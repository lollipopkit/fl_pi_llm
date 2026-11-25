// The host-facing half of fl_pi_llm.
//
// Everything the Dart side can ask for goes through `__fl.dispatch(method,
// payload)`, which always resolves — to `{ok: true, value}` or `{ok: false,
// error}` — so the Rust side never has to turn a JS exception into a message.
// Everything the JS side needs from the host goes through `__host` (see
// web.js for the Web platform part of it):
//
//   __host.call(name, payloadJson, bytes?) -> Promise<string>   answered by Dart
//   __host.notify(name, payloadJson)                             fire and forget
//   __host.emit(payloadJson)                                     an event for Dart
//
// A chat is a pi-durable Harness over a storage of its own (a SQLite file,
// through `db.js`), opened while the chat is. Its conversations are the
// chat's versions: an edit or a regeneration forks the conversation at the
// entry it goes back to, so every version stays, sharing what came before.
// The chat stands on one conversation, `current`, and may stand on an
// earlier entry of it, `tip`, until the next prompt forks there.
//
// The host sees pi-durable's entries and events in the shape it has always
// had (`type: message | compaction | custom`, a `parentId` chain, the
// harness event names); `hostEntry` and `Session.#diffView` translate.
//
// Imported first so every global pi reaches for exists before its modules run.
import './web.js';

import { BACKGROUND_CONTEXT } from '@earendil-works/chord/context';
import {
  createRegistry,
  defineDoc,
  defineExtension,
  defineTool,
  Harness,
  hook,
  LiveDoc,
  section,
  ToolTask,
} from '@earendil-works/pi-durable';
import { SqliteStorage } from '@earendil-works/pi-durable/storage/sqlite';
import { listChats, openChat, removeChat } from './db.js';
import { legacyFiles, migrate, removeLegacy } from './legacy.js';
import { hostEntry } from './entry.js';
import { exportEntries, exportPage, exportUids, importPage } from './sync.js';
import { ChatTree } from './tree.js';
import { CUSTOM_APIS, listedProviders, models, modelInfo, probeModels, providerInfo, resolveModel, setCustomProviders } from './providers.js';

const host = globalThis.__host;
const BG = BACKGROUND_CONTEXT;

const hostCall = async (name, payload) => JSON.parse(await host.call(name, JSON.stringify(payload)));
const emit = (payload) => host.emit(JSON.stringify(payload));

const PI_VERSION = '1.6.0';

// ---------------------------------------------------------------------------
// Storage

/**
 * pi-durable names a model by `{provider, modelId}` and looks it up again for
 * every request. A custom provider's model its list does not have (an id the
 * user typed) is still one `resolveModel` can make.
 */
const harnessModels = new Proxy(models, {
  get(target, key) {
    if (key === 'getModel') {
      return (provider, id) => {
        const m = target.getModel(provider, id);
        if (m) return m;
        try { return resolveModel({ provider, id }); } catch { return undefined; }
      };
    }
    const v = target[key];
    return typeof v === 'function' ? v.bind(target) : v;
  },
});

/** Where a chat stands, kept with it. */
const ChatDoc = defineDoc({
  kind: 'fl.chat',
  version: 1,
  scope: 'session',
  history: 'latest',
  // `tip`: an entry of `current` to continue from, -1 before the first entry,
  // null at the end.
  initial: () => ({ current: null, tip: null, name: null }),
  // pi 1.4.0 asks every document for a checkpoint policy, with no default.
  // The whole state is three fields, written in one go: a base every time.
  checkpointWhen: () => true,
});

/** Every chat in storage, by id, with when it was made and last written. */
const storedChats = () => new Map(listChats().map((c) => [c.id, c]));

/**
 * Runs [fn] after whatever else is being done to chat [id]'s file: opening
 * its session, a legacy move, a sync, deleting it. Two harnesses never have
 * one file open.
 */
const queues = new Map();
function onChat(id, fn) {
  const run = (queues.get(id) ?? Promise.resolve()).then(fn);
  const tail = run.then(() => {}, () => {});
  queues.set(id, tail);
  tail.then(() => { if (queues.get(id) === tail) queues.delete(id); });
  return run;
}

/** A harness over chat [id]'s file, for work outside an open session. */
async function openHarness(id) {
  const db = openChat(id);
  const storage = await SqliteStorage.open(db);
  try {
    const harness = await Harness.open(storage, { models: harnessModels, registry: createRegistry() }, BG);
    return { id, db, storage, harness, shape: new ChatTree(db) };
  } catch (e) {
    await storage.close(BG).catch(() => {});
    throw e;
  }
}

/**
 * Moves chat [id] out of a session from before pi-durable (TODO: remove with
 * legacy.js). The chat's file is made again from it: a move cut short leaves
 * the old session, and is started over. On the chat's queue ([onChat]).
 */
async function migrateLegacy(id, file) {
  removeChat(id);
  const { harness } = await openHarness(id);
  try {
    const moved = await migrate(harness, file, BG);
    await setPlace(harness, moved.current, moved.tip, moved.name);
  } finally {
    await harness.close(BG);
  }
  await removeLegacy(file);
}

/**
 * Runs [fn] on chat [id]: on its session when it is open, else on a harness
 * opened for it alone — moved out of a legacy session first, if one is left.
 */
function withChat(id, fn) {
  return onChat(id, async () => {
    const open = sessions.get(id);
    if (open) return open.exclusive(() => fn(open));
    // TODO: remove with legacy.js.
    const legacy = (await legacyFiles()).get(id);
    if (legacy) await migrateLegacy(id, legacy);
    const chat = await openHarness(id);
    try {
      return await fn(chat);
    } finally {
      await chat.harness.close(BG);
    }
  });
}

/** Where standing on entry [id] puts a chat: the version it ends, or before what follows it. */
function placeOf(shape, id) {
  const leaf = shape.conversationEndingAt(id);
  return { current: leaf ?? shape.entries.get(id).conversationId, tip: leaf != null ? null : id };
}

/** The last entry of the branch [chat] stands on, or null. */
async function branchEnd({ harness, shape }) {
  const place = await harness.snapshot(ChatDoc, BG);
  if (place?.tip === -1) return null;
  await shape.refresh();
  const current = place?.current ?? (await harness.root(BG)).id;
  return shape.history(current, place?.tip ?? Infinity).at(-1) ?? null;
}

async function setPlace(harness, current, tip, name) {
  await harness.commit(async (tx) => {
    const doc = await tx.doc(ChatDoc);
    doc.current = current;
    doc.tip = tip;
    doc.name = name;
  }, BG);
}

// ---------------------------------------------------------------------------
// The host's shapes

/** A settled input submission as the host's run result. */
function runResult(settled) {
  if (settled.status === 'done') return { status: 'completed', tipId: String(settled.answer) };
  if (settled.reason === 'aborted') return { status: 'aborted' };
  const detail = settled.detail;
  const message = typeof detail === 'string' ? detail : detail?.message ?? settled.reason;
  return { status: 'failed', error: { message } };
}

// ---------------------------------------------------------------------------
// Sessions

/** @type {Map<string, Session>} */
const sessions = new Map();

function getSession(id) {
  const s = sessions.get(id);
  if (!s) throw new Error(`Session is not open: ${id}`);
  return s;
}

/** A tool defined by the host, executed there. */
function hostTool(sessionId, def) {
  return defineTool({
    name: def.name,
    description: def.description ?? '',
    parameters: def.parameters ?? { type: 'object', properties: {} },
    ...(def.executionMode ? { executionMode: def.executionMode } : {}),
    // What a tool returns is the host's to bound.
    outputLimits: { maxBytes: 16 << 20, maxLines: 1 << 20 },
    execute: async (args, api, context) => {
      const signal = context?.abortSignal;
      const toolCallId = api.callId;
      const onAbort = () => host.notify('tool.cancel', JSON.stringify({ sessionId, toolCallId }));
      signal?.addEventListener('abort', onAbort, { once: true });
      try {
        const res = await hostCall('tool', { sessionId, toolCallId, name: def.name, args });
        if (res.error != null) throw new Error(String(res.error));
        return {
          // pi 1.3.0 named the result's content `output`; `content` is read no more.
          output: res.content ?? [],
          details: res.details ?? null,
          ...(res.terminate ? { control: { terminate: true } } : {}),
        };
      } finally {
        signal?.removeEventListener('abort', onAbort);
      }
    },
  });
}

const DEFAULT_COMPACTION = { enabled: true, reserveTokens: 16384, keepRecentTokens: 20000 };

class Session {
  constructor(id) {
    this.id = id;
    this.approval = false;
    this.tools = [];
    this.compaction = { ...DEFAULT_COMPACTION };
    this.stream = undefined;
    /** Characters of each block of the answer in flight the host was sent. */
    this.streamed = new Map();
    /** The id of the newest entry the host was shown on the current branch. */
    this.lastId = null;
    this.queue = Promise.resolve();
  }

  /**
   * Runs [fn] after what came before it here. Whatever writes takes a turn —
   * a prompt until it is admitted, a sync's import — so an import never
   * writes into a conversation a run has just started on.
   */
  exclusive(fn) {
    const run = this.queue.then(fn);
    this.queue = run.then(() => {}, () => {});
    return run;
  }

  static async open(p) {
    const s = new Session(p.sessionId);
    try {
      await s.#init(p);
    } catch (e) {
      await s.close().catch(() => {});
      throw e;
    }
    return s;
  }

  async #init(p) {
    this.model = resolveModel(p.model);
    this.thinkingLevel = p.thinkingLevel ?? 'off';
    this.systemPrompt = p.systemPrompt ?? '';
    this.approval = !!p.approval;
    this.compaction = { ...DEFAULT_COMPACTION, ...(p.compaction ?? {}) };

    // TODO: remove with legacy.js. `session.open` runs on the chat's queue.
    const legacy = (await legacyFiles()).get(this.id);
    if (legacy) await migrateLegacy(this.id, legacy);

    this.db = openChat(this.id);
    this.storage = await SqliteStorage.open(this.db);
    this.shape = new ChatTree(this.db);
    const session = this;
    this.registry = createRegistry();
    this.#installTools(p.tools ?? []);
    this.harness = await Harness.open(this.storage, {
      models: harnessModels,
      registry: this.registry,
      settings: {
        get compaction() { return session.compaction; },
      },
      onReport(report) {
        if (report.kind === 'task_faulted' || report.kind === 'storage_failed') {
          emit({
            type: 'session.event',
            sessionId: session.id,
            event: { type: 'fault', kind: report.kind, error: { message: errorText(report.error) } },
          });
        }
      },
    }, BG);

    const place = await this.harness.snapshot(ChatDoc, BG);
    this.current = place?.current != null
      ? await this.harness.conversation(place.current, BG)
      : await this.harness.root(BG);
    this.tip = place?.tip ?? null;
    this.name = place?.name ?? null;
    await this.#configure(this.current);
    this.interrupted = (await this.harness.inspect(BG)).tasks.length > 0;
    await this.#watch();
  }

  /** The host's tools, and its say over every call when it asks for one. */
  #installTools(defs) {
    this.tools = defs.map((t) => hostTool(this.id, t));
    this.registry.install(defineExtension({
      name: 'host',
      tools: this.tools,
      // As given, read at every request: the host may change it while open.
      sections: [section('system', () => this.systemPrompt || undefined, { tag: false })],
      hooks: [hook(ToolTask, {
        beforeTool: async (call) => {
          if (!this.approval) return undefined;
          const res = await hostCall('approve', {
            sessionId: this.id, toolCallId: call.id, name: call.name, args: call.arguments,
          });
          return res.block ? { block: res.reason ?? 'Denied by the user' } : undefined;
        },
      })],
    }));
  }

  /** What [conv] runs with: what the host asked for last. */
  async #configure(conv) {
    await conv.configure({
      model: { provider: this.model.provider, modelId: this.model.id },
      thinkingLevel: this.thinkingLevel,
      tools: this.tools,
    }, BG);
  }

  async #setPlace(current, tip, name = this.name) {
    await setPlace(this.harness, current, tip, name);
  }

  /** Forwards the current conversation's view changes, in the host's event shape. */
  async #watch() {
    await this.stream?.stop?.();
    const last = (await this.#branchIds()).at(-1);
    this.lastId = last == null ? null : String(last);
    this.streaming = false;
    this.streamed = new Map();
    this.toolArgs = new Map();
    this.toolSlots = new Map();
    this.stream = await this.current.watch(BG);
    let prev = this.stream.value;
    this.seenEntryId = prev.entries.at(-1)?.id ?? 0;
    const prevTools = prev.docs?.['pi.live']?.tools ?? [];
    if (prevTools.length > 0) {
      const activeIds = new Set(prevTools.map((s) => s.callId));
      for (const record of prev.entries) this.#rememberToolArgs(record, activeIds);
      for (const slot of prevTools) {
        this.toolSlots.set(slot.callId, {
          taskId: slot.taskId,
          started: slot.status !== 'pending',
          ended: slot.status === 'done',
          name: slot.name,
          output: slot.output,
          details: slot.details,
        });
      }
    }
    this.stream.start(async (call) => {
      if (call.kind !== 'value') return;
      const next = call.value;
      const out = this.#diffView(prev, next);
      prev = next;
      for (const ev of out) emit({ type: 'session.event', sessionId: this.id, event: ev });
    });
  }

  #rememberToolArgs(record, filterIds = null) {
    const m = record?.model?.[0];
    if (m?.role !== 'assistant' || !Array.isArray(m.content)) return;
    for (const c of m.content) {
      if (c?.type === 'toolCall' && c.id != null && (!filterIds || filterIds.has(c.id))) {
        this.toolArgs.set(c.id, c.arguments ?? {});
      }
    }
  }

  #clearEndedToolSlots() {
    for (const [id, state] of this.toolSlots) {
      if (state.ended) {
        this.toolSlots.delete(id);
        this.toolArgs.delete(id);
      }
    }
  }

  /** The text and thinking of [m] the host has not been sent yet, as deltas. */
  #catchUp(m) {
    const out = [];
    (Array.isArray(m.content) ? m.content : []).forEach((c, contentIndex) => {
      const [type, full] = c.type === 'text' ? ['text_delta', c.text] : c.type === 'thinking' ? ['thinking_delta', c.thinking] : [];
      if (!type || !full) return;
      const sent = this.streamed.get(contentIndex) ?? 0;
      if (full.length <= sent) return;
      this.streamed.set(contentIndex, full.length);
      out.push({ type: 'message_update', event: { type, contentIndex, delta: full.slice(sent) } });
    });
    return out;
  }

  #added(record) {
    const h = hostEntry(record, this.lastId);
    if (!h) return [];
    this.lastId = h.id;
    return [{ type: 'entry_added', entry: h }];
  }

  #emitRunEnd(out, prevLive, nextLive, failureChanged) {
    this.streaming = false;
    this.streamed = new Map();
    this.toolArgs.clear();
    out.push({ type: 'turn_end' });
    const fail = nextLive?.runFailure;
    if (fail && (failureChanged || (prevLive?.run && fail.taskId === prevLive.run.taskId))) {
      out.push(fail.reason === 'aborted'
        ? { type: 'run_end', status: 'aborted' }
        : { type: 'run_end', status: 'failed', error: { message: fail.detail ?? fail.reason } });
    } else {
      out.push({ type: 'run_end', status: 'completed', tipId: this.lastId });
    }
  }

  #diffView(prev, next) {
    const out = [];
    const prevLive = prev.docs?.['pi.live'];
    const nextLive = next.docs?.['pi.live'];
    const newEntries = next.entries.filter((r) => r.id > this.seenEntryId);
    const isRunAssistant = (r) => r.kind === 'pi.assistant' && r.model?.[0]?.role === 'assistant';
    const isRunToolResult = (r) => r.kind === 'pi.tool-result' && r.model?.[0]?.role === 'toolResult';
    const sameInputs = (a = [], b = []) => a.length === b.length && a.every((v, i) => v === b[i]);

    const runStarted = !prevLive?.run && !!nextLive?.run;
    const runEnded = !!prevLive?.run && !nextLive?.run;
    const failureChanged = nextLive?.runFailure != null && nextLive.runFailure !== prevLive?.runFailure;
    const runReplaced = !!prevLive?.run && !!nextLive?.run && (
      failureChanged || !sameInputs(prevLive.run.inputs, nextLive.run.inputs)
    );
    // A fast run can start and finish within one folded watch callback.
    const foldedRun = !prevLive?.run && !nextLive?.run && (
      failureChanged || newEntries.some(isRunAssistant)
    );

    if (runStarted || foldedRun) {
      out.push({ type: 'run_start' }, { type: 'turn_start' });
    } else if (runReplaced) {
      this.#clearEndedToolSlots();
      this.#emitRunEnd(out, prevLive, nextLive, failureChanged);
      out.push({ type: 'run_start' }, { type: 'turn_start' });
    } else if (prevLive?.run && nextLive?.run && prevLive.run.taskId !== nextLive.run.taskId) {
      this.#clearEndedToolSlots();
      out.push({ type: 'turn_end' }, { type: 'turn_start' });
    }

    const entryById = new Map(next.entries.map((r) => [r.id, r]));
    for (const record of newEntries) {
      this.seenEntryId = record.id;
      const m = record.model?.[0];
      if (isRunAssistant(record)) {
        this.#clearEndedToolSlots();
        this.#rememberToolArgs(record);
        if (!this.streaming) {
          this.streamed = new Map();
          out.push({ type: 'message_start', message: { ...m, content: [] } });
        }
        out.push(...this.#catchUp(m));
        this.streaming = false;
        this.streamed = new Map();
        out.push({ type: 'message_end', message: m }, ...this.#added(record));
      } else if (isRunToolResult(record)) {
        const callId = m.toolCallId;
        if (callId != null) {
          const state = this.toolSlots.get(callId) ?? {
            taskId: undefined, started: false, ended: false, name: m.toolName ?? '', output: undefined, details: undefined,
          };
          if (!state.started) {
            state.started = true;
            const args = this.toolArgs.get(callId) ?? {};
            this.toolArgs.delete(callId);
            out.push({
              type: 'tool_start',
              toolCallId: callId,
              toolName: m.toolName ?? state.name,
              args,
            });
          }
          if (!state.ended) {
            state.ended = true;
            out.push({ type: 'tool_end', toolCallId: callId, toolName: m.toolName ?? state.name, isError: !!m.isError });
          }
          this.toolSlots.set(callId, state);
        }
        out.push({ type: 'message_end', message: m }, ...this.#added(record));
      } else if (record.kind === 'pi.user' && m && m.role !== 'system') {
        out.push({ type: 'message_end', message: m }, ...this.#added(record));
      } else {
        out.push(...this.#added(record));
      }
    }

    const liveMsg = nextLive?.generation?.message;
    if (liveMsg?.role === 'assistant') {
      if (!this.streaming) {
        this.streaming = true;
        this.streamed = new Map();
        out.push({ type: 'message_start', message: { ...liveMsg, content: [] } });
      }
      out.push(...this.#catchUp(liveMsg));
    }

    const prevRetry = prevLive?.generation?.retry;
    const nextRetry = nextLive?.generation?.retry;
    if (!prevRetry && nextRetry) {
      out.push({ type: 'retry_start', attempt: nextLive.generation.attempt, at: nextRetry.at, message: nextRetry.error });
    } else if (prevRetry && !nextRetry) {
      out.push({ type: 'retry_end', attempt: prevLive.generation.attempt });
    } else if (prevRetry && nextRetry && (prevRetry !== nextRetry || prevLive.generation.attempt !== nextLive.generation.attempt)) {
      out.push(
        { type: 'retry_end', attempt: prevLive.generation.attempt },
        { type: 'retry_start', attempt: nextLive.generation.attempt, at: nextRetry.at, message: nextRetry.error },
      );
    }

    const nextSlots = nextLive?.tools ?? [];
    const nextCallIds = new Set(nextSlots.map((s) => s.callId));
    for (const [callId, state] of this.toolSlots) {
      if (nextCallIds.has(callId)) continue;
      if (state.started && !state.ended) {
        out.push({ type: 'tool_end', toolCallId: callId, toolName: state.name, isError: true });
      }
      this.toolSlots.delete(callId);
      this.toolArgs.delete(callId);
    }
    for (const slot of nextSlots) {
      let state = this.toolSlots.get(slot.callId);
      if (state != null && slot.taskId != null && state.taskId != null && state.taskId !== slot.taskId) {
        if (state.started && !state.ended) {
          out.push({ type: 'tool_end', toolCallId: slot.callId, toolName: state.name, isError: true });
        }
        state = undefined;
      }
      state ??= {
        taskId: slot.taskId, started: false, ended: false, name: slot.name, output: undefined, details: undefined,
      };
      if (slot.taskId != null) state.taskId = slot.taskId;
      if (!state.started && (slot.status === 'running' || slot.status === 'done')) {
        state.started = true;
        const args = this.toolArgs.get(slot.callId) ?? {};
        this.toolArgs.delete(slot.callId);
        out.push({
          type: 'tool_start',
          toolCallId: slot.callId,
          toolName: slot.name,
          args,
        });
      }
      if (slot.output !== state.output || slot.details !== state.details) {
        state.output = slot.output;
        state.details = slot.details;
        if (slot.output !== undefined || slot.details !== undefined) {
          out.push({ type: 'tool_update', toolCallId: slot.callId, toolName: slot.name, output: slot.output, details: slot.details });
        }
      }
      if (!state.ended && slot.status === 'done') {
        state.ended = true;
        const entry = slot.entry != null ? entryById.get(slot.entry) : undefined;
        const isError = slot.entry == null ? true : !!entry?.model?.[0]?.isError;
        out.push({ type: 'tool_end', toolCallId: slot.callId, toolName: slot.name, isError });
      }
      this.toolSlots.set(slot.callId, state);
    }

    const prevComp = new Map((prevLive?.compactions ?? []).map((c) => [c.taskId, c]));
    const nextComp = new Map((nextLive?.compactions ?? []).map((c) => [c.taskId, c]));
    for (const [id, c] of nextComp) {
      if (!prevComp.has(id)) out.push({ type: 'compaction_start', reason: c.trigger });
    }
    for (const [id, c] of prevComp) {
      if (!nextComp.has(id)) out.push({ type: 'compaction_end', reason: c.trigger });
    }

    const nextUsage = next.docs?.['pi.usage'];
    if (nextUsage != null && nextUsage !== prev.docs?.['pi.usage']) {
      out.push({ type: 'usage', usage: nextUsage });
    }

    if (runEnded || foldedRun) {
      this.#emitRunEnd(out, prevLive, nextLive, failureChanged);
    }

    return out;
  }

  /** The ids of the current branch's shown entries, root first. */
  async #branchIds() {
    await this.shape.refresh();
    if (this.tip === -1) return [];
    return this.shape.history(this.current.id, this.tip ?? Infinity);
  }

  /** [ids], a run of one history, as host entries; the first after its parent. */
  async #hostEntries(ids, parentId = ids.length ? this.shape.parentOf(ids[0]) : null) {
    const out = [];
    let prev = parentId == null ? null : String(parentId);
    for (const id of ids) {
      const h = hostEntry((await this.storage.entry(id, BG)).entry, prev);
      out.push(h);
      prev = h.id;
    }
    return out;
  }

  /**
   * The last [limit] entries of the current branch before [before] (its end
   * when null), root first, and whether there are more before them. A page
   * starts at a user message, so a reply is never cut from what it answers;
   * each user message carries its `versions` when it has more than one.
   */
  async page(limit = Infinity, before = null) {
    const ids = await this.#branchIds();
    const end = before == null ? ids.length : ids.indexOf(Number(before));
    if (end < 0) throw new Error(`No entry ${before} on the branch`);
    if (!(limit > 0)) return { entries: [], more: end > 0 };
    let start = Math.max(0, end - limit);
    while (start > 0 && !this.shape.entries.get(ids[start]).user) start--;
    const entries = await this.#hostEntries(ids.slice(start, end));
    for (const e of entries) {
      if (!this.shape.entries.get(e.seq).user) continue;
      const versions = this.shape.versions(e.seq);
      if (versions.length < 2) continue;
      e.versions = await Promise.all(versions.map(async (id) => hostEntry((await this.storage.entry(id, BG)).entry, e.parentId)));
    }
    return { entries, more: start > 0 };
  }

  /** The current branch, root first. */
  async branch() {
    return (await this.page()).entries;
  }

  /** Every entry of every version, each once. Reads them all. */
  async tree() {
    await this.shape.refresh();
    return Promise.all(this.shape.all().map(async (id) => {
      const p = this.shape.parentOf(id);
      return hostEntry((await this.storage.entry(id, BG)).entry, p == null ? null : String(p));
    }));
  }

  /** One entry by id, whichever version it is in, or null. */
  async entry(id) {
    await this.shape.refresh();
    const n = Number(id);
    if (!this.shape.entries.has(n)) return null;
    return (await this.#hostEntries([n]))[0];
  }

  /**
   * The conversation the next write goes to: the current one, forked first
   * when the chat stands on an earlier entry of it.
   */
  async writable() {
    if (this.tip == null) return this.current;
    const conv = this.tip === -1
      ? await this.harness.createConversation({ ownership: { kind: 'ownerless' } }, BG)
      : await this.current.fork(this.tip, { ownership: { kind: 'ownerless' } }, BG);
    await this.#configure(conv);
    this.current = conv;
    this.tip = null;
    await this.#setPlace(conv.id, null);
    await this.#watch();
    return conv;
  }

  /**
   * Stands on [targetId] (null: before the first entry). On a version's last
   * entry that is the version; elsewhere the next write forks there.
   */
  async navigate(targetId) {
    if (targetId == null) {
      this.tip = -1;
    } else {
      const id = Number(targetId);
      await this.shape.refresh();
      if (!this.shape.entries.has(id)) throw new Error(`No entry ${targetId}`);
      const place = placeOf(this.shape, id);
      this.current = await this.harness.conversation(place.current, BG);
      this.tip = place.tip;
      await this.#configure(this.current);
    }
    await this.#setPlace(this.current.id, this.tip);
    await this.#watch();
  }

  /** Stands on the newest leaf under [entryId]: the version it starts. */
  async switchTo(entryId) {
    await this.shape.refresh();
    const id = Number(entryId);
    if (!this.shape.entries.has(id)) throw new Error(`No entry ${entryId}`);
    await this.navigate(String(this.shape.leafOf(id)));
  }

  /** Admits [submission] to the conversation the next write goes to. */
  submit(submission) {
    return this.exclusive(async () => (await this.writable()).submit(submission, BG));
  }

  /** Writes an entry the model may see, without running it. */
  async write(entry) {
    const settled = await (await this.submit({ type: 'write', entry })).wait(BG);
    if (settled.status !== 'done') throw new Error(`Not written: ${settled.reason}`);
    return String(settled.entry);
  }

  async prompt(text, images) {
    const content = [{ type: 'text', text }, ...(images ?? [])];
    return runResult(await (await this.submit({ type: 'input', content })).wait(BG));
  }

  /** Picks up what a previous launch left running, and waits for it. */
  async resume() {
    this.harness.resume();
    await this.current.waitForIdle(BG);
    this.interrupted = false;
    const fail = (await this.harness.snapshot(LiveDoc, this.current.id, BG))?.runFailure;
    if (fail) {
      return fail.reason === 'aborted'
        ? { status: 'aborted' }
        : { status: 'failed', error: { message: fail.detail ?? fail.reason } };
    }
    const lastId = (await this.#branchIds()).at(-1);
    const last = lastId == null ? undefined : (await this.storage.entry(lastId, BG)).entry.model?.[0];
    if (last?.role === 'assistant' && last.stopReason === 'aborted') return { status: 'aborted' };
    if (last?.role === 'assistant' && last.stopReason === 'error') return { status: 'failed', error: { message: last.errorMessage ?? 'error' } };
    return { status: 'completed', tipId: this.lastId };
  }

  async compact(instructions) {
    const taskId = await this.exclusive(async () => (await this.writable()).compact(instructions || undefined, BG));
    const { outcome } = (await this.harness.waitForTask(taskId, BG)).state;
    if (outcome.status !== 'completed') {
      return { status: outcome.status === 'aborted' ? 'aborted' : 'failed', error: outcome.error ?? null };
    }
    const placedId = outcome.result?.submissionId;
    if (placedId === undefined) return { status: 'declined' };
    const placed = await (await this.harness.submission(placedId, BG)).wait(BG);
    return placed.status === 'done' ? { status: 'completed' } : { status: 'declined', reason: placed.reason };
  }

  /**
   * The chat as a session file of pi's coding agent (session format v3), so
   * `pi` can show and continue it: every version, the one the chat stands on
   * last, since pi continues from a file's last entry.
   */
  async exportPi(cwd) {
    const iso = (ms) => new Date(ms || Date.now()).toISOString();
    const createdAt = (await this.db.get('SELECT created_at FROM fl_chat'))?.created_at;
    const tree = await this.tree();
    const lastId = (await this.#branchIds()).at(-1);
    const tip = lastId == null ? undefined : await this.entry(lastId);
    const lines = [{ type: 'session', version: 3, id: this.id, timestamp: iso(createdAt ?? tree[0]?.timestamp), cwd }];
    const v3 = (e) => {
      const base = { id: e.id, parentId: e.parentId, timestamp: iso(e.timestamp) };
      switch (e.type) {
        case 'message':
          return { type: 'message', ...base, message: e.message };
        case 'compaction':
          return { type: 'compaction', ...base, summary: e.summary, firstKeptEntryId: e.firstKeptEntryId ?? e.id, tokensBefore: e.tokensBefore ?? 0 };
        case 'custom':
          return { type: 'custom', ...base, customType: e.customType, data: e.data };
        default:
          return null;
      }
    };
    for (const e of tree) if (e.id !== tip?.id) lines.push(v3(e));
    if (this.name) {
      // Beside the tip rather than on its branch, so it is not where pi continues.
      lines.push({ type: 'session_info', id: `name-${this.id}`, parentId: tip?.parentId ?? null, timestamp: iso(), name: this.name });
    }
    if (tip) lines.push(v3(tip));
    return `${lines.filter(Boolean).map((l) => JSON.stringify(l)).join('\n')}\n`;
  }

  async setModel(ref) {
    this.model = resolveModel(ref);
    await this.#configure(this.current);
  }

  async setThinkingLevel(level) {
    this.thinkingLevel = level;
    await this.#configure(this.current);
  }

  setSystemPrompt(text) {
    this.systemPrompt = text ?? '';
  }

  async setTools(defs) {
    this.#installTools(defs);
    await this.#configure(this.current);
  }

  async setName(name) {
    this.name = name ?? null;
    await this.#setPlace(this.current.id, this.tip, this.name);
  }

  async close() {
    await this.stream?.stop?.();
    this.stream = undefined;
    // The harness closes its storage; one that never opened leaves it to us.
    if (this.harness) await this.harness.close(BG);
    else await this.storage?.close(BG);
  }
}

// ---------------------------------------------------------------------------
// Dispatch

const methods = {
  /** Version info, and a cheap way to see the runtime is up. */
  'runtime.info': () => ({ pi: PI_VERSION, piAi: PI_VERSION, piDurable: PI_VERSION, apis: Object.keys(CUSTOM_APIS) }),

  /** Every provider and its models: the built-in catalog, then custom ones. */
  'providers.list': () => listedProviders().map(providerInfo),

  /** Models whose provider has usable auth. */
  'providers.available': async (p) =>
    (await models.getAvailable(p.providerId ?? undefined)).map(modelInfo),

  /** The models an unregistered custom provider's endpoint lists. */
  'providers.probe': (p) => probeModels(p.provider, p.credential ?? undefined),

  /** Replaces the custom providers. */
  'providers.setCustom': (p) => { setCustomProviders(p.providers ?? []); return null; },

  /**
   * Refetches the model lists of dynamic providers — custom ones and the
   * built-in ones that list remotely. Errors are per provider.
   */
  'providers.refresh': async (p) => {
    const r = await models.refresh({
      ...(p.providers ? { providers: p.providers } : {}),
      force: !!p.force,
      allowNetwork: true,
    });
    return { errors: Object.fromEntries([...r.errors].map(([k, e]) => [k, e?.message ?? String(e)])) };
  },

  /** Where each provider with usable auth gets it: `stored credential`, or an env var. */
  'providers.auth': async () => {
    const out = {};
    for (const p of listedProviders()) {
      const auth = await models.checkAuth(p.id);
      if (auth) out[p.id] = auth.source;
    }
    return out;
  },

  /** Whether a provider's auth is set up, as pi-ai sees it. */
  'providers.checkAuth': async (p) => (await models.checkAuth(p.providerId)) ?? null,

  /** Every stored session, newest first; legacy ones not moved yet too. */
  'sessions.list': async () => {
    const chats = storedChats();
    // TODO: remove with legacy.js.
    for (const [id, f] of await legacyFiles()) {
      if (!chats.has(id)) chats.set(id, { id, createdAt: f.mtimeMs, modifiedAt: f.mtimeMs });
    }
    return [...chats.values()]
      .sort((a, b) => b.createdAt - a.createdAt)
      .map((c) => ({ id: c.id, createdAt: c.createdAt, modifiedAt: c.modifiedAt, name: null }));
  },

  /**
   * Moves every session from before pi-durable that is left, one at a time
   * (TODO: remove with legacy.js). Returns those that could not be moved,
   * by id, with why; they stay, and opening one tries again.
   */
  'sessions.migrate': async () => {
    const failed = {};
    for (const id of (await legacyFiles()).keys()) {
      try {
        await onChat(id, async () => {
          // Moved meanwhile, by opening it.
          const file = (await legacyFiles()).get(id);
          if (file && !sessions.has(id)) await migrateLegacy(id, file);
        });
      } catch (e) {
        failed[id] = errorText(e);
      }
    }
    return { failed };
  },

  /** Deletes a stored session. It must not be open. */
  'sessions.delete': (p) => onChat(p.sessionId, async () => {
    if (sessions.has(p.sessionId)) throw new Error(`Session is open: ${p.sessionId}`);
    removeChat(p.sessionId);
    // TODO: remove with legacy.js.
    const legacy = (await legacyFiles()).get(p.sessionId);
    if (legacy) await removeLegacy(legacy);
    return null;
  }),

  /**
   * A page of the chat for another device: see `sync.js`. `after` is the
   * last page's `next`; the chat need not be open.
   */
  'sessions.export': async (p) => {
    const id = p.sessionId;
    // Nothing to read, and no file made for it. TODO: legacy, with legacy.js.
    if (!sessions.has(id) && !storedChats().has(id) && !(await legacyFiles()).has(id)) {
      return { entries: [], next: null, tip: null };
    }
    return withChat(id, async (chat) => exportPage(chat, await branchEnd(chat), p.after ?? null, p.maxChars ?? undefined));
  },

  /**
   * The entries of the chat after the one numbered `after`, as `{id, uid}`:
   * see `sync.js`. The chat need not be open.
   */
  'sessions.uids': async (p) => {
    const id = p.sessionId;
    // A legacy one is moved over when opened. TODO: legacy, with legacy.js.
    if (!sessions.has(id) && !storedChats().has(id) && !(await legacyFiles()).has(id)) return [];
    return withChat(id, async (chat) => exportUids(chat, p.after ?? null));
  },

  /** The entries of the chat whose uid is among `uids`, as an export holds them. */
  'sessions.entries': async (p) => {
    const id = p.sessionId;
    if (!sessions.has(id) && !storedChats().has(id) && !(await legacyFiles()).has(id)) return [];
    return withChat(id, async (chat) => exportEntries(chat, p.uids ?? []));
  },

  /**
   * Writes what a page of another device's export has and the chat lacks,
   * creating the chat when there is none. `tip`, given with the last page of
   * a chat new here, is the entry to stand on: where the other device stood.
   */
  'sessions.import': (p) => withChat(p.sessionId, async (chat) => {
    const { added, orphans, known } = await importPage(chat, p.entries ?? []);
    const tipId = p.tip == null ? undefined : known.get(p.tip);
    if (tipId != null) {
      if (chat instanceof Session) {
        await chat.navigate(String(tipId));
      } else {
        await chat.shape.refresh();
        const place = placeOf(chat.shape, tipId);
        const name = (await chat.harness.snapshot(ChatDoc, BG))?.name ?? null;
        await setPlace(chat.harness, place.current, place.tip, name);
      }
    }
    return { added, orphans };
  }),

  /**
   * Opens a session, creating it when it does not exist. Returns the entries
   * on its current branch and whether a previous launch left work running.
   */
  'session.open': (p) => onChat(p.sessionId, async () => {
    if (sessions.has(p.sessionId)) throw new Error(`Session is already open: ${p.sessionId}`);
    const s = await Session.open(p);
    sessions.set(p.sessionId, s);
    return {
      interrupted: s.interrupted ? [{ operationId: 'run', kind: 'run' }] : [],
      name: s.name,
    };
  }),

  /** Resolves when the run ends. */
  'session.prompt': async (p) => ({ result: await getSession(p.sessionId).prompt(p.text, p.images) }),

  /** Picks up a run a previous launch left open, or retries after an error. */
  'session.resume': async (p) => ({ result: await getSession(p.sessionId).resume() }),

  'session.abort': async (p) => {
    const s = getSession(p.sessionId);
    await s.current.abort(BG);
    return null;
  },

  /** The current branch, root first. Reads it all: see `session.page`. */
  'session.entries': async (p) => ({ entries: await getSession(p.sessionId).branch() }),

  /** The last `limit` entries of the current branch before `before`: see `Session.page`. */
  'session.page': async (p) => getSession(p.sessionId).page(p.limit ?? Infinity, p.before ?? null),

  /** Every entry in the session, all versions. Reads them all. */
  'session.tree': async (p) => ({ entries: await getSession(p.sessionId).tree() }),

  /** One entry by id, whichever version it is in — including compacted ones. */
  'session.entry': async (p) => ({ entry: await getSession(p.sessionId).entry(p.entryId) }),

  /**
   * Stands on `targetId` (null: before the first entry). The next prompt then
   * continues from there, leaving the old version as it is. This is how a
   * message is edited or an answer regenerated.
   */
  'session.navigate': async (p) => {
    await getSession(p.sessionId).navigate(p.targetId ?? null);
    return null;
  },

  /** Stands on the version the entry `entryId` starts: its newest leaf. */
  'session.switchTo': async (p) => {
    await getSession(p.sessionId).switchTo(p.entryId);
    return null;
  },

  /**
   * Appends messages without running the model — an import, or a result the
   * host produced itself.
   */
  'session.append': async (p) => {
    const s = getSession(p.sessionId);
    const ids = [];
    for (const m of p.messages ?? []) ids.push(await s.write({ kind: 'fl.message', model: [m] }));
    return { ids };
  },

  /**
   * Appends an entry of the host's own kind — something to show, which the
   * model never sees.
   */
  'session.appendCustom': async (p) => ({
    id: await getSession(p.sessionId).write({
      kind: 'fl.custom',
      data: { customType: p.customType, data: p.data ?? null, timestamp: Date.now() },
    }),
  }),

  /** Compacts now, whatever the thresholds say. */
  'session.compact': async (p) => {
    return { compaction: await getSession(p.sessionId).compact(p.customInstructions) };
  },

  /** The chat as a session file `pi` reads: see `Session.exportPi`. */
  'session.exportPi': async (p) => ({ text: await getSession(p.sessionId).exportPi(p.cwd ?? '/') }),

  'session.setModel': async (p) => { await getSession(p.sessionId).setModel(p.model); return null; },

  'session.setSystemPrompt': (p) => { getSession(p.sessionId).setSystemPrompt(p.systemPrompt); return null; },

  'session.setThinkingLevel': async (p) => { await getSession(p.sessionId).setThinkingLevel(p.thinkingLevel); return null; },

  'session.setTools': async (p) => { await getSession(p.sessionId).setTools(p.tools ?? []); return null; },

  'session.setApproval': (p) => { getSession(p.sessionId).approval = !!p.approval; return null; },

  'session.setName': async (p) => { await getSession(p.sessionId).setName(p.name); return null; },

  'session.setCompaction': (p) => {
    getSession(p.sessionId).compaction = { ...DEFAULT_COMPACTION, ...(p.compaction ?? {}) };
    return null;
  },

  'session.close': (p) => onChat(p.sessionId, async () => {
    const s = sessions.get(p.sessionId);
    if (!s) return null;
    sessions.delete(p.sessionId);
    // After a sync's import into it, not in the middle.
    await s.exclusive(() => s.close());
    return null;
  }),

  /**
   * One completion without a session — a chat title, a translation. Streamed
   * when `streamId` is given, as `complete.event` events under it.
   */
  'complete': async (p) => {
    const model = resolveModel(p.model);
    const context = { systemPrompt: p.systemPrompt, messages: p.messages ?? [], tools: p.tools };
    const options = { ...(p.options ?? {}) };
    if (p.streamId == null) return await models.completeSimple(model, context, options);
    const controller = new AbortController();
    completions.set(p.streamId, controller);
    try {
      const stream = models.streamSimple(model, context, { ...options, signal: controller.signal });
      for await (const e of stream) {
        const { partial: _partial, ...rest } = e;
        emit({ type: 'complete.event', streamId: p.streamId, event: rest });
      }
      return await stream.result();
    } finally {
      completions.delete(p.streamId);
    }
  },

  'complete.abort': (p) => { completions.get(p.streamId)?.abort(); return null; },
};

/** Streamed completions still running, so they can be aborted. */
const completions = new Map();

function errorText(e) {
  if (e instanceof Error) return e.message || e.name;
  try { return JSON.stringify(e); } catch { return String(e); }
}

globalThis.__fl = {
  async dispatch(method, payload) {
    try {
      const fn = methods[method];
      if (!fn) throw new Error(`Unknown method: ${method}`);
      const value = await fn(payload ? JSON.parse(payload) : {});
      return JSON.stringify({ ok: true, value: value ?? null });
    } catch (e) {
      return JSON.stringify({ ok: false, error: errorText(e) });
    }
  },
};
