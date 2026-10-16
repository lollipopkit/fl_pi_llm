import 'dart:typed_data';

import 'package:fl_pi_llm/fl_pi_llm.dart';

/// A source's files: path relative to its root, `/`-separated, and bytes.
typedef SkillFiles = Map<String, Uint8List>;

/// A skill found in a source, before it is installed.
final class FoundSkill {
  const FoundSkill({required this.name, required this.description, required this.dir, required this.files});

  final String name;
  final String description;

  /// Its directory in the source: '' at the root.
  final String dir;

  /// Its files, relative to [dir].
  final SkillFiles files;

  /// `SKILL.md`'s path in the source, as the lock records it.
  String get skillPath => dir.isEmpty ? 'SKILL.md' : '$dir/SKILL.md';
}

/// The `name` and `description` of a SKILL.md, and what is under them.
typedef SkillMd = LlmSkillMd;

/// Finds the skills in a source the way the `skills` CLI does: fl_pi_llm's
/// [LlmSkills], over this package's types.
abstract final class SkillDiscovery {
  /// The skills in [files], under [path] when given. The first of a name
  /// wins, as the CLI's does.
  static List<FoundSkill> find(SkillFiles files, {String? path}) => [
    for (final s in LlmSkills.find(files, path: path))
      FoundSkill(name: s.name, description: s.description, dir: s.dir, files: s.files),
  ];

  /// A SKILL.md's frontmatter: null unless it names the skill and says what
  /// it is for, both as text.
  static SkillMd? parse(String md) => LlmSkills.parse(md);

  /// A skill's directory name, as the CLI makes it (`sanitizeName`).
  static String dirName(String name) => LlmSkills.dirName(name);
}
