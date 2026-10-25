// A chat across devices: exported from one, imported into another, both
// keeping what either said.
//
// pi-durable numbers entries per file, so an entry is known across devices
// by a uid of its own: in its record (`data.uid`) when this file wrote it for
// a sync or a legacy move, in `fl_uid` (`rust/src/db.rs`) when pi-durable
// wrote it, given there the first time it is exported.
//
// An export is the chat's tree as the host sees it, in pages, each entry
// after its parent, in pi's session-file shape:
//
//   {uid, parent: uid | null, type: 'message', timestamp, message}
//   {uid, parent, type: 'custom', timestamp, customType, data}
//   {uid, parent, type: 'compaction', timestamp, summary, tokensBefore?, firstKept: uid | null}
//
// An import writes what the chat lacks, each entry after its parent: at the
// end of a conversation that ends there, or in a fork of one that goes on
// past it. A conversation running a turn is never written to; it is forked.
// What is written carries its uid in the same commit, so an import cut short
// goes on where it stopped.
import { BACKGROUND_CONTEXT } from '@earendil-works/chord/context';
import { entryDraft, hostEntry } from './entry.js';

const BG = BACKGROUND_CONTEXT;

/** About how much of a chat one page of an export holds. */
export const PAGE_CHARS = 4 << 20;

/** The uid of every entry of [db] that has one, by entry id. */
async function uids(db) {
  const rows = await db.all(`SELECT e.id AS id, COALESCE(u.uid, json_extract(e.record, '$.data.uid')) AS uid
    FROM entries e LEFT JOIN fl_uid u ON u.id = e.id`);
  return new Map(rows.filter((r) => r.uid != null).map((r) => [r.id, r.uid]));
}

/** The first shown entry of [conversationId]'s history from [head] on, up to [max]. */
function firstShownFrom(shape, conversationId, head, max) {
  return shape.history(conversationId, max).find((id) => id >= head);
}

/**
 * The entries of [chat] after the one numbered [after], up to about
 * [maxChars]; `next` to go on from, null at the end. `tip`: the last entry of
 * the branch the chat stands on, [tipId], by uid.
 */
export async function exportPage(chat, tipId, after = null, maxChars = PAGE_CHARS) {
  const { db, storage, shape } = chat;
  await shape.refresh();
  const ids = shape.all();
  const known = await uids(db);
  const fresh = ids.filter((id) => !known.has(id));
  if (fresh.length) {
    await db.transaction(async (tx) => {
      for (const id of fresh) {
        const uid = crypto.randomUUID();
        await tx.run('INSERT INTO fl_uid (id, uid) VALUES (?, ?)', id, uid);
        known.set(id, uid);
      }
    });
  }
  const entries = [];
  let chars = 0;
  let next = null;
  for (const id of ids) {
    if (after != null && id <= after) continue;
    if (entries.length && chars >= maxChars) break;
    const record = (await storage.entry(id, BG)).entry;
    const e = hostEntry(record, null);
    const parent = shape.parentOf(id);
    const out = { uid: known.get(id), parent: parent == null ? null : known.get(parent), type: e.type, timestamp: e.timestamp };
    switch (e.type) {
      case 'message':
        out.message = e.message;
        break;
      case 'custom':
        out.customType = e.customType;
        out.data = e.data;
        break;
      case 'compaction': {
        // A head pi-durable set may be an entry the host is not shown: the
        // kept tail starts at the first shown one from there.
        const head = typeof record.head === 'number' && record.head !== id
          ? firstShownFrom(shape, shape.entries.get(id).conversationId, record.head, id - 1)
          : undefined;
        out.summary = e.summary;
        if (e.tokensBefore != null) out.tokensBefore = e.tokensBefore;
        out.firstKept = head == null ? null : known.get(head);
        break;
      }
    }
    chars += JSON.stringify(out).length;
    entries.push(out);
    next = id;
  }
  if (next === ids.at(-1)) next = null;
  return { entries, next, tip: tipId == null ? null : known.get(tipId) ?? null };
}

/**
 * Writes the [entries] of an export page [chat] lacks. Returns how many it
 * wrote; the uids of those it could not, their parent missing here and in
 * the page; and every entry's id here, by uid.
 */
export async function importPage(chat, entries) {
  const { harness, db, shape } = chat;
  await shape.refresh();
  const local = await uids(db);
  /** uid -> local id */
  const known = new Map([...local].map(([id, uid]) => [uid, id]));
  /** local id -> its conversation */
  const convOf = (id) => shape.entries.get(id)?.conversationId ?? written.get(id);
  const written = new Map();
  /** conversation id -> the last shown entry of its history, null for none */
  const ends = new Map([...shape.conversations.keys()].map((c) => [c, shape.lastShown(c)]));
  const inspection = await harness.inspect(BG);
  const busy = new Set([
    ...inspection.tasks.map((t) => t.record.conversationId),
    ...inspection.submissions.map((s) => s.conversationId),
  ]);

  /** What is waiting to be written to one conversation, in one commit. */
  let run = null;
  let added = 0;
  const orphans = [];

  async function flush() {
    if (!run?.drafts.length) return;
    const { conversationId, drafts } = run;
    run = null;
    const ids = await harness.commit(async (tx) => {
      const out = [];
      for (const d of drafts) out.push((await tx.appendEntry(conversationId, d.draft)).id);
      return out;
    }, BG);
    drafts.forEach((d, i) => {
      known.set(d.uid, ids[i]);
      written.set(ids[i], conversationId);
    });
    ends.set(conversationId, ids.at(-1));
    added += drafts.length;
  }

  /** The conversation the entry after [parentId] (null: the first) goes to. */
  async function conversationAfter(parentId) {
    for (const [c, end] of ends) {
      if (end === parentId && !busy.has(c)) return c;
    }
    const conv = parentId == null
      ? await harness.createConversation({ ownership: { kind: 'ownerless' } }, BG)
      : await (await harness.conversation(convOf(parentId), BG)).fork(parentId, { ownership: { kind: 'ownerless' } }, BG);
    ends.set(conv.id, parentId);
    return conv.id;
  }

  // An empty chat takes the first entries on its root, as one written here would.
  if (!shape.all().length) {
    const root = await harness.root(BG);
    if (!ends.has(root.id)) ends.set(root.id, null);
  }

  for (const e of entries) {
    if (e?.uid == null || known.has(e.uid) || run?.uids.has(e.uid)) continue;
    // What it hangs off, or the head it keeps from, must have an id first.
    const pending = (uid) => uid != null && run?.uids.has(uid) && run.last !== uid;
    if (pending(e.parent) || (e.firstKept != null && run?.uids.has(e.firstKept))) await flush();
    const parentId = e.parent == null ? null : known.get(e.parent);
    if (e.parent != null && parentId == null && run?.last !== e.parent) {
      orphans.push(e.uid);
      continue;
    }
    const head = e.firstKept == null ? undefined : known.get(e.firstKept);
    const draft = entryDraft(e, e.uid, head);
    if (!draft) continue;
    if (!run || run.last !== (e.parent ?? null) || e.parent == null) {
      await flush();
      run = { conversationId: await conversationAfter(parentId), drafts: [], uids: new Set(), last: null };
    }
    run.drafts.push({ uid: e.uid, draft });
    run.uids.add(e.uid);
    run.last = e.uid;
  }
  await flush();
  return { added, orphans, known };
}
