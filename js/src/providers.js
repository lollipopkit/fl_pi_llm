// Providers and models, as pi-ai has them.
//
// The built-in catalog is pi-ai's own. Custom providers are endpoints the user
// adds: their models are listed from `{baseUrl}/models` and enriched with
// OpenRouter-shaped metadata, the way lollipopkit/pi-models-metadata does it.
//
// Credentials never live here. pi-ai asks its `CredentialStore`, and this one
// asks the host, which keeps them in the platform's keychain:
//
//   auth.read   {providerId}          -> Credential | null
//   auth.list   {}                    -> [{providerId, type}]
//   auth.write  {providerId, credential}
//   auth.delete {providerId}
//
// Model lists fetched from the network are cached through the host's store
// (see fs.js), under /models/.
import { createProvider } from '@earendil-works/pi-ai';
import { anthropicMessagesApi } from '@earendil-works/pi-ai/api/anthropic-messages.lazy';
import { googleGenerativeAIApi } from '@earendil-works/pi-ai/api/google-generative-ai.lazy';
import { openAICompletionsApi } from '@earendil-works/pi-ai/api/openai-completions.lazy';
import { openAIResponsesApi } from '@earendil-works/pi-ai/api/openai-responses.lazy';
import { builtinModels } from '@earendil-works/pi-ai/providers/all';

import { hostFileSystem } from './fs.js';

const host = globalThis.__host;
const call = async (name, payload) => JSON.parse(await host.call(name, JSON.stringify(payload)));

/** The APIs a custom provider may speak. */
export const CUSTOM_APIS = {
  'openai-completions': openAICompletionsApi,
  'openai-responses': openAIResponsesApi,
  'anthropic-messages': anthropicMessagesApi,
  'google-generative-ai': googleGenerativeAIApi,
};

/**
 * Built-in providers that cannot work here: their auth reads files or runs
 * a login that only exists under Node.
 */
const UNAVAILABLE = new Set(['amazon-bedrock', 'google-vertex', 'openai-codex', 'github-copilot']);

const credentials = {
  read: async (providerId) => (await call('auth.read', { providerId })) ?? undefined,
  list: async () => call('auth.list', {}),
  modify: async (providerId, fn) => {
    const next = await fn((await call('auth.read', { providerId })) ?? undefined);
    if (next === undefined) await call('auth.delete', { providerId });
    else await call('auth.write', { providerId, credential: next });
    return next;
  },
  delete: async (providerId) => { await call('auth.delete', { providerId }); },
};

/** Custom provider specs by id, so they can be told from built-in ones. */
const customSpecs = new Map();
export const customIds = { has: (id) => customSpecs.has(id) };

const modelsStore = {
  path: (id) => `/models/${encodeURIComponent(id)}.json`,
  async read(id) {
    const r = await hostFileSystem.readTextFile(this.path(id));
    if (!r.ok) return undefined;
    let entry;
    try { entry = JSON.parse(r.value); } catch { return undefined; }
    // A custom provider's list belongs to the endpoint it was fetched from:
    // its models carry that baseUrl and headers.
    const spec = customSpecs.get(id);
    if (spec && entry?.endpoint !== endpointKey(spec)) return undefined;
    return entry;
  },
  async write(id, entry) {
    const spec = customSpecs.get(id);
    await hostFileSystem.writeFile(this.path(id), JSON.stringify(spec ? { ...entry, endpoint: endpointKey(spec) } : entry));
  },
  async delete(id) {
    await hostFileSystem.remove(this.path(id), { force: true });
  },
};

/** Nothing from the environment: a credential carries its own `env`. */
const authContext = { env: async () => undefined, fileExists: async () => false };

export const models = builtinModels({ credentials, modelsStore, authContext });
for (const p of [...models.getProviders()]) {
  if (UNAVAILABLE.has(p.id)) models.deleteProvider(p.id);
}

// ---------------------------------------------------------------------------
// Custom providers

/** The APIs whose endpoints list their models at `{baseUrl}/models`. */
const LISTING_APIS = new Set(['openai-completions', 'openai-responses']);

/** What a custom provider's cached model list depends on. */
const endpointKey = (spec) => JSON.stringify([spec.api, spec.baseUrl, spec.headers ?? null]);

/**
 * Listed models that cannot chat. Metadata decides when there is some; the
 * ids are the fallback.
 */
const NOT_CHAT = /(^|[-_/.])(embed(ding)?s?|tts|whisper|transcribe|dall-e|moderation|rerank(er)?)([-_/.:]|\d|$)/i;
const canChat = (listed, meta) => {
  const out = meta?.architecture?.output_modalities;
  if (Array.isArray(out)) return out.includes('text');
  return !NOT_CHAT.test(listed.id);
};

const METADATA_URL = 'https://ormc.lollipopkit.com/models-data.json';
const PRICE_SCALE = 1_000_000;


let metadataIndex;
async function metadata(signal) {
  if (metadataIndex) return metadataIndex;
  const res = await fetch(METADATA_URL, { signal });
  if (!res.ok) throw new Error(`metadata: HTTP ${res.status}`);
  const body = await res.json();
  const list = Array.isArray(body?.data) ? body.data : Array.isArray(body) ? body : [];
  const byId = new Map();
  const byNorm = new Map();
  const buckets = new Map();
  for (const m of list) {
    if (typeof m?.id !== 'string') continue;
    byId.set(m.id, m);
    byNorm.set(norm(m.id), m);
    const base = norm(basename(m.id));
    buckets.set(base, [...(buckets.get(base) ?? []), m]);
  }
  const byBase = new Map();
  for (const [k, v] of buckets) if (v.length === 1) byBase.set(k, v[0]);
  metadataIndex = { byId, byNorm, byBase };
  return metadataIndex;
}

const norm = (id) => id.trim().toLowerCase();
const basename = (id) => id.split('/').at(-1) || id;
const price = (v) => {
  const n = Number.parseFloat(v ?? '');
  return Number.isFinite(n) ? n * PRICE_SCALE : 0;
};

function findMetadata(id, index) {
  return index.byId.get(id) ?? index.byNorm.get(norm(id)) ?? (id.includes('/') ? undefined : index.byBase.get(norm(id)));
}

function toModel(spec, listed, meta) {
  const src = meta ?? listed;
  const params = src.supported_parameters;
  return {
    id: listed.id,
    name: meta?.name ?? listed.name ?? basename(listed.id),
    api: spec.api,
    provider: spec.id,
    baseUrl: spec.baseUrl,
    reasoning: params?.some?.((p) => p === 'reasoning' || p === 'reasoning_effort') ?? false,
    // Unknown capabilities are the endpoint's to refuse: without metadata, an
    // image is sent rather than silently dropped.
    input: src.architecture?.input_modalities
      ? (src.architecture.input_modalities.includes('image') ? ['text', 'image'] : ['text'])
      : ['text', 'image'],
    cost: {
      input: price(src.pricing?.prompt),
      output: price(src.pricing?.completion),
      cacheRead: price(src.pricing?.input_cache_read),
      cacheWrite: price(src.pricing?.input_cache_write),
    },
    contextWindow: src.top_provider?.context_length ?? src.context_length ?? 128000,
    maxTokens: src.top_provider?.max_completion_tokens ?? 16384,
    ...(spec.headers ? { headers: spec.headers } : {}),
  };
}

/**
 * Registers (or replaces) the user's custom providers.
 *
 * Spec: `{id, name, api, baseUrl, headers?, models?: [{id, name?, ...}]}`.
 * An OpenAI-compatible endpoint also lists its models at `{baseUrl}/models`
 * on refresh; `models` are kept beside that list, for ids it lacks. Other
 * APIs have only `models`.
 */
export function setCustomProviders(specs) {
  for (const id of customSpecs.keys()) {
    if (specs.some((s) => s.id === id)) continue;
    models.deleteProvider(id);
    modelsStore.delete(id).catch(() => {});
  }
  customSpecs.clear();
  for (const spec of specs) {
    const api = CUSTOM_APIS[spec.api];
    if (!api) throw new Error(`Unsupported api: ${spec.api}`);
    if (!spec.id || !spec.baseUrl) throw new Error('A custom provider needs an id and a baseUrl');
    const baseUrl = spec.baseUrl.replace(/\/+$/, '');
    const s = { ...spec, baseUrl };
    const fixed = (spec.models ?? []).map((m) => toModel(s, { ...m, id: m.id }, undefined));
    models.setProvider(createProvider({
      id: spec.id,
      name: spec.name ?? spec.id,
      baseUrl,
      ...(spec.headers ? { headers: spec.headers } : {}),
      auth: {
        apiKey: {
          name: spec.name ?? spec.id,
          resolve: async ({ credential }) => ({
            auth: credential?.key ? { apiKey: credential.key } : {},
            ...(credential?.env ? { env: credential.env } : {}),
          }),
        },
      },
      models: fixed,
      ...(LISTING_APIS.has(spec.api) ? { fetchModels: ({ credential, signal }) => listModels(s, credential, signal) } : {}),
      api: api(),
    }));
    customSpecs.set(spec.id, s);
  }
}

/** `GET {baseUrl}/models` of an OpenAI-compatible endpoint, as pi-ai models. */
async function listModels(spec, credential, signal) {
  const headers = { accept: 'application/json', ...(spec.headers ?? {}) };
  if (credential?.key) headers.authorization = `Bearer ${credential.key}`;
  const res = await fetch(`${spec.baseUrl}/models`, { headers, signal });
  if (!res.ok) throw new Error(`${spec.baseUrl}/models: HTTP ${res.status}`);
  const body = await res.json();
  // OpenAI's `{data}`; some servers answer `{models}` or a bare array.
  const raw = Array.isArray(body?.data) ? body.data : Array.isArray(body?.models) ? body.models : Array.isArray(body) ? body : [];
  const listed = raw.filter((m) => typeof m?.id === 'string');
  let index;
  try { index = await metadata(signal); } catch { index = undefined; }
  return listed
    .map((m) => [m, index && findMetadata(m.id, index)])
    .filter(([m, meta]) => canChat(m, meta))
    .map(([m, meta]) => toModel(spec, m, meta));
}

// ---------------------------------------------------------------------------
// What the host sees

/** A model as the host sees it: no functions, nothing provider-internal. */
export function modelInfo(m) {
  return {
    provider: m.provider,
    id: m.id,
    name: m.name,
    api: m.api,
    reasoning: !!m.reasoning,
    input: m.input,
    contextWindow: m.contextWindow,
    maxTokens: m.maxTokens,
    cost: m.cost,
  };
}

export function providerInfo(p) {
  return {
    id: p.id,
    name: p.name ?? p.id,
    custom: customIds.has(p.id),
    baseUrl: p.baseUrl ?? null,
    auth: { apiKey: !!p.auth?.apiKey, oauth: !!p.auth?.oauth },
    models: p.getModels().map(modelInfo),
  };
}

/** The model a `{provider, id}` reference names. */
export function resolveModel(ref) {
  if (!ref?.provider || !ref?.id) throw new Error('A model is named by {provider, id}');
  const m = models.getModel(ref.provider, ref.id);
  if (m) return m;
  // A custom provider's model that its list does not have (yet): the user
  // typed an id. Take the provider's endpoint and API.
  const spec = customSpecs.get(ref.provider);
  if (spec) {
    return {
      id: ref.id, name: ref.id, api: spec.api, provider: spec.id, baseUrl: spec.baseUrl,
      ...(spec.headers ? { headers: spec.headers } : {}),
      reasoning: false, input: ['text', 'image'], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
      contextWindow: 128000, maxTokens: 16384,
    };
  }
  throw new Error(`Unknown model: ${ref.provider}/${ref.id}`);
}
