import 'dart:convert';

import 'rust/api/memory.dart' as rs;

/// A memory call refused: a path outside it, a file where a directory is,
/// text too long. Its message is what the model is told.
final class MemoryError implements Exception {
  const MemoryError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A memory file as the memory reads it: [key] below [LlmMemory.root],
/// [modified] in milliseconds since the epoch.
typedef LlmMemoryFile = ({String key, String content, int? modified});

/// What a call changes: [remove] goes, [put] (key, content) is written, all
/// or none.
typedef LlmMemoryChange = ({List<(String, String)> put, List<String> remove});

/// A memory tool, as the model sees it.
typedef LlmMemoryTool = ({String name, String label, String description, Map<String, Object?> parameters});

/// The model's memory: text files under `/memories` the `memory_*` tools read
/// and write across chats, with the index in every system prompt. The rules,
/// the tools and the prompt are fl_pi_llm's own (Rust, shared with every
/// host); the files are the app's, handed to each call, which answers with
/// what to change. Needs the library loaded ([FlPiLlm.loadLibrary]).
abstract final class LlmMemory {
  static const root = '/memories';

  /// The index: shown in every chat's system prompt.
  static const index = 'MEMORY.md';

  /// [path] as a key: relative to [root], `/`-separated, empty for the root
  /// itself. Throws [MemoryError] for a path outside it or malformed.
  static String keyOf(String path) {
    final out = jsonDecode(rs.memoryKeyOf(path: path)) as Map<String, Object?>;
    if (out['ok'] != true) throw MemoryError(out['error'] as String);
    return out['key'] as String;
  }

  /// [key] as the model sees it.
  static String pathOf(String key) => key.isEmpty ? root : '$root/$key';

  static List<LlmMemoryTool>? _tools;

  /// Every memory tool.
  static List<LlmMemoryTool> get tools => _tools ??= [
    for (final t in (jsonDecode(rs.memoryTools()) as List).cast<Map<String, Object?>>())
      (
        name: t['name'] as String,
        label: t['label'] as String,
        description: t['description'] as String,
        parameters: (t['parameters'] as Map).cast<String, Object?>(),
      ),
  ];

  /// The memory's part of the system prompt: how to use it when [tools] are
  /// on, the files, and the index. Null when there is nothing to say.
  static String? prompt(Iterable<LlmMemoryFile> files, {required bool tools}) =>
      rs.memoryPrompt(files: _encode(files), tools: tools);

  /// Runs the memory tool [name] with [args] on [files]: what the model is
  /// told and what to change. Throws [MemoryError] for the tool's failure.
  static (String, LlmMemoryChange) run(Iterable<LlmMemoryFile> files, String name, Map<String, Object?> args) {
    final out = jsonDecode(rs.memoryRun(files: _encode(files), name: name, args: jsonEncode(args))) as Map<String, Object?>;
    if (out['ok'] != true) throw MemoryError(out['error'] as String);
    return (
      out['text'] as String,
      (
        put: [for (final p in (out['put'] as List).cast<List>()) (p[0] as String, p[1] as String)],
        remove: (out['remove'] as List).cast<String>(),
      ),
    );
  }

  static String _encode(Iterable<LlmMemoryFile> files) => jsonEncode([
    for (final f in files) {'key': f.key, 'content': f.content, 'modified': ?f.modified},
  ]);
}
