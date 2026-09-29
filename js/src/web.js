// The Web platform surface pi and the provider SDKs reach for, none of which
// QuickJS has. Built over `globalThis.__host`, which the Rust runtime installs
// before this script runs:
//
//   __host.setTimer(ms, cb, repeat) -> id, __host.clearTimer(id)
//   __host.randomBytes(n) -> Uint8Array
//   __host.log(level, msg)
//   __host.call(name, payloadJson, bytes?) -> Promise<string>
//   __host.notify(name, payloadJson)
//   __host.read(streamId) -> Promise<Uint8Array | null>   (null: body ended)
import 'core-js/actual/url';
import 'core-js/actual/url-search-params';
import 'core-js/actual/structured-clone';
import 'core-js/actual/queue-microtask';
import 'core-js/actual/atob';
import 'core-js/actual/btoa';
import { EventTarget, Event } from 'event-target-shim';
import { ReadableStream, WritableStream, TransformStream } from 'web-streams-polyfill';

const g = globalThis;
const host = g.__host;

// UTF-8 only, which is all fetch and the SDKs ask for.
class TextEncoder {
  get encoding() { return 'utf-8'; }
  encode(str = '') {
    const out = []; 
    for (let i = 0; i < str.length; i++) {
      let c = str.charCodeAt(i);
      if (c >= 0xd800 && c < 0xdc00 && i + 1 < str.length) {
        const d = str.charCodeAt(i + 1);
        if (d >= 0xdc00 && d < 0xe000) { c = 0x10000 + ((c - 0xd800) << 10) + (d - 0xdc00); i++; }
        else c = 0xfffd;
      } else if (c >= 0xd800 && c < 0xe000) c = 0xfffd;
      if (c < 0x80) out.push(c);
      else if (c < 0x800) out.push(0xc0 | (c >> 6), 0x80 | (c & 63));
      else if (c < 0x10000) out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
      else out.push(0xf0 | (c >> 18), 0x80 | ((c >> 12) & 63), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
    }
    return new Uint8Array(out);
  }
  encodeInto(str, dest) { const b = this.encode(str); const n = Math.min(b.length, dest.length); dest.set(b.subarray(0, n)); return { read: str.length, written: n }; }
}

class TextDecoder {
  constructor(label = 'utf-8', opts = {}) {
    if (!/^utf-?8$/i.test(label)) throw new RangeError(`Unsupported encoding: ${label}`);
    this.fatal = !!opts.fatal; this.ignoreBOM = !!opts.ignoreBOM; this._pending = []; this._bomSeen = false;
  }
  get encoding() { return 'utf-8'; }
  decode(input, opts = {}) {
    let bytes = input == null ? new Uint8Array()
      : input instanceof Uint8Array ? input
      : ArrayBuffer.isView(input) ? new Uint8Array(input.buffer, input.byteOffset, input.byteLength)
      : new Uint8Array(input);
    if (this._pending.length) { const b = new Uint8Array(this._pending.length + bytes.length); b.set(this._pending); b.set(bytes, this._pending.length); bytes = b; this._pending = []; }
    let s = ''; let i = 0; const n = bytes.length;
    if (!this._bomSeen && !this.ignoreBOM && n >= 3 && bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf) i = 3;
    if (n) this._bomSeen = true;
    const chunk = [];
    const flushChunk = () => { if (chunk.length) { s += String.fromCharCode.apply(null, chunk); chunk.length = 0; } };
    while (i < n) {
      const b = bytes[i];
      const len = b < 0x80 ? 1 : b >= 0xf0 && b < 0xf8 ? 4 : b >= 0xe0 ? 3 : b >= 0xc0 ? 2 : 0;
      if (len === 0) { if (this.fatal) throw new TypeError('Invalid UTF-8'); chunk.push(0xfffd); i++; continue; }
      if (i + len > n) {
        if (opts.stream) { this._pending = Array.from(bytes.subarray(i)); break; }
        if (this.fatal) throw new TypeError('Truncated UTF-8'); chunk.push(0xfffd); break;
      }
      let c = len === 1 ? b : b & (0xff >> (len + 1)); let bad = false;
      for (let k = 1; k < len; k++) { const x = bytes[i + k]; if ((x & 0xc0) !== 0x80) { bad = true; break; } c = (c << 6) | (x & 63); }
      if (bad) { if (this.fatal) throw new TypeError('Invalid UTF-8'); chunk.push(0xfffd); i++; continue; }
      i += len;
      if (c >= 0x10000) { c -= 0x10000; chunk.push(0xd800 + (c >> 10), 0xdc00 + (c & 0x3ff)); } else chunk.push(c);
      if (chunk.length > 8192) flushChunk();
    }
    flushChunk();
    if (!opts.stream) { this._bomSeen = false; }
    return s;
  }
}
g.TextEncoder ??= TextEncoder;
g.TextDecoder ??= TextDecoder;

g.EventTarget ??= EventTarget;
g.Event ??= Event;
g.ReadableStream ??= ReadableStream;
g.WritableStream ??= WritableStream;
g.TransformStream ??= TransformStream;

class DOMException extends Error {
  constructor(message = '', name = 'Error') { super(message); this.name = name; }
}
g.DOMException ??= DOMException;

// Timers
g.setTimeout = (cb, ms = 0, ...args) => host.setTimer(ms, () => cb(...args), false);
g.setInterval = (cb, ms = 0, ...args) => host.setTimer(ms, () => cb(...args), true);
g.clearTimeout = g.clearInterval = (id) => { if (id != null) host.clearTimer(id); };

// AbortController
class AbortSignal extends EventTarget {
  constructor() { super(); this.aborted = false; this.reason = undefined; this.onabort = null; }
  throwIfAborted() { if (this.aborted) throw this.reason; }
  _abort(reason) {
    if (this.aborted) return;
    this.aborted = true;
    this.reason = reason ?? new DOMException('This operation was aborted', 'AbortError');
    const e = new Event('abort');
    this.onabort?.(e);
    this.dispatchEvent(e);
  }
  static abort(reason) { const s = new AbortSignal(); s._abort(reason); return s; }
  static timeout(ms) {
    const s = new AbortSignal();
    setTimeout(() => s._abort(new DOMException('The operation timed out', 'TimeoutError')), ms);
    return s;
  }
  static any(signals) {
    const s = new AbortSignal();
    for (const x of signals) {
      if (x.aborted) { s._abort(x.reason); return s; }
      x.addEventListener('abort', () => s._abort(x.reason), { once: true });
    }
    return s;
  }
}
class AbortController {
  constructor() { this.signal = new AbortSignal(); }
  abort(reason) { this.signal._abort(reason); }
}
g.AbortSignal = AbortSignal;
g.AbortController = AbortController;

// crypto
g.crypto ??= {};
g.crypto.getRandomValues ??= (arr) => {
  const bytes = host.randomBytes(arr.byteLength);
  new Uint8Array(arr.buffer, arr.byteOffset, arr.byteLength).set(bytes);
  return arr;
};
g.crypto.randomUUID ??= () => {
  const b = g.crypto.getRandomValues(new Uint8Array(16));
  b[6] = (b[6] & 0x0f) | 0x40; b[8] = (b[8] & 0x3f) | 0x80;
  const h = [...b].map((x) => x.toString(16).padStart(2, '0')).join('');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
};

// console
const fmt = (args) => args.map((a) => (typeof a === 'string' ? a : (() => { try { return JSON.stringify(a); } catch { return String(a); } })())).join(' ');
g.console = {
  log: (...a) => host.log('info', fmt(a)), info: (...a) => host.log('info', fmt(a)),
  debug: (...a) => host.log('debug', fmt(a)), warn: (...a) => host.log('warn', fmt(a)),
  error: (...a) => host.log('error', fmt(a)),
};

// Blob / File / FormData: the SDKs test for them; nothing here uploads files.
class Blob {
  constructor(parts = [], opts = {}) {
    const enc = new TextEncoder(); const bufs = parts.map((p) => typeof p === 'string' ? enc.encode(p) : p instanceof Blob ? p._b : ArrayBuffer.isView(p) ? new Uint8Array(p.buffer, p.byteOffset, p.byteLength) : new Uint8Array(p));
    const n = bufs.reduce((a, b) => a + b.byteLength, 0); this._b = new Uint8Array(n); let o = 0; for (const b of bufs) { this._b.set(b, o); o += b.byteLength; }
    this.type = opts.type ?? '';
  }
  get size() { return this._b.byteLength; }
  arrayBuffer() { return Promise.resolve(this._b.slice().buffer); }
  bytes() { return Promise.resolve(this._b.slice()); }
  text() { return Promise.resolve(new TextDecoder().decode(this._b)); }
  slice(a, b, type) { return new Blob([this._b.slice(a, b)], { type }); }
  stream() { const b = this._b; return new ReadableStream({ start(c) { c.enqueue(b); c.close(); } }); }
}
class File extends Blob {
  constructor(parts, name, opts = {}) { super(parts, opts); this.name = name; this.lastModified = opts.lastModified ?? Date.now(); }
}
class FormData {
  constructor() { this._e = []; }
  append(k, v) { this._e.push([k, v]); }
  set(k, v) { this.delete(k); this.append(k, v); }
  get(k) { return this._e.find((e) => e[0] === k)?.[1] ?? null; }
  getAll(k) { return this._e.filter((e) => e[0] === k).map((e) => e[1]); }
  has(k) { return this._e.some((e) => e[0] === k); }
  delete(k) { this._e = this._e.filter((e) => e[0] !== k); }
  *entries() { yield* this._e; }
  [Symbol.iterator]() { return this.entries(); }
}
g.Blob ??= Blob; g.File ??= File; g.FormData ??= FormData;

g.process ??= { env: {}, versions: {}, platform: 'quickjs' };
g.navigator ??= { userAgent: 'fl_pi_llm', product: 'fl_pi_llm' };

// fetch
class Headers {
  constructor(init) {
    this._m = new Map();
    if (init instanceof Headers) init.forEach((v, k) => this.append(k, v));
    else if (Array.isArray(init)) for (const [k, v] of init) this.append(k, v);
    else if (init) for (const k of Object.keys(init)) this.append(k, init[k]);
  }
  append(k, v) { k = k.toLowerCase(); const o = this._m.get(k); this._m.set(k, o == null ? String(v) : `${o}, ${v}`); }
  set(k, v) { this._m.set(k.toLowerCase(), String(v)); }
  get(k) { return this._m.get(k.toLowerCase()) ?? null; }
  has(k) { return this._m.has(k.toLowerCase()); }
  delete(k) { this._m.delete(k.toLowerCase()); }
  forEach(cb, t) { for (const [k, v] of this._m) cb.call(t, v, k, this); }
  *entries() { yield* this._m.entries(); }
  *keys() { yield* this._m.keys(); }
  *values() { yield* this._m.values(); }
  [Symbol.iterator]() { return this.entries(); }
}
g.Headers = Headers;

const utf8 = new TextEncoder();
async function bodyBytes(body) {
  if (body == null) return null;
  if (typeof body === 'string') return utf8.encode(body);
  if (body instanceof Uint8Array) return body;
  if (body instanceof ArrayBuffer) return new Uint8Array(body);
  if (ArrayBuffer.isView(body)) return new Uint8Array(body.buffer, body.byteOffset, body.byteLength);
  if (body instanceof URLSearchParams) return utf8.encode(body.toString());
  if (body instanceof ReadableStream) {
    const parts = []; let n = 0;
    for await (const c of body) { parts.push(c); n += c.byteLength; }
    const out = new Uint8Array(n); let o = 0;
    for (const p of parts) { out.set(p, o); o += p.byteLength; }
    return out;
  }
  throw new TypeError('Unsupported request body');
}

class Body {
  _consume() {
    if (this.bodyUsed) return Promise.reject(new TypeError('Body already used'));
    this.bodyUsed = true;
    return bodyBytes(this.body).then((b) => b ?? new Uint8Array());
  }
  arrayBuffer() { return this._consume().then((b) => b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength)); }
  bytes() { return this._consume(); }
  text() { return this._consume().then((b) => new TextDecoder().decode(b)); }
  json() { return this.text().then(JSON.parse); }
}

class Request extends Body {
  constructor(input, init = {}) {
    super();
    const src = input instanceof Request ? input : null;
    this.url = src ? src.url : String(input);
    this.method = (init.method ?? src?.method ?? 'GET').toUpperCase();
    this.headers = new Headers(init.headers ?? src?.headers);
    this.body = init.body ?? src?.body ?? null;
    this.signal = init.signal ?? src?.signal ?? null;
    this.bodyUsed = false;
  }
  clone() { return new Request(this); }
}
g.Request = Request;

class Response extends Body {
  constructor(body = null, init = {}) {
    super();
    this.body = body == null ? null : body instanceof ReadableStream ? body
      : new ReadableStream({ start(c) { bodyBytes(body).then((b) => { c.enqueue(b); c.close(); }); } });
    this.status = init.status ?? 200;
    this.statusText = init.statusText ?? '';
    this.headers = new Headers(init.headers);
    this.ok = this.status >= 200 && this.status < 300;
    this.url = init.url ?? '';
    this.redirected = false;
    this.type = 'basic';
    this.bodyUsed = false;
  }
  clone() {
    const [a, b] = this.body ? this.body.tee() : [null, null];
    this.body = a;
    return new Response(b, this);
  }
  static json(data, init = {}) {
    const h = new Headers(init.headers); if (!h.has('content-type')) h.set('content-type', 'application/json');
    return new Response(JSON.stringify(data), { ...init, headers: h });
  }
  static error() { return new Response(null, { status: 0 }); }
}
g.Response = Response;

g.fetch = async (input, init = {}) => {
  const req = new Request(input, init);
  req.signal?.throwIfAborted();
  const headers = {}; req.headers.forEach((v, k) => { headers[k] = v; });
  const body = await bodyBytes(req.body);
  const res = JSON.parse(await host.call('fetch', JSON.stringify({ url: req.url, method: req.method, headers }), body ?? undefined));
  const id = res.streamId;
  let done = false;
  const cancel = () => { if (!done) { done = true; host.notify('fetch.cancel', JSON.stringify({ streamId: id })); } };
  const onAbort = () => cancel();
  req.signal?.addEventListener('abort', onAbort, { once: true });
  const stream = new ReadableStream({
    async pull(c) {
      if (req.signal?.aborted) { c.error(req.signal.reason); return; }
      const chunk = await host.read(id);
      if (chunk == null) { done = true; c.close(); req.signal?.removeEventListener('abort', onAbort); }
      else c.enqueue(chunk);
    },
    cancel,
  }, { highWaterMark: 0 });
  return new Response(stream, { status: res.status, statusText: res.statusText, headers: res.headers, url: req.url });
};
