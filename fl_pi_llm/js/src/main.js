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
// harness event names); `hostEntry` and `hostEvents` translate.
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
  section,
  ToolTask,
  watchEvents,
} from '@earendil-works/pi-durable';
import { SqliteStorage } from '@earendil-works/pi-durable/storage/sqlite';
import { listChats, openChat, removeChat } from './db.js';
import { legacyFiles, migrate, removeLegacy } from './legacy.js';
import { ChatTree } from './tree.js';
import { CUSTOM_APIS, models, modelInfo, probeModels, providerInfo, resolveModel, setCustomProviders } from './providers.js';

const host = globalThis.__host;
const BG = BACKGROUND_CONTEXT;

const hostCall = async (name, payload) => JSON.parse(await host.call(name, JSON.stringify(payload)));
const emit = (payload) => host.emit(JSON.stringify(payload));

const PI_VERSION = '1.1.0';

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
});

/** Every chat in storage, by id, with when it was made and last written. */
const storedChats = () => new Map(listChats().map((c) => [c.id, c]));

/**
 * Moves chat [id] out of a session from before pi-durable, if one is left
 * (TODO: remove with legacy.js). The chat's file is made again from it: a
 * move cut short leaves the old session, and is started over.
 */
const migrating = new Map();
function migrateLegacy(id, file) {
  let m = migrating.get(id);
  if (!m) {
    m = (async () => {
      removeChat(id);
      const harness = await Harness.open(await SqliteStorage.open(openChat(id)), {
        models: harnessModels,
        registry: createRegistry(),
      }, BG);
      try {
        const moved = await migrate(harness, file, BG);
        await setPlace(harness, moved.current, moved.tip, moved.name);
      } finally {
        await harness.close(BG);
      }
      await removeLegacy(file);
    })().finally(() => migrating.delete(id));
    migrating.set(id, m);
  }
  return m;
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

const MESSAGE_ROLES = new Set(['user', 'assistant', 'toolResult']);

const textOf = (m) => (typeof m?.content === 'string'
  ? m.content
  : (m?.content ?? []).filter((c) => c.type === 'text').map((c) => c.text).join(''));

/** pi-durable hands the model a summary wrapped in a preamble; the host shows the summary. */
const unwrapSummary = (text) => /<summary>\n?([\s\S]*?)\n?<\/summary>/.exec(text)?.[1] ?? text;

/**
 * One pi-durable entry as the host knows entries, or null for what it never
 * shows (system prompt and tool changes, resets).
 */
function hostEntry(e, parentId) {
  const m = e.model?.[0];
  const id = String(e.id);
  const base = { id, parentId, seq: e.id, timestamp: m?.timestamp ?? e.data?.timestamp ?? 0 };
  switch (e.kind) {
    case 'pi.compaction':
    case 'fl.compaction':
      return {
        ...base,
        type: 'compaction',
        summary: e.data?.summary ?? unwrapSummary(textOf(m)),
        // The first entry the summary kept: `head`, itself when it kept none.
        firstKeptEntryId: typeof e.head === 'number' ? String(e.head) : id,
        ...(e.data?.tokensBefore != null ? { tokensBefore: e.data.tokensBefore } : {}),
      };
    case 'fl.custom':
      return { ...base, type: 'custom', customType: e.data?.customType ?? '', data: e.data?.data ?? null };
    case 'pi.system':
    case 'pi.reset':
      return null;
    default:
      return m && MESSAGE_ROLES.has(m.role) ? { ...base, type: 'message', message: m } : null;
  }
}

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
          content: res.content ?? [],
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

    // TODO: remove with legacy.js.
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

  /** Forwards the current conversation's events, in the host's shape. */
  async #watch() {
    await this.stream?.stop?.();
    const last = (await this.#branchIds()).at(-1);
    this.lastId = last == null ? null : String(last);
    this.stream = await watchEvents(this.harness, this.current.id, BG);
    this.stream.start(async (events) => {
      for (const e of events) {
        for (const out of this.#hostEvents(e)) emit({ type: 'session.event', sessionId: this.id, event: out });
      }
    });
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

  #hostEvents(e) {
    switch (e.type) {
      case 'message_start': {
        const m = e.message;
        if (m?.role === 'system') return [];
        if (m?.role !== 'assistant' || !Array.isArray(m.content)) return [{ type: 'message_start', message: m }];
        // A partial is committed at most every 100 ms, so an answer may start
        // with text in it; the host streams from an empty message.
        this.streamed = new Map();
        return [{ type: 'message_start', message: { ...m, content: [] } }, ...this.#catchUp(m)];
      }
      case 'message_update':
        return (e.changes ?? [])
          .filter((c) => c.type === 'text_delta' || c.type === 'thinking_delta' || c.type === 'toolcall_delta')
          .map((c) => {
            if (c.type !== 'toolcall_delta') this.streamed.set(c.contentIndex, (this.streamed.get(c.contentIndex) ?? 0) + c.delta.length);
            return { type: 'message_update', event: { type: c.type, contentIndex: c.contentIndex, delta: c.delta } };
          });
      case 'message_end': {
        const m = e.entry?.model?.[0];
        if (!m || m.role === 'system') return [];
        // What came after the last committed partial reaches the host here.
        const rest = m.role === 'assistant' ? this.#catchUp(m) : [];
        this.streamed = new Map();
        return [...rest, { type: 'message_end', message: m }, ...this.#added(e.entry)];
      }
      case 'entry_appended':
        return this.#added(e.entry);
      case 'tool_execution_start':
        return [{ type: 'tool_start', toolCallId: e.toolCallId, toolName: e.toolName, args: e.args }];
      case 'tool_execution_update':
        return [{ type: 'tool_update', toolCallId: e.toolCallId, toolName: e.toolName, output: e.output, details: e.details }];
      case 'tool_execution_end':
        return [{ type: 'tool_end', toolCallId: e.toolCallId, toolName: e.toolName, isError: !!e.entry?.model?.[0]?.isError }];
      case 'run_start':
      case 'turn_start':
      case 'turn_end':
        return [{ type: e.type }];
      case 'submission': {
        // A run ends for the host when its input is answered, or is not.
        const r = e.record;
        if (r?.type !== 'input' || (r.status !== 'done' && r.status !== 'unanswered')) return [];
        return [{ type: 'run_end', ...runResult(r) }];
      }
      case 'compaction_start':
        return [{ type: 'compaction_start', reason: e.reason }];
      case 'compaction_end':
        return [{ type: 'compaction_end', reason: e.reason }];
      case 'auto_retry_start':
        return [{ type: 'retry_start', attempt: e.attempt, at: e.at, message: e.errorMessage }];
      case 'auto_retry_end':
        return [{ type: 'retry_end', attempt: e.attempt }];
      case 'usage_changed':
        return [{ type: 'usage', usage: e.usage }];
      case 'task_failed':
        return [{ type: 'fault', message: e.message }];
      default:
        return [];
    }
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
      const at = this.shape.entries.get(id);
      if (!at) throw new Error(`No entry ${targetId}`);
      const leaf = this.shape.conversationEndingAt(id);
      this.current = await this.harness.conversation(leaf ?? at.conversationId, BG);
      this.tip = leaf != null ? null : id;
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

  /** Writes an entry the model may see, without running it. */
  async write(entry) {
    const conv = await this.writable();
    const settled = await (await conv.submit({ type: 'write', entry }, BG)).wait(BG);
    if (settled.status !== 'done') throw new Error(`Not written: ${settled.reason}`);
    return String(settled.entry);
  }

  async prompt(text, images) {
    const conv = await this.writable();
    const content = [{ type: 'text', text }, ...(images ?? [])];
    return runResult(await (await conv.submit({ type: 'input', content }, BG)).wait(BG));
  }

  /** Picks up what a previous launch left running, and waits for it. */
  async resume() {
    this.harness.resume();
    await this.current.waitForIdle(BG);
    this.interrupted = false;
    const lastId = (await this.#branchIds()).at(-1);
    const last = lastId == null ? undefined : (await this.storage.entry(lastId, BG)).entry.model?.[0];
    if (last?.role === 'assistant' && last.stopReason === 'aborted') return { status: 'aborted' };
    if (last?.role === 'assistant' && last.stopReason === 'error') return { status: 'failed', error: { message: last.errorMessage ?? 'error' } };
    return { status: 'completed', tipId: this.lastId };
  }

  async compact(instructions) {
    const conv = await this.writable();
    const taskId = await conv.compact(instructions || undefined, BG);
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
  'providers.list': () => models.getProviders().map(providerInfo),

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
    for (const p of models.getProviders()) {
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
    for (const [id, file] of await legacyFiles()) {
      if (sessions.has(id)) continue;
      try {
        await migrateLegacy(id, file);
      } catch (e) {
        failed[id] = errorText(e);
      }
    }
    return { failed };
  },

  /** Deletes a stored session. It must not be open. */
  'sessions.delete': async (p) => {
    if (sessions.has(p.sessionId)) throw new Error(`Session is open: ${p.sessionId}`);
    // TODO: remove with legacy.js.
    await migrating.get(p.sessionId)?.catch(() => {});
    removeChat(p.sessionId);
    const legacy = (await legacyFiles()).get(p.sessionId);
    if (legacy) await removeLegacy(legacy);
    return null;
  },

  /**
   * Opens a session, creating it when it does not exist. Returns the entries
   * on its current branch and whether a previous launch left work running.
   */
  'session.open': async (p) => {
    if (sessions.has(p.sessionId)) throw new Error(`Session is already open: ${p.sessionId}`);
    const s = await Session.open(p);
    sessions.set(p.sessionId, s);
    return {
      interrupted: s.interrupted ? [{ operationId: 'run', kind: 'run' }] : [],
      name: s.name,
    };
  },

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

  'session.close': async (p) => {
    const s = sessions.get(p.sessionId);
    if (!s) return null;
    sessions.delete(p.sessionId);
    await s.close();
    return null;
  },

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
