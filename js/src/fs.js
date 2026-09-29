// pi's `FileSystem`, over the host's session store.
//
// pi keeps a session as an append-only JSONL file and reaches it only through
// an injected `FileSystem`. This is that filesystem, reduced to what the host
// has to implement — seven calls on whole files keyed by path:
//
//   fs.read   {path, maxLines?}  -> {text: string | null}
//   fs.write  {path, text}
//   fs.append {path, text}
//   fs.rename {from, to}
//   fs.remove {path, recursive}
//   fs.stat   {path}             -> {size, mtimeMs} | null
//   fs.list   {dir}              -> {files: [{path, size, mtimeMs}]}  (recursive)
//
// Directories are not stored: one exists while a file under it does. Paths are
// POSIX and absolute, rooted wherever the host decides.
import { err, FileError, ok } from '@earendil-works/pi-agent-core';

const host = globalThis.__host;
const call = async (name, payload) => JSON.parse(await host.call(name, JSON.stringify(payload)));

function normalize(path) {
  const out = [];
  for (const part of path.split('/')) {
    if (part === '' || part === '.') continue;
    if (part === '..') out.pop();
    else out.push(part);
  }
  return `/${out.join('/')}`;
}

const basename = (path) => path.slice(path.lastIndexOf('/') + 1);
const decoder = new TextDecoder();
const text = (content) => (typeof content === 'string' ? content : decoder.decode(content));

function splitLines(s) {
  if (s === '') return [];
  const lines = s.split('\n');
  const terminated = s.endsWith('\n');
  if (terminated) lines.pop();
  return lines.map((line, i) => ({ text: line, terminated: terminated || i < lines.length - 1 }));
}

/** Runs `fn`, turning a host failure into pi's `Result`. */
async function attempt(path, fn) {
  try {
    return ok(await fn());
  } catch (e) {
    if (e instanceof FileError) return err(e);
    return err(new FileError('unknown', e?.message ?? String(e), path, e instanceof Error ? e : undefined));
  }
}

const notFound = (path) => new FileError('not_found', `No such file: ${path}`, path);
const unsupported = (what) => err(new FileError('not_supported', `${what} is not supported`));

async function stat(path) {
  const file = await call('fs.stat', { path });
  if (file) return { name: basename(path), path, kind: 'file', size: file.size, mtimeMs: file.mtimeMs };
  const { files } = await call('fs.list', { dir: path });
  if (files.length) {
    const mtimeMs = Math.max(...files.map((f) => f.mtimeMs));
    return { name: basename(path), path, kind: 'directory', size: 0, mtimeMs };
  }
  return undefined;
}

export const hostFileSystem = {
  cwd: '/',

  absolutePath: async (path) => ok(normalize(path.startsWith('/') ? path : `/${path}`)),
  canonicalPath: async (path) => ok(normalize(path)),
  joinPath: async (parts) => ok(normalize(parts.join('/'))),

  readTextFile: (path) => attempt(path, async () => {
    const { text: t } = await call('fs.read', { path });
    if (t == null) throw notFound(path);
    return t;
  }),

  readTextLines: (path, options) => attempt(path, async () => {
    const max = options?.maxLines;
    const { text: t } = await call('fs.read', { path, ...(max != null ? { maxLines: max } : {}) });
    if (t == null) throw notFound(path);
    const lines = splitLines(t).map((l) => l.text);
    return max != null ? lines.slice(0, max) : lines;
  }),

  openTextLineReader: (path) => attempt(path, async () => {
    const { text: t } = await call('fs.read', { path });
    if (t == null) throw notFound(path);
    const lines = splitLines(t);
    let i = 0;
    return {
      readLine: async () => ok(i < lines.length ? lines[i++] : undefined),
      close: async () => {},
    };
  }),

  readBinaryFile: async () => unsupported('Binary files'),

  writeFile: (path, content) => attempt(path, () => call('fs.write', { path, text: text(content) }).then(() => undefined)),
  appendFile: (path, content) => attempt(path, () => call('fs.append', { path, text: text(content) }).then(() => undefined)),
  renameFile: (from, to) => attempt(from, () => call('fs.rename', { from, to }).then(() => undefined)),

  fileInfo: (path) => attempt(path, async () => {
    const info = await stat(normalize(path));
    if (!info) throw notFound(path);
    return info;
  }),

  exists: (path) => attempt(path, async () => (await stat(normalize(path))) !== undefined),

  listDir: (dir) => attempt(dir, async () => {
    const root = normalize(dir);
    const prefix = root === '/' ? '/' : `${root}/`;
    const { files } = await call('fs.list', { dir: root });
    const entries = new Map();
    for (const f of files) {
      const rest = f.path.slice(prefix.length);
      const slash = rest.indexOf('/');
      if (slash < 0) {
        entries.set(rest, { name: rest, path: f.path, kind: 'file', size: f.size, mtimeMs: f.mtimeMs });
      } else {
        const name = rest.slice(0, slash);
        const prev = entries.get(name);
        const mtimeMs = Math.max(prev?.mtimeMs ?? 0, f.mtimeMs);
        entries.set(name, { name, path: prefix + name, kind: 'directory', size: 0, mtimeMs });
      }
    }
    return [...entries.values()];
  }),

  // Directories exist while they hold a file, so there is nothing to create.
  createDir: async () => ok(undefined),

  remove: (path, options) => attempt(path, async () => {
    const p = normalize(path);
    const info = await stat(p);
    if (!info) {
      if (options?.force) return;
      throw notFound(p);
    }
    if (info.kind === 'directory' && !options?.recursive) {
      throw new FileError('is_directory', `Is a directory: ${p}`, p);
    }
    await call('fs.remove', { path: p, recursive: info.kind === 'directory' });
  }),

  createTempDir: async () => unsupported('Temporary directories'),
  createTempFile: async () => unsupported('Temporary files'),
  cleanup: async () => {},
};
