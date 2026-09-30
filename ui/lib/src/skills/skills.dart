import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fl_lib/fl_lib.dart';
import 'package:fl_pi_llm_ui/src/skills/discover.dart';
import 'package:fl_pi_llm_ui/src/skills/fetch.dart';
import 'package:fl_pi_llm_ui/src/skills/source.dart';
import 'package:flutter/foundation.dart';

/// A skill on this device: in its directory under [Skills.root], with what
/// the lock knows of it.
final class InstalledSkill {
  const InstalledSkill({
    required this.dir,
    required this.name,
    required this.description,
    required this.source,
    required this.skillPath,
    required this.hash,
    required this.installedAt,
    required this.updatedAt,
    this.enabled = true,
  });

  /// Its directory's name: what the model asks for it by.
  final String dir;
  final String name;
  final String description;
  final SkillSource? source;

  /// Its SKILL.md's path in [source].
  final String skillPath;

  /// SHA-256 of its files, as `npx skills` computes it: an update is one
  /// whose files hash differently.
  final String hash;
  final DateTime installedAt;
  final DateTime updatedAt;
  final bool enabled;

  /// Shipped with the app: switched off rather than removed, and updated with
  /// the app rather than from a source.
  bool get builtin => source is BuiltinSource;

  InstalledSkill copyWith({bool? enabled}) => InstalledSkill(
    dir: dir,
    name: name,
    description: description,
    source: source,
    skillPath: skillPath,
    hash: hash,
    installedAt: installedAt,
    updatedAt: updatedAt,
    enabled: enabled ?? this.enabled,
  );

  factory InstalledSkill.fromJson(String dir, Map<String, Object?> j) => InstalledSkill(
    dir: dir,
    name: j['name'] as String? ?? dir,
    description: j['description'] as String? ?? '',
    source: switch (j['source']) {
      final Map m => SkillSource.fromJson(m.cast()),
      _ => null,
    },
    skillPath: j['skillPath'] as String? ?? 'SKILL.md',
    hash: j['hash'] as String? ?? '',
    installedAt: DateTime.tryParse(j['installedAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
    enabled: j['enabled'] as bool? ?? true,
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'description': description,
    'source': ?source?.toJson(),
    'skillPath': skillPath,
    'hash': hash,
    'installedAt': installedAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'enabled': enabled,
  };
}

/// The skills installed on this device: plain files, one directory each, as
/// `npx skills` leaves them, and a lock beside them saying where each came
/// from. Not in the database, nor backed up: what a source has can be
/// fetched again.
abstract final class Skills {
  /// A skill's files past these are refused, as the CLI refuses an archive.
  static const maxSkillBytes = 25 * 1024 * 1024;
  static const maxSkillFiles = 1000;

  /// What the model is given of a file at once.
  static const maxReadChars = 256 * 1024;

  static String? _root;

  /// `skills/` in the app's documents. Throws before the app has set
  /// [Paths] up; [all] is empty then instead.
  static String get root => _root ??= '${Paths.doc}/skills';

  static bool get _hasRoot {
    try {
      root;
      return true;
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  static set root(String dir) {
    _root = dir;
    _lock = null;
  }

  static const _lockName = '.lock.json';

  /// Notified when one is installed, removed, updated or switched.
  static final changes = RNode();

  static Map<String, InstalledSkill>? _lock;

  static Map<String, InstalledSkill> get _skills => _lock ??= _readLock();

  static Map<String, InstalledSkill> _readLock() {
    if (!_hasRoot) return {};
    final f = File('$root/$_lockName');
    if (!f.existsSync()) return {};
    try {
      final j = (jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>();
      final skills = (j['skills'] as Map?)?.cast<String, Object?>() ?? const {};
      return {
        for (final MapEntry(:key, :value) in skills.entries)
          if (value is Map && Directory('$root/$key').existsSync()) key: InstalledSkill.fromJson(key, value.cast()),
      };
    } catch (e, s) {
      Loggers.app.warning('Skills lock is unreadable', e, s);
      return {};
    }
  }

  static void _saveLock() {
    Directory(root).createSync(recursive: true);
    final keys = _skills.keys.toList()..sort();
    File('$root/$_lockName').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'version': 1,
        'skills': {for (final k in keys) k: _skills[k]!.toJson()},
      }),
    );
    changes.notify();
  }

  /// Every one, by name.
  static List<InstalledSkill> get all => _skills.values.toList()..sort((a, b) => a.name.compareTo(b.name));

  /// The ones switched on: what the model is told of.
  static List<InstalledSkill> get enabled => [for (final s in all) if (s.enabled) s];

  static InstalledSkill? byDir(String dir) => _skills[dir];

  /// Finds the skills [source] holds, to choose from before installing.
  static Future<FetchedSkills> find(SkillSource source) => SkillFetch.fetch(source);

  /// Installs [skill], found in [source], over one of the same name.
  static Future<InstalledSkill> install(FoundSkill skill, SkillSource source) async {
    final files = skill.files;
    if (files.length > maxSkillFiles) throw StateError('${skill.name} has more than $maxSkillFiles files');
    final size = files.values.fold<int>(0, (a, b) => a + b.length);
    if (size > maxSkillBytes) throw StateError('${skill.name} is larger than ${maxSkillBytes ~/ 1024 ~/ 1024} MB');

    final dir = SkillDiscovery.dirName(skill.name);
    final target = Directory('$root/$dir');
    // Written aside and moved in, so a failure leaves the old one whole.
    final tmp = Directory('$root/.tmp-$dir-${Random().nextInt(1 << 32)}');
    try {
      for (final MapEntry(key: rel, value: bytes) in files.entries) {
        final f = File('${tmp.path}/$rel');
        if (!_inside(tmp.path, f.path)) continue;
        f.parent.createSync(recursive: true);
        f.writeAsBytesSync(bytes);
      }
      if (target.existsSync()) target.deleteSync(recursive: true);
      tmp.renameSync(target.path);
    } finally {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    }
    final now = DateTime.now();
    final old = _skills[dir];
    final installed = InstalledSkill(
      dir: dir,
      name: skill.name,
      description: skill.description,
      source: SkillSource.fromJson(source.toJson()),
      skillPath: skill.skillPath,
      hash: hashOf(files),
      installedAt: old?.installedAt ?? now,
      updatedAt: now,
      enabled: old?.enabled ?? true,
    );
    _skills[dir] = installed;
    _saveLock();
    return installed;
  }

  static void remove(String dir) {
    if (_skills[dir]?.builtin ?? false) throw StateError('$dir comes with the app');
    _drop(dir);
  }

  static void _drop(String dir) {
    final d = Directory('$root/$dir');
    if (_inside(root, d.path) && d.existsSync()) d.deleteSync(recursive: true);
    _skills.remove(dir);
    _saveLock();
  }

  static void setEnabled(String dir, bool on) {
    final s = _skills[dir];
    if (s == null) return;
    _skills[dir] = s.copyWith(enabled: on);
    _saveLock();
  }

  /// Fetches every source again and installs what changed: the names of
  /// those that did, and why a source could not be fetched. A folder or file
  /// that is gone — a copy the picker made, since cleared — is left alone.
  static Future<({List<String> updated, Map<String, String> failed})> update() async {
    final bySource = <String, List<InstalledSkill>>{};
    for (final s in all) {
      if (s.source case final src? when src is! BuiltinSource) (bySource[jsonEncode(src.toJson())] ??= []).add(s);
    }
    final updated = <String>[];
    final failed = <String, String>{};
    for (final group in bySource.values) {
      final source = group.first.source!;
      if (source is LocalSource && FileSystemEntity.typeSync(source.path) == FileSystemEntityType.notFound) continue;
      final List<FoundSkill> found;
      try {
        found = (await SkillFetch.fetch(source)).skills;
      } catch (e, s) {
        Loggers.app.warning('Update skills from ${source.id}', e, s);
        failed[source.id] = '$e';
        continue;
      }
      for (final s in group) {
        final next = found.firstWhereOrNull((f) => f.skillPath == s.skillPath) ??
            found.firstWhereOrNull((f) => f.name == s.name);
        if (next == null || hashOf(next.files) == s.hash) continue;
        await install(next, source);
        updated.add(s.name);
      }
    }
    return (updated: updated, failed: failed);
  }

  /// Installs the skills the app ships, [skills], where they are missing or
  /// differ, and removes the ones it no longer ships. Each keeps its switch.
  /// One the user installed under the same name stays theirs.
  static Future<void> syncBuiltin(List<FoundSkill> skills) async {
    if (!_hasRoot) return;
    final shipped = <String>{};
    for (final s in skills) {
      final dir = SkillDiscovery.dirName(s.name);
      shipped.add(dir);
      final have = _skills[dir];
      if (have != null && (!have.builtin || have.hash == hashOf(s.files))) continue;
      await install(s, const BuiltinSource());
    }
    for (final s in all) {
      if (s.builtin && !shipped.contains(s.dir)) _drop(s.dir);
    }
  }

  /// SHA-256 over the files in path order, each its path then its bytes:
  /// `computedHash` of the CLI's `skills-lock.json`.
  static String hashOf(Map<String, Uint8List> files) {
    final keys = files.keys.toList()..sort();
    final all = BytesBuilder(copy: false);
    for (final k in keys) {
      all
        ..add(utf8.encode(k))
        ..add(files[k]!);
    }
    return sha256.convert(all.takeBytes()).toString();
  }

  /// [dir]'s files, relative to it, SKILL.md first.
  static List<String> filesOf(String dir) {
    final d = Directory('$root/$dir');
    if (!d.existsSync()) return const [];
    final files = [
      for (final f in d.listSync(recursive: true).whereType<File>())
        f.path.substring(d.path.length + 1).replaceAll(r'\', '/'),
    ]..sort();
    return [if (files.remove('SKILL.md')) 'SKILL.md', ...files];
  }

  /// [file] of [dir] as text; null when there is no such file in it.
  static String? read(String dir, [String file = 'SKILL.md']) {
    final f = File('$root/$dir/$file');
    if (!_inside('$root/$dir', f.path) || !f.existsSync()) return null;
    final bytes = f.readAsBytesSync();
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return null;
    }
  }

  /// Whether [path] is under [dir], after `..` and the like are resolved.
  static bool _inside(String dir, String path) {
    final base = Directory(dir).absolute.uri.normalizePath().path;
    final p = File(path).absolute.uri.normalizePath().path;
    return p.startsWith(base.endsWith('/') ? base : '$base/') && p != base;
  }

  /// The skills part of the system prompt: what each is for, the model to
  /// load one with [toolName] when a task matches it. Null with none on.
  static String? prompt(String toolName) {
    final on = enabled;
    if (on.isEmpty) return null;
    final list = [
      for (final s in on) '- ${s.dir}: ${s.description.length > 1024 ? '${s.description.substring(0, 1024)}…' : s.description}',
    ].join('\n');
    return '''# Skills

Skills are instructions for particular tasks that the user installed. When a task matches a skill's description, load the skill with the `$toolName` tool before starting the task, and follow it. A skill may point to its other files by relative path; read those with the same tool when you need them. Scripts in a skill cannot run here unless another tool can run them.

Available skills:
$list''';
  }
}
