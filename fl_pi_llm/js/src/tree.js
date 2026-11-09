// The shape of a chat: which entries the host is shown, in which
// conversation, after which entry — and nothing they say.
//
// pi-durable's `Storage` hands over whole entries, and the versions of a
// message, the branch a chat stands on and the leaf a version leads to are
// all questions about the shape alone. So the shape is read straight from
// pi-durable's tables, SQLite taking it out of each record, and kept current
// from the commits after the last read. A chat of any length is a few numbers
// per entry here; what entries say is read a page at a time, by id.
//
// The host's tree is pi-durable's conversations flattened: a conversation's
// history is the history it was forked from, up to the fork point, then its
// own entries; an entry's parent is the shown entry before it there.
import { CURRENT_SQLITE_SCHEMA_VERSION } from '@earendil-works/pi-durable/storage/sqlite';
import { isShown } from './entry.js';

// The queries below are against this schema. A pi-durable that changes it
// must have them looked at again.
//
// pi 1.4.0's schema 2 rebuilds the tasks table for the `sleeping` status; the
// tables read here — durable_metadata, conversations, entries — are the same.
if (CURRENT_SQLITE_SCHEMA_VERSION !== 2) {
  throw new Error(`tree.js reads pi-durable SQLite schema 2, not ${CURRENT_SQLITE_SCHEMA_VERSION}`);
}

/** Whether an entry of [kind] is a message to the host, not a summary or the host's own. */
const isMessage = (kind) => kind !== 'pi.compaction' && kind !== 'fl.compaction' && kind !== 'fl.custom';

/** The index of the last of [sorted] at most [max], or -1. */
function lastAtMost(sorted, max) {
  let lo = 0;
  let hi = sorted.length;
  while (lo < hi) {
    const mid = (lo + hi) >> 1;
    if (sorted[mid] <= max) lo = mid + 1;
    else hi = mid;
  }
  return lo - 1;
}

export class ChatTree {
  constructor(db) {
    this.db = db;
    /** The commit sequence everything before has been read up to. */
    this.seq = 0;
    /** conversation id -> {parent: {conversationId, at} | null, own: shown entry ids, ascending} */
    this.conversations = new Map();
    /** shown entry id -> {conversationId, user} */
    this.entries = new Map();
    /** parent id (null at the root) -> shown child ids; built when asked */
    this.childrenOf = null;
  }

  /** Reads what was committed since the last read. One query when nothing was. */
  async refresh() {
    const { next_seq: next } = await this.db.get('SELECT next_seq FROM durable_metadata WHERE singleton = 1');
    if (next === this.seq) return;
    // Few: one per version. Read whole, as ids need not arrive in order.
    const convs = await this.db.all(`SELECT id,
      json_extract(record, '$.parent.conversationId') AS pc,
      json_extract(record, '$.parent.at') AS pa
      FROM conversations ORDER BY id`);
    for (const c of convs) {
      if (this.conversations.has(c.id)) continue;
      this.conversations.set(c.id, { parent: c.pc == null ? null : { conversationId: c.pc, at: c.pa }, own: [] });
    }
    const rows = await this.db.all(`SELECT id, conversation_id AS c,
      json_extract(record, '$.kind') AS k,
      json_extract(record, '$.model[0].role') AS r
      FROM entries WHERE commit_seq >= ? ORDER BY id`, this.seq);
    for (const e of rows) {
      if (!isShown(e.k, e.r) || this.entries.has(e.id)) continue;
      this.entries.set(e.id, { conversationId: e.c, user: isMessage(e.k) && e.r === 'user' });
      const own = this.conversations.get(e.c).own;
      // A commit may carry ids minted before another's.
      own.splice(lastAtMost(own, e.id) + 1, 0, e.id);
    }
    this.seq = next;
    this.childrenOf = null;
  }

  /** The last shown entry of [conversationId]'s history at most [max], or null. */
  lastShown(conversationId, max = Infinity) {
    for (let c = this.conversations.get(conversationId); c;) {
      const i = lastAtMost(c.own, max);
      if (i >= 0) return c.own[i];
      if (!c.parent) return null;
      max = Math.min(max, c.parent.at);
      c = this.conversations.get(c.parent.conversationId);
    }
    return null;
  }

  /** The shown entries of [conversationId]'s history, oldest first, up to [max]. */
  history(conversationId, max = Infinity) {
    const parts = [];
    for (let c = this.conversations.get(conversationId); c;) {
      parts.push(c.own.slice(0, lastAtMost(c.own, max) + 1));
      if (!c.parent) break;
      max = Math.min(max, c.parent.at);
      c = this.conversations.get(c.parent.conversationId);
    }
    return parts.reverse().flat();
  }

  /** The shown entry before [id] in its own history. */
  parentOf(id) {
    return this.lastShown(this.entries.get(id).conversationId, id - 1);
  }

  #children() {
    if (!this.childrenOf) {
      this.childrenOf = new Map();
      for (const id of [...this.entries.keys()].sort((a, b) => a - b)) {
        const p = this.parentOf(id);
        if (!this.childrenOf.has(p)) this.childrenOf.set(p, []);
        this.childrenOf.get(p).push(id);
      }
    }
    return this.childrenOf;
  }

  /** The user messages beside the user message [id], itself included, oldest first. */
  versions(id) {
    return (this.#children().get(this.parentOf(id)) ?? []).filter((c) => this.entries.get(c).user);
  }

  /** The newest leaf under [id]: where switching to its version lands. */
  leafOf(id) {
    const children = this.#children();
    for (;;) {
      const next = children.get(id);
      if (!next?.length) return id;
      id = next[next.length - 1];
    }
  }

  /** The conversation whose history ends at [id], if one does. */
  conversationEndingAt(id) {
    for (const c of [...this.conversations.keys()].sort((a, b) => a - b)) {
      if (this.lastShown(c) === id) return c;
    }
    return undefined;
  }

  /** Every shown entry, oldest first. */
  all() {
    return [...this.entries.keys()].sort((a, b) => a - b);
  }
}
