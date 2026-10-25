// TODO: remove once no install keeps a session written before pi-durable
// (fl_pi_llm on pi-agent-core 0.87, `/sessions/<cwd>/<created>_<id>.jsonl`).
//
// Such a session is a tree of entries in one file, with the branch tip the
// harness last stood on. It is moved into a chat's storage once: every
// root-to-leaf path becomes a conversation, forked from the one it shares the
// longest prefix with, so the versions an edit or a regeneration left stay
// where they were. The old file is deleted once the chat holds everything it
// said.
//
// A file may be far larger than the heap, so it is never read whole: the
// host hands it over a few chunks at a time (`legacy.read`), a first pass
// keeps only the shape of the tree and where each entry is, and the second
// reads each entry again as it is written.
//
//   legacy.list   {}                       -> {files: [{path, size, mtimeMs}]}
//   legacy.read   {path, after, maxChars}  -> {chunks: [[seq, text], ...]}
//                 the chunks after `after`, in order, at least one when any
//                 are left; none at the end
//   legacy.remove {path}

import { entryDraft } from './entry.js';

const host = globalThis.__host;
const call = async (name, payload) => JSON.parse(await host.call(name, JSON.stringify(payload)));

/** About how much of a file one `legacy.read` brings. */
const READ_CHARS = 1 << 20;

/** pi named a session `<created>_<id>.jsonl`, the id URI-encoded. */
export function legacyIdOf(path) {
  const name = path.slice(path.lastIndexOf('/') + 1);
  if (!name.endsWith('.jsonl')) return null;
  const stem = name.slice(0, -'.jsonl'.length);
  const at = stem.indexOf('_');
  if (at < 0) return null;
  try {
    return decodeURIComponent(stem.slice(at + 1));
  } catch {
    return null;
  }
}

/** Every legacy session file still waiting to be moved, by chat id. */
export async function legacyFiles() {
  const { files } = await call('legacy.list', {});
  const out = new Map();
  for (const f of files) {
    const id = legacyIdOf(f.path);
    if (id != null) out.set(id, f);
  }
  return out;
}

export const removeLegacy = (file) => call('legacy.remove', { path: file.path });

/**
 * Every line of [path] with where it starts — `[seq, offset]`, the chunk and
 * the character in it — from the chunk after [after]. Stops after the first
 * line when [one].
 */
async function* lines(path, after = -1, offset = 0, one = false) {
  let carry = '';
  let at = null;
  for (;;) {
    const { chunks } = await call('legacy.read', { path, after, maxChars: one ? 1 : READ_CHARS });
    if (!chunks.length) break;
    for (const [seq, text] of chunks) {
      let start = offset;
      offset = 0;
      after = seq;
      for (;;) {
        at ??= [seq, start];
        const nl = text.indexOf('\n', start);
        if (nl < 0) {
          carry += text.slice(start);
          break;
        }
        yield { text: carry + text.slice(start, nl), at };
        if (one) return;
        carry = '';
        at = null;
        start = nl + 1;
      }
    }
  }
  // A torn last line: what came before it is whole.
  if (carry !== '') {
    try {
      JSON.parse(carry);
      yield { text: carry, at };
    } catch { /* dropped */ }
  }
}

/** The writes of one line, or none when it is not JSON. */
function writesOf(text) {
  if (!text.trim()) return [];
  let value;
  try {
    value = JSON.parse(text);
  } catch {
    return [];
  }
  return Array.isArray(value) ? value : [value];
}

const isEntry = (w) => w != null && typeof w === 'object' &&
  (w.kind === 'entry' || (w.kind === undefined && typeof w.id === 'string' && typeof w.type === 'string' && w.type !== 'session'));

/**
 * The shape of the tree in [path]: each entry's parent, seq and where it is,
 * without its content; and the tip and name.
 */
export async function scanLegacy(path) {
  /** id -> {parentId, seq, at: [chunk, offset], index} */
  const entries = new Map();
  let tip;
  let name = null;
  for await (const line of lines(path)) {
    writesOf(line.text).forEach((w, index) => {
      if (isEntry(w)) {
        entries.set(w.id, { parentId: w.parentId ?? null, seq: w.seq ?? 0, at: line.at, index });
      } else if (w?.kind === 'value' && w.namespace === 'pi.branch.tip' && w.key === 'main') {
        tip = w.op === 'delete' ? null : w.value;
      } else if (w?.kind === 'value' && w.namespace === 'pi.session.name') {
        name = w.op === 'delete' ? null : (w.value ?? null);
      }
    });
  }
  return { entries, tip, name };
}

/** The entry [ref] points at, read again from [path]. */
async function readEntry(path, ref) {
  const [seq, offset] = ref.at;
  for await (const line of lines(path, seq - 1, offset, true)) return writesOf(line.text)[ref.index];
  return undefined;
}

/**
 * What a legacy entry is known by on every device: the id pi gave it, which
 * every copy of the session kept (`sync.js`).
 */
const uidOf = (oldId) => `pi:${oldId}`;

/** The new id of the entry legacy compaction [e] kept from, if it kept one. */
function headOf(e, mapped) {
  if (e.type !== 'compaction' && e.type !== 'branch_summary') return undefined;
  // The kept tail starts at the first entry the summary did not replace.
  const kept = e.firstKeptEntryId ?? firstKept(e, mapped);
  return kept == null ? undefined : mapped.get(kept)?.newId ?? undefined;
}

/** pi 0.87 kept the tail as messages; the entry holding the first is the head. */
function firstKept(e, mapped) {
  const first = e.retainedTail?.[0];
  if (!first) return null;
  for (const [oldId, m] of mapped) {
    if (m.timestamp === first.timestamp && m.role === first.role) return oldId;
  }
  return null;
}

/**
 * Moves the legacy session in [file] into [harness]'s empty storage. Returns
 * the conversation and tip the chat should open on, and its name.
 */
export async function migrate(harness, file, BG) {
  const { entries, tip, name } = await scanLegacy(file.path);

  const children = new Map();
  for (const [id, e] of entries) {
    const p = e.parentId;
    if (!children.has(p)) children.set(p, []);
    children.get(p).push(id);
  }
  const leaves = [...entries.keys()].filter((id) => !children.has(id)).sort((a, b) => entries.get(a).seq - entries.get(b).seq);

  /** old id -> {newId, conv, timestamp, role}; `newId` null before a conversation's first entry */
  const mapped = new Map();
  /** conversation id -> the old id of its last entry */
  const lastOf = new Map();
  let root;
  /** Every entry some path has gone through. */
  const visited = new Set();

  /** Moves the path from the root to [leaf]. */
  async function place(leaf) {
    const path = [];
    // A broken file may link back on itself: a path visits an entry once.
    const seen = new Set();
    for (let id = leaf; id != null; id = entries.get(id)?.parentId ?? null) {
      if (!entries.has(id) || seen.has(id)) break;
      seen.add(id);
      visited.add(id);
      path.unshift(id);
    }
    let i = 0;
    while (i < path.length && mapped.has(path[i])) i++;
    if (i === path.length) return;
    let conv;
    if (i === 0) {
      conv = root ? await harness.createConversation({ ownership: { kind: 'ownerless' } }, BG) : await harness.root(BG);
      root ??= conv;
    } else {
      const at = mapped.get(path[i - 1]);
      // A branch ends where another goes on: continue that conversation
      // when this one is its own tip, fork it otherwise — before anything
      // was written, by starting another.
      conv = lastOf.get(at.conv) === path[i - 1]
        ? await harness.conversation(at.conv, BG)
        : at.newId == null
          ? await harness.createConversation({ ownership: { kind: 'ownerless' } }, BG)
          : await (await harness.conversation(at.conv, BG)).fork(at.newId, { ownership: { kind: 'ownerless' } }, BG);
    }
    for (; i < path.length; i++) {
      const id = path[i];
      const e = await readEntry(file.path, entries.get(id));
      const entry = e && entryDraft(e, uidOf(id), headOf(e, mapped));
      if (!entry) {
        // Nothing the chat keeps; what follows hangs off what came before,
        // or off the start of this conversation.
        const prev = i > 0 ? mapped.get(path[i - 1]) : { newId: null, conv: conv.id };
        mapped.set(id, prev);
        if (i === 0 || lastOf.get(prev.conv) === path[i - 1]) lastOf.set(prev.conv, id);
        continue;
      }
      const settled = await (await conv.submit({ type: 'write', entry }, BG)).wait(BG);
      if (settled.status !== 'done') throw new Error(`Could not move entry ${id}: ${settled.reason}`);
      mapped.set(id, { newId: settled.entry, conv: conv.id, timestamp: e.message?.timestamp, role: e.message?.role });
      lastOf.set(conv.id, id);
    }
  }

  for (const leaf of leaves) await place(leaf);
  // A cycle with no leaf off it is reached by no path: started from its
  // newest entry instead of being lost.
  for (;;) {
    const left = [...entries.keys()].filter((id) => !visited.has(id));
    if (!left.length) break;
    await place(left.reduce((a, b) => (entries.get(b).seq > entries.get(a).seq ? b : a)));
  }
  root ??= await harness.root(BG);

  let current = root.id;
  let newTip = null;
  if (tip === null) {
    newTip = -1;
  } else if (tip != null && mapped.has(tip)) {
    const m = mapped.get(tip);
    current = m.conv;
    // On an entry nothing was written for, before the conversation's first.
    if (lastOf.get(m.conv) !== tip) newTip = m.newId ?? -1;
  } else if (leaves.length) {
    const m = mapped.get(leaves[leaves.length - 1]);
    if (m) current = m.conv;
  }
  return { current, tip: newTip, name };
}
