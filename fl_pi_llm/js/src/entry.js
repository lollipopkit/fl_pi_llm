// Entries as the host knows them: `type: message | compaction | custom`
// and a `parentId` chain, out of pi-durable's records.

const MESSAGE_ROLES = new Set(['user', 'assistant', 'toolResult']);

/** Whether the host is shown an entry of [kind] whose first message is by [role]: `hostEntry`'s rule. */
export function isShown(kind, role) {
  switch (kind) {
    case 'pi.compaction':
    case 'fl.compaction':
    case 'fl.custom':
      return true;
    case 'pi.system':
    case 'pi.reset':
      return false;
    default:
      return MESSAGE_ROLES.has(role);
  }
}

const textOf = (m) => (typeof m?.content === 'string'
  ? m.content
  : (m?.content ?? []).filter((c) => c.type === 'text').map((c) => c.text).join(''));

/** pi-durable hands the model a summary wrapped in a preamble; the host shows the summary. */
const unwrapSummary = (text) => /<summary>\n?([\s\S]*?)\n?<\/summary>/.exec(text)?.[1] ?? text;

/**
 * One pi-durable entry as the host knows entries, or null for what it never
 * shows (system prompt and tool changes, resets).
 */
export function hostEntry(e, parentId) {
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

const millis = (t) => (typeof t === 'number' ? t : Date.parse(t) || Date.now());

/**
 * An entry in pi's session-file shape — `type: message | custom |
 * compaction`, what a legacy session and a synced chat carry — as the
 * pi-durable entry kept in its place, null for what a chat does not keep.
 * [uid] is what it is known by on every device (`sync.js`); [head], the entry
 * a compaction kept from, here, if it kept any.
 */
export function entryDraft(e, uid, head) {
  const timestamp = millis(e.timestamp);
  switch (e.type) {
    case 'message':
      return e.message ? { kind: 'fl.message', model: [e.message], data: { uid } } : null;
    case 'custom':
      return { kind: 'fl.custom', data: { customType: e.customType ?? '', data: e.data ?? null, timestamp, uid } };
    case 'compaction':
    case 'branch_summary': {
      const summary = e.summary ?? '';
      return {
        kind: 'fl.compaction',
        data: { summary, timestamp, ...(e.tokensBefore != null ? { tokensBefore: e.tokensBefore } : {}), uid },
        model: [{ role: 'user', content: [{ type: 'text', text: summary }], timestamp }],
        head: head ?? 'self',
      };
    }
    default:
      return null;
  }
}
