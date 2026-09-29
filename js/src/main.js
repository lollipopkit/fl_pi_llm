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
// Conversations are pi sessions: an append-only tree of entries driven by
// pi's AgentHarness, stored through `fs.js` wherever the host keeps them.
//
// Imported first so every global pi reaches for exists before its modules run.
import './web.js';

import {
  BACKGROUND_CONTEXT,
  AgentHarness,
  DEFAULT_COMPACTION_SETTINGS,
  JsonlSessionRepo,
} from '@earendil-works/pi-agent-core';
import { hostFileSystem } from './fs.js';
import { CUSTOM_APIS, models, modelInfo, probeModels, providerInfo, resolveModel, setCustomProviders } from './providers.js';

const host = globalThis.__host;
const BG = BACKGROUND_CONTEXT;

const hostCall = async (name, payload) => JSON.parse(await host.call(name, JSON.stringify(payload)));
const emit = (payload) => host.emit(JSON.stringify(payload));

// ---------------------------------------------------------------------------
// Sessions

const CWD = '/';
const LANE = 'main';
const repo = new JsonlSessionRepo({ fileSystem: hostFileSystem, sessionsRoot: '/sessions' });

/** Metadata of every stored session, by id. Read once, then kept current. */
let catalog;
async function sessionCatalog() {
  if (!catalog) {
    catalog = new Map();
    for (const m of await repo.list({ cwd: CWD }, BG)) catalog.set(m.id, m);
  }
  return catalog;
}

/** @type {Map<string, Session>} */
const sessions = new Map();

function getSession(id) {
  const s = sessions.get(id);
  if (!s) throw new Error(`Session is not open: ${id}`);
  return s;
}

/** A tool defined by the host, executed there. */
function hostTool(sessionId, def) {
  return {
    name: def.name,
    label: def.label ?? def.name,
    description: def.description ?? '',
    parameters: def.parameters ?? { type: 'object', properties: {} },
    ...(def.executionMode ? { executionMode: def.executionMode } : {}),
    execute: async (toolCallId, args, _onUpdate, _toolContext, _invocation, context) => {
      const signal = context?.abortSignal;
      const onAbort = () => host.notify('tool.cancel', JSON.stringify({ sessionId, toolCallId }));
      signal?.addEventListener('abort', onAbort, { once: true });
      try {
        const res = await hostCall('tool', { sessionId, toolCallId, name: def.name, args });
        if (res.error != null) throw new Error(String(res.error));
        return { content: res.content ?? [], details: res.details ?? null, ...(res.terminate ? { terminate: true } : {}) };
      } finally {
        signal?.removeEventListener('abort', onAbort);
      }
    },
  };
}

/** The harness events forwarded to the host. */
const EVENTS = [
  'run_start', 'run_end', 'run_suspend', 'run_resume', 'operation_abort', 'fault',
  'turn_start', 'turn_end', 'message_start', 'message_update', 'message_end',
  'tool_start', 'tool_update', 'tool_end', 'entry_added',
  'retry_scheduled', 'retry_start', 'retry_end',
  'compaction_start', 'compaction_end', 'navigation_start', 'navigation_end',
  'usage', 'handler_error',
];

/**
 * Strips what the host does not need: `message_update` carries the whole
 * partial message on every token, and the delta is all that changed.
 */
function slimEvent(e) {
  if (e.type === 'message_update') {
    const { partial: _partial, ...event } = e.event ?? {};
    return { type: e.type, runId: e.runId, event };
  }
  return e;
}

/** Unwraps pi's `Result`, throwing its error. */
function unwrap(result) {
  if (result.ok) return result.value;
  const e = result.error;
  throw new Error(e?.message ?? JSON.stringify(e));
}

class Session {
  constructor(id) {
    this.id = id;
    this.approval = false;
    this.unsubscribe = [];
  }

  static async open(p) {
    const s = new Session(p.sessionId);
    await s.#init(p);
    return s;
  }

  async #init(p) {
    const model = resolveModel(p.model);
    const cat = await sessionCatalog();
    const existing = cat.get(this.id);
    if (existing) {
      this.session = await repo.open(existing, BG);
    } else {
      this.session = await repo.create({ id: this.id, cwd: CWD }, BG);
      cat.set(this.id, this.session.metadata);
    }
    const tools = (p.tools ?? []).map((t) => hostTool(this.id, t));
    this.systemPrompt = p.systemPrompt ?? '';
    const { harness, open } = await AgentHarness.create({
      session: this.session,
      models,
      model,
      thinkingLevel: p.thinkingLevel ?? 'off',
      tools,
      // A function, so it can be changed without reopening the session.
      systemPrompt: () => this.systemPrompt,
      compaction: { ...DEFAULT_COMPACTION_SETTINGS, ...(p.compaction ?? {}) },
    }, BG);
    this.harness = harness;
    this.interrupted = open;
    this.approval = !!p.approval;
    this.lane = await harness.lane(LANE, BG);

    // A reopened session remembers its model and tools; what the host asks
    // for now is what counts.
    await this.lane.setModel({ provider: model.provider, modelId: model.id }, BG);
    await this.lane.setActiveTools(tools.map((t) => t.name), BG);
    if (p.thinkingLevel) await this.lane.setThinkingLevel(p.thinkingLevel, BG);

    this.unsubscribe.push(harness.hooks.on('before_tool', async (e) => {
      if (!this.approval) return undefined;
      const res = await hostCall('approve', {
        sessionId: this.id, toolCallId: e.toolCallId, name: e.toolName, args: e.args,
      });
      return res.block ? { block: { reason: res.reason ?? 'Denied by the user' } } : undefined;
    }));
    for (const type of EVENTS) {
      this.unsubscribe.push(harness.events.on(type, (event) => {
        emit({ type: 'session.event', sessionId: this.id, event: slimEvent(event) });
      }));
    }
  }

  /** Waits for a run to settle, however it was started. */
  async settle(result) {
    const v = unwrap(result);
    // A suspended run is waiting on the provider (a deferred request), not on
    // us; the harness resumes it by itself.
    if (v?.status === 'suspended') await this.lane.waitForIdle(BG);
    return v;
  }

  async entries() {
    return this.lane.findEntries(undefined, BG);
  }

  async close() {
    for (const u of this.unsubscribe) u();
    this.unsubscribe = [];
    try {
      await this.harness.close(BG);
    } finally {
      await this.session.close(BG);
    }
  }
}

/** Entries on the current branch, root first. */
async function branch(s) {
  return bySeq(await s.entries());
}

/** pi returns a branch tip first; the host wants it in the order it was written. */
const bySeq = (entries) => [...entries].sort((a, b) => a.seq - b.seq);

// ---------------------------------------------------------------------------
// Dispatch

const methods = {
  /** Version info, and a cheap way to see the runtime is up. */
  'runtime.info': () => ({ piAgentCore: '0.87.1', piAi: '0.87.1', apis: Object.keys(CUSTOM_APIS) }),

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

  /** Whether a provider's auth is set up, as pi-ai sees it. */
  'providers.checkAuth': async (p) => (await models.checkAuth(p.providerId)) ?? null,

  /** Every stored session, newest first. */
  'sessions.list': async () => {
    const cat = await sessionCatalog();
    return [...cat.values()]
      .sort((a, b) => b.createdAt - a.createdAt)
      .map((m) => ({ id: m.id, createdAt: m.createdAt, modifiedAt: m.modifiedAt, name: null }));
  },

  /** Deletes a stored session. It must not be open. */
  'sessions.delete': async (p) => {
    if (sessions.has(p.sessionId)) throw new Error(`Session is open: ${p.sessionId}`);
    const cat = await sessionCatalog();
    const m = cat.get(p.sessionId);
    if (!m) return null;
    await repo.delete(m, BG);
    cat.delete(p.sessionId);
    return null;
  },

  /**
   * Opens a session, creating it when it does not exist. Returns the entries
   * on its current branch and any operation a previous launch left running.
   */
  'session.open': async (p) => {
    if (sessions.has(p.sessionId)) throw new Error(`Session is already open: ${p.sessionId}`);
    const s = await Session.open(p);
    sessions.set(p.sessionId, s);
    return {
      entries: await branch(s),
      interrupted: s.interrupted.map((o) => ({ operationId: o.operationId, kind: o.kind })),
      name: (await s.harness.getName(BG)) ?? null,
    };
  },

  /** Resolves when the run ends. */
  'session.prompt': async (p) => {
    const s = getSession(p.sessionId);
    const r = await s.settle(await s.lane.prompt(p.text, p.images, BG));
    return { result: r };
  },

  /** Picks up a run a previous launch left open, or retries after an error. */
  'session.resume': async (p) => {
    const s = getSession(p.sessionId);
    return { result: await s.settle(await s.lane.resume(BG)) };
  },

  'session.abort': async (p) => {
    const s = getSession(p.sessionId);
    const r = await s.lane.abort(BG);
    return r.ok ? { operationId: r.value.operationId } : null;
  },

  /** The current branch, root first. */
  'session.entries': async (p) => ({ entries: await branch(getSession(p.sessionId)) }),

  /** Every entry in the session, all branches. */
  'session.tree': async (p) => ({ entries: bySeq(await getSession(p.sessionId).session.findEntries(undefined, BG)) }),

  /** One entry by id, whichever branch it is on — including compacted ones. */
  'session.entry': async (p) => ({ entry: (await getSession(p.sessionId).session.getEntry(p.entryId, BG)) ?? null }),

  /**
   * Moves the branch tip to `targetId` (null: before the first entry). The
   * next prompt then continues from there, leaving the old path in the tree.
   * This is how a message is edited or an answer regenerated.
   */
  'session.navigate': async (p) => {
    const s = getSession(p.sessionId);
    const r = unwrap(await s.lane.navigateTree(p.targetId ?? null, p.options, BG));
    return { navigation: r.navigation, entries: await branch(s) };
  },

  /**
   * Appends messages to the branch without running the model — an import, or
   * a result the host produced itself.
   */
  'session.append': async (p) => {
    const s = getSession(p.sessionId);
    const ids = [];
    for (const m of p.messages ?? []) ids.push(await s.lane.appendMessage(m, BG));
    return { ids };
  },

  /**
   * Appends an entry of the host's own kind — something to show, which the
   * model never sees.
   */
  'session.appendCustom': async (p) => {
    const s = getSession(p.sessionId);
    return { id: await s.lane.appendCustomEntry(p.customType, p.data ?? null, BG) };
  },

  /** Compacts now, whatever the thresholds say. */
  'session.compact': async (p) => {
    const s = getSession(p.sessionId);
    const r = unwrap(await s.lane.compact(p.customInstructions ? { customInstructions: p.customInstructions } : undefined, BG));
    return { compaction: r.compaction, entries: await branch(s) };
  },

  'session.setModel': async (p) => {
    const s = getSession(p.sessionId);
    const model = resolveModel(p.model);
    await s.lane.setModel({ provider: model.provider, modelId: model.id }, BG);
    return null;
  },

  'session.setSystemPrompt': (p) => { getSession(p.sessionId).systemPrompt = p.systemPrompt ?? ''; return null; },

  'session.setThinkingLevel': async (p) => {
    await getSession(p.sessionId).lane.setThinkingLevel(p.thinkingLevel, BG);
    return null;
  },

  'session.setTools': async (p) => {
    const s = getSession(p.sessionId);
    const tools = (p.tools ?? []).map((t) => hostTool(p.sessionId, t));
    await s.harness.setTools(tools, BG);
    await s.lane.setActiveTools(tools.map((t) => t.name), BG);
    return null;
  },

  'session.setApproval': (p) => { getSession(p.sessionId).approval = !!p.approval; return null; },

  'session.setName': async (p) => {
    await getSession(p.sessionId).harness.setName(p.name ?? undefined, BG);
    return null;
  },

  'session.setCompaction': async (p) => {
    await getSession(p.sessionId).harness.setCompactionSettings({ ...DEFAULT_COMPACTION_SETTINGS, ...p.compaction }, BG);
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
