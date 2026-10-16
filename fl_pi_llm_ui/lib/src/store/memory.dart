import 'package:fl_lib/fl_lib.dart';
import 'package:fl_pi_llm/fl_pi_llm.dart';

/// Where the model's memory ([LlmMemory]) keeps its files, across chats.
///
/// One row per file, keyed by its path below `/memories` (`MEMORY.md`,
/// `projects/app.md`); directories are only prefixes. Being a store, it is
/// encrypted with the rest, and backups merge it per file. What may be
/// written is [LlmMemory]'s to decide: every change goes through it.
final class MemoryStore extends SqliteStore {
  MemoryStore._() : super('memory') {
    watch().listen((_) => changes.notify());
  }

  static final instance = MemoryStore._();

  static const root = LlmMemory.root;

  /// The index: shown in every chat's system prompt.
  static const index = LlmMemory.index;

  /// Notified on every change, for the memory page.
  final changes = RNode();

  /// [path] as a key — see [LlmMemory.keyOf]; throws [MemoryError].
  static String keyOf(String path) => LlmMemory.keyOf(path);

  /// [key] as the model sees it.
  static String pathOf(String key) => LlmMemory.pathOf(key);

  /// Every file, by key, sorted.
  Map<String, String> files() {
    final all = getAllMap();
    final keys = all.keys.toList()..sort();
    return {
      for (final k in keys)
        if (all[k] case final String v) k: v,
    };
  }

  /// Every file, as [LlmMemory] reads them.
  List<LlmMemoryFile> all() => [
    for (final MapEntry(:key, :value) in files().entries)
      (key: key, content: value, modified: lastUpdateTs?[key]),
  ];

  String? read(String key) => get<String>(key);

  /// Files at or below [key]: the file itself, or everything in the directory.
  List<String> under(String key) {
    if (key.isEmpty) return files().keys.toList();
    final prefix = '$key/';
    return [
      for (final k in files().keys)
        if (k == key || k.startsWith(prefix)) k,
    ];
  }

  DateTime? modified(String key) {
    final ts = lastUpdateTs?[key];
    return ts == null ? null : DateTime.fromMillisecondsSinceEpoch(ts);
  }

  /// Runs the memory tool [name] with [args] and makes its change: what the
  /// model is told. Throws [MemoryError] for the tool's failure.
  String run(String name, Map<String, Object?> args) {
    final (text, change) = LlmMemory.run(all(), name, args);
    SqliteStore.transact(() {
      for (final k in change.remove) {
        remove(k);
      }
      for (final (k, v) in change.put) {
        set(k, v);
      }
    });
    return text;
  }

  /// Writes [content] to the file at [key], creating it.
  void write(String key, String content) => run('memory_write', {'path': pathOf(key), 'content': content});

  /// Deletes the file or directory at [key]; how many files went.
  int delete(String key) {
    final n = under(key).length;
    if (key.isEmpty || n == 0) return 0;
    run('memory_delete', {'path': pathOf(key)});
    return n;
  }

  /// Moves the file or directory at [from] to [to].
  void move(String from, String to) => run('memory_move', {'from': pathOf(from), 'to': pathOf(to)});
}
