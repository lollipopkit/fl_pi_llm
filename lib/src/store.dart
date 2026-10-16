/// A session file written before pi-durable, in [LlmLegacySessions].
///
/// TODO: remove with `js/src/legacy.js`.
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

/// The sessions an app kept for fl_pi_llm before pi-durable, each an
/// append-only JSONL file stored as the chunks it was appended in.
///
/// Read once, to move each into the chat it belongs to, and deleted after.
/// A file may be larger than the engine's heap, so it is read a few chunks
/// at a time, never whole.
///
/// TODO: remove once no install keeps a session from before pi-durable
/// (`js/src/legacy.js`).
abstract interface class LlmLegacySessions {
  /// Every session file left.
  Future<List<StoredFile>> list();

  /// The chunks of [path] after the one numbered [after] (`-1`: from the
  /// first), in order, as `(seq, text)`: at least one when any are left,
  /// then more while they add up to no more than [maxChars]. None at the end.
  Future<List<(int, String)>> read(String path, {required int after, required int maxChars});

  Future<void> remove(String path);
}
