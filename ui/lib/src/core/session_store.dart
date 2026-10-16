import 'package:fl_lib/fl_lib.dart';
import 'package:fl_pi_llm/fl_pi_llm.dart';

/// The sessions fl_pi_llm kept in the app's encrypted SQLite database before
/// pi-durable, read once to move each into its chat.
///
/// A session was an append-only JSONL file, stored as its appended chunks,
/// one row each. They are read a few chunks at a time: a long session is
/// larger than the engine's heap.
///
/// Rows under `/chats/` and `/meta/` are what development builds on
/// pi-durable's JSONL storage wrote; nothing reads them.
///
/// TODO: remove, with `pi_chunks`, once no install keeps a session from
/// before pi-durable (`js/src/legacy.js` in fl_pi_llm).
final class SqliteLegacySessions implements LlmLegacySessions {
  const SqliteLegacySessions();

  static const _root = '/sessions/';

  static bool get _exists => SqliteDb.instance
      .select("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'pi_chunks';")
      .isNotEmpty;

  @override
  Future<List<StoredFile>> list() async {
    if (!_exists) return const [];
    final rows = SqliteDb.instance.select(
      '''
SELECT path, SUM(length(text)) AS size, MAX(mtime) AS mtime FROM pi_chunks
WHERE substr(path, 1, length(?1)) = ?1 GROUP BY path;
''',
      [_root],
    );
    return [
      for (final r in rows)
        StoredFile(r['path'] as String, r['size'] as int, DateTime.fromMillisecondsSinceEpoch(r['mtime'] as int)),
    ];
  }

  @override
  Future<List<(int, String)>> read(String path, {required int after, required int maxChars}) async {
    if (!_exists) return const [];
    final out = <(int, String)>[];
    var chars = 0;
    var cursor = after;
    // A page of rows at a time: a single long chunk stays one row.
    while (true) {
      final rows = SqliteDb.instance.select(
        'SELECT seq, text FROM pi_chunks WHERE path = ? AND seq > ? ORDER BY seq LIMIT 64;',
        [path, cursor],
      );
      for (final r in rows) {
        final text = r['text'] as String;
        if (out.isNotEmpty && chars + text.length > maxChars) return out;
        chars += text.length;
        cursor = r['seq'] as int;
        out.add((cursor, text));
      }
      if (rows.length < 64) return out;
    }
  }

  @override
  Future<void> remove(String path) async {
    SqliteDb.instance.execute('DELETE FROM pi_chunks WHERE path = ?;', [path]);
    // What could be fetched again: the model lists pi-agent-core cached.
    SqliteDb.instance.execute("DELETE FROM pi_chunks WHERE substr(path, 1, 8) = '/models/';");
  }
}
