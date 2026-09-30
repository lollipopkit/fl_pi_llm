import 'dart:convert';
import 'dart:typed_data';

import 'package:yaml/yaml.dart';

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
typedef SkillMd = ({String name, String description, String body});

/// Finds the skills in a source the way the `skills` CLI does
/// (`src/skills.ts`): a SKILL.md at the root is the one skill; otherwise the
/// usual places, and every directory below them that has a SKILL.md, without
/// looking inside one that does; and when those have none, anywhere a few
/// levels down.
abstract final class SkillDiscovery {
  /// Directories searched besides the root, in this order.
  static const _containers = [
    'skills',
    'skills/.curated',
    'skills/.experimental',
    'skills/.system',
    '.agents/skills',
    '.claude/skills',
    '.cline/skills',
    '.codebuddy/skills',
    '.codex/skills',
    '.commandcode/skills',
    '.continue/skills',
    '.factory/skills',
    '.github/skills',
    '.goose/skills',
    '.grok/skills',
    '.iflow/skills',
    '.junie/skills',
    '.kilo/skills',
    '.kilocode/skills',
    '.kimchi/skills',
    '.kiro/skills',
    '.minimax/skills',
    '.mux/skills',
    '.neovate/skills',
    '.opencode/skills',
    '.openhands/skills',
    '.pi/skills',
    '.posit/assistant/skills',
    '.qoder/skills',
    '.roo/skills',
    '.trae/skills',
    '.windsurf/skills',
    '.zcode/skills',
    '.zencoder/skills',
  ];

  static const _containerDepth = 3;
  static const _fallbackDepth = 5;
  static const _skipDirs = {'node_modules', '.git', 'dist', 'build', '__pycache__'};

  /// Files a skill is installed without.
  static const _skipFiles = {'metadata.json'};
  static const _skipFileDirs = {'.git', '__pycache__', '__pypackages__'};

  /// The skills in [files], under [path] when given. The first of a name
  /// wins, as the CLI's does.
  static List<FoundSkill> find(SkillFiles files, {String? path}) {
    final base = path == null || path.isEmpty ? '' : '$path/';
    // Directories that have a SKILL.md, case as it is.
    final skillDirs = <String>{};
    for (final p in files.keys) {
      if (!p.startsWith(base)) continue;
      final slash = p.lastIndexOf('/');
      final name = slash < 0 ? p : p.substring(slash + 1);
      if (name.toLowerCase() == 'skill.md') skillDirs.add(slash < 0 ? '' : p.substring(0, slash));
    }
    final root = base.isEmpty ? '' : base.substring(0, base.length - 1);

    final found = <FoundSkill>[];
    final seen = <String>{};
    void add(String dir) {
      final s = _load(files, dir);
      if (s != null && seen.add(s.name)) found.add(s);
    }

    if (skillDirs.contains(root)) {
      add(root);
      if (found.isNotEmpty) return found;
    }

    // Directories below [dir] with a SKILL.md, not below one that has it.
    List<String> walk(String dir, int depth) {
      final prefix = dir.isEmpty ? '' : '$dir/';
      final out = <String>[];
      for (final d in skillDirs) {
        if (d == dir || !d.startsWith(prefix)) continue;
        final rel = d.substring(prefix.length).split('/');
        if (rel.length > depth || rel.any(_skipDirs.contains)) continue;
        // The nearest one wins: a SKILL.md above this one takes it in.
        var covered = false;
        for (var i = 1; i < rel.length && !covered; i++) {
          covered = skillDirs.contains('$prefix${rel.sublist(0, i).join('/')}');
        }
        if (!covered) out.add(d);
      }
      return out..sort();
    }

    walk(root, 1).forEach(add);
    for (final c in _containers) {
      walk(root.isEmpty ? c : '$root/$c', _containerDepth).forEach(add);
    }
    if (found.isEmpty) walk(root, _fallbackDepth).forEach(add);
    return found;
  }

  static FoundSkill? _load(SkillFiles files, String dir) {
    final prefix = dir.isEmpty ? '' : '$dir/';
    final md = files.entries.firstWhere(
      (e) => e.key.startsWith(prefix) && e.key.substring(prefix.length).toLowerCase() == 'skill.md',
      orElse: () => MapEntry('', Uint8List(0)),
    );
    if (md.key.isEmpty) return null;
    final parsed = parse(utf8.decode(md.value, allowMalformed: true));
    if (parsed == null) return null;
    return FoundSkill(
      name: parsed.name,
      description: parsed.description,
      dir: dir,
      files: {
        for (final MapEntry(:key, :value) in files.entries)
          if (key.startsWith(prefix) && _keeps(key.substring(prefix.length)))
            // `SKILL.md` by that name whatever its case in the source.
            (key == md.key ? 'SKILL.md' : key.substring(prefix.length)): value,
      },
    );
  }

  static bool _keeps(String rel) {
    final parts = rel.split('/');
    return !_skipFiles.contains(parts.last) && !parts.sublist(0, parts.length - 1).any(_skipFileDirs.contains);
  }

  /// A SKILL.md's frontmatter: null unless it names the skill and says what
  /// it is for, both as text.
  static SkillMd? parse(String md) {
    final m = RegExp(r'^---\r?\n([\s\S]*?)\r?\n---\r?\n?([\s\S]*)$').firstMatch(md.replaceFirst('﻿', ''));
    if (m == null) return null;
    Object? yaml;
    try {
      yaml = loadYaml(m[1]!);
    } catch (_) {
      return null;
    }
    if (yaml is! Map) return null;
    final name = yaml['name'], description = yaml['description'];
    if (name is! String || description is! String) return null;
    final n = clean(name), d = clean(description);
    if (n.isEmpty || d.isEmpty) return null;
    return (name: n, description: d, body: m[2]!);
  }

  /// One line of text: no control characters, no escape sequences.
  static String clean(String s) => s
      .replaceAll(RegExp(r'\x1B\[[0-9;?]*[ -/]*[@-~]'), '')
      .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
      .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '')
      .trim();

  /// A skill's directory name, as the CLI makes it (`sanitizeName`).
  static String dirName(String name) {
    var s = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9._]+'), '-');
    s = s.replaceAll(RegExp(r'^[.\-]+|[.\-]+$'), '');
    if (s.length > 255) s = s.substring(0, 255);
    return s.isEmpty ? 'unnamed-skill' : s;
  }
}
