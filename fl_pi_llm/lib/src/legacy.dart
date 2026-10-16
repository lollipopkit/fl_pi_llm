part of 'runtime.dart';

// Sessions fl_pi_llm kept before 0.1.0, when the app stored them as files.
// Exported by `package:fl_pi_llm/legacy.dart` alone. TODO: remove once no
// install keeps one (`js/src/legacy.js`).

/// A session file in [LlmLegacySessions].
final class StoredFile {
  const StoredFile(this.path, this.size, this.modified);

  /// Absolute, POSIX: `/sessions/<cwd>/<created>_<id>.jsonl`.
  final String path;

  /// In UTF-16 code units or bytes; only compared, never summed.
  final int size;
  final DateTime modified;

  Map<String, Object?> toJson() => {
    'path': path,
    'size': size,
    'mtimeMs': modified.millisecondsSinceEpoch,
  };
}

/// The sessions an app kept for fl_pi_llm before 0.1.0, each an append-only
/// JSONL file stored as the chunks it was appended in.
///
/// Read once, to move each into the chat it belongs to, and deleted after.
/// A file may be larger than the engine's heap, so it is read a few chunks
/// at a time, never whole.
abstract interface class LlmLegacySessions {
  /// Every session file left.
  Future<List<StoredFile>> list();

  /// The chunks of [path] after the one numbered [after] (`-1`: from the
  /// first), in order, as `(seq, text)`: at least one when any are left,
  /// then more while they add up to no more than [maxChars]. None at the end.
  Future<List<(int, String)>> read(String path, {required int after, required int maxChars});

  Future<void> remove(String path);
}

/// Moving the sessions of [LlmLegacySessions] into the runtime's directory.
extension LlmLegacyMigration on FlPiLlm {
  /// Where the sessions from before 0.1.0 are. Set it right after
  /// [FlPiLlm.start], before any session is opened: a session moves the
  /// first time it is opened, and one opened before this is set starts
  /// empty, to be replaced by the move later.
  set legacySessions(LlmLegacySessions? sessions) => _legacy = sessions;

  /// Moves every session from before 0.1.0 that is left. Returns those that
  /// could not be moved, by id, with why; opening one tries again.
  Future<Map<String, String>> migrateLegacy() async {
    final v = await _request('sessions.migrate', const {}) as Map;
    return ((v['failed'] as Map?) ?? const {}).cast<String, String>();
  }

  Future<Object?> _legacyCall(String op, Map<String, Object?> p) async {
    final legacy = _legacy;
    switch (op) {
      case 'legacy.list':
        return {'files': [for (final f in await legacy?.list() ?? const <StoredFile>[]) f.toJson()]};
      case 'legacy.read':
        final chunks = await legacy?.read(
          p['path'] as String,
          after: p['after'] as int,
          maxChars: p['maxChars'] as int,
        );
        return {'chunks': [for (final (seq, text) in chunks ?? const <(int, String)>[]) [seq, text]]};
      case 'legacy.remove':
        await legacy?.remove(p['path'] as String);
        return null;
      default:
        throw LlmException('Unknown legacy call: $op');
    }
  }
}
