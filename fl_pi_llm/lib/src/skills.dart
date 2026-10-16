import 'dart:convert';
import 'dart:typed_data';

import 'rust/api/skills.dart' as rs;

/// A `skill` tool call refused: no such skill, no such file. Its message is
/// what the model is told.
final class SkillError implements Exception {
  const SkillError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A skill as the prompt and the tool know it: [dir] is what the model asks
/// for it by.
typedef LlmSkill = ({String dir, String name, String description});

/// A SKILL.md's front matter and the instructions after it.
typedef LlmSkillMd = ({String name, String description, String body});

/// A skill found among a source's files: [dir] its folder there ('' at the
/// root), [files] its own by path relative to [dir], `SKILL.md` by that name.
typedef LlmFoundSkill = ({String name, String description, String dir, Map<String, Uint8List> files});

/// Skills: folders with a SKILL.md, installed from a source. What a skill
/// is, finding them among a source's files the way the `skills` CLI does,
/// reading where a source is, the system prompt part and the `skill` tool are
/// fl_pi_llm's own (Rust, shared with every host); fetching, unpacking and
/// keeping them are the app's. Needs the library loaded ([FlPiLlm.loadLibrary]).
abstract final class LlmSkills {
  /// [md]'s front matter: null unless it names the skill and says what it is
  /// for.
  static LlmSkillMd? parse(String md) {
    final out = rs.skillParse(md: md);
    if (out == null) return null;
    final j = jsonDecode(out) as Map<String, Object?>;
    return (name: j['name'] as String, description: j['description'] as String, body: j['body'] as String);
  }

  /// A skill's directory name, as the CLI makes it (`sanitizeName`).
  static String dirName(String name) => rs.skillDirName(name: name);

  /// The skills in a source's [files], under [path] when given. The first of
  /// a name wins.
  static List<LlmFoundSkill> find(Map<String, Uint8List> files, {String? path}) {
    final mds = {
      for (final MapEntry(:key, :value) in files.entries)
        if (rs.skillIsMd(path: key)) key: utf8.decode(value, allowMalformed: true),
    };
    final found = jsonDecode(rs.skillFind(paths: files.keys.toList(), mds: jsonEncode(mds), path: path)) as List;
    return [
      for (final f in found.cast<Map<String, Object?>>())
        (
          name: f['name'] as String,
          description: f['description'] as String,
          dir: f['dir'] as String,
          files: {for (final p in (f['files'] as List).cast<List>()) p[0] as String: files[p[1] as String]!},
        ),
    ];
  }

  /// Where what the user typed or pasted (a source, or a whole `npx skills
  /// add <source> [--skill <name>]` line) points: the source as a lock keeps
  /// it (`{type, …}`) and the one skill wanted. Throws [FormatException]
  /// when it is none.
  static (Map<String, Object?>, String?) parseSource(String input) {
    final out = jsonDecode(rs.skillSourceParse(input: input)) as Map<String, Object?>;
    if (out['ok'] != true) throw FormatException(out['error'] as String, input);
    return ((out['source'] as Map).cast<String, Object?>(), out['skill'] as String?);
  }

  static ({String name, String description, Map<String, Object?> parameters})? _tool;

  /// The `skill` tool, as the model sees it.
  static ({String name, String description, Map<String, Object?> parameters}) get tool => _tool ??= () {
    final t = jsonDecode(rs.skillTool()) as Map<String, Object?>;
    return (
      name: t['name'] as String,
      description: t['description'] as String,
      parameters: (t['parameters'] as Map).cast<String, Object?>(),
    );
  }();

  /// The skills part of the system prompt over [offered], in that order.
  /// Null with none.
  static String? prompt(Iterable<LlmSkill> offered) => rs.skillPrompt(offered: _encode(offered));

  /// What the `skill` tool answers for [args] over the skills in [root],
  /// offering [offered]. Throws [SkillError] for what the model is told
  /// instead.
  static String run(String root, Iterable<LlmSkill> offered, Map<String, Object?> args) {
    final out = jsonDecode(rs.skillRun(root: root, offered: _encode(offered), args: jsonEncode(args))) as Map<String, Object?>;
    if (out['ok'] != true) throw SkillError(out['error'] as String);
    return out['text'] as String;
  }

  /// [file] of skill [dir] in [root] as text; null when there is no such
  /// text file in it (a link out of it included).
  static String? read(String root, String dir, [String file = 'SKILL.md']) => rs.skillRead(root: root, dir: dir, file: file);

  /// The files of skill [dir] in [root], SKILL.md first.
  static List<String> files(String root, String dir) => rs.skillFiles(root: root, dir: dir);

  static String _encode(Iterable<LlmSkill> skills) => jsonEncode([
    for (final s in skills) {'dir': s.dir, 'name': s.name, 'description': s.description},
  ]);
}
