import 'package:fl_pi_llm/fl_pi_llm.dart';

/// Where skills are installed from, as `npx skills add` takes it (the
/// formats are fl_pi_llm's, [LlmSkills.parseSource]). A local path is a
/// folder or a file.
sealed class SkillSource {
  const SkillSource({this.skill});

  /// The one skill wanted of several, by name: `owner/repo@skill`, `#ref@skill`
  /// or `--skill`. Null for all of them, to choose from.
  final String? skill;

  /// Where it is, as the user reads it.
  String get id;

  /// What the lock records, for an update to fetch it again: all of it,
  /// not only the one skill.
  Map<String, Object?> toJson();

  static SkillSource? fromJson(Map<String, Object?> j) => switch (j['type']) {
    'github' => GitHubSource(j['owner'] as String, j['repo'] as String, ref: j['ref'] as String?, path: j['path'] as String?),
    'gitlab' => GitLabSource(Uri.parse(j['project'] as String), ref: j['ref'] as String?, path: j['path'] as String?),
    'download' => DownloadSource(Uri.parse(j['url'] as String)),
    'site' => SiteSource(Uri.parse(j['url'] as String)),
    'local' => LocalSource(j['path'] as String),
    'builtin' => const BuiltinSource(),
    _ => null,
  };

  /// Reads what the user typed or pasted: a source, or a whole
  /// `npx skills add <source> [--skill <name>]` line, as fl_pi_llm reads it
  /// ([LlmSkills.parseSource]). Throws [FormatException] when it is none.
  static SkillSource parse(String input) {
    final (source, skill) = LlmSkills.parseSource(input);
    final parsed = fromJson(source);
    if (parsed == null) throw FormatException('Not a skill source', input);
    return skill == null ? parsed : parsed._withSkill(skill);
  }

  SkillSource _withSkill(String skill);
}

/// A repository on GitHub, fetched as the archive of [ref] (the default
/// branch when null).
final class GitHubSource extends SkillSource {
  const GitHubSource(this.owner, this.repo, {this.ref, this.path, super.skill});

  final String owner;
  final String repo;
  final String? ref;

  /// Where in it to look.
  final String? path;

  @override
  String get id => '$owner/$repo';

  @override
  Map<String, Object?> toJson() => {'type': 'github', 'owner': owner, 'repo': repo, 'ref': ?ref, 'path': ?path};

  @override
  SkillSource _withSkill(String skill) => GitHubSource(owner, repo, ref: ref, path: path, skill: skill);

  @override
  String toString() => [id, if (path != null) '/$path', if (ref != null) '#$ref', if (skill != null) '@$skill'].join();
}

/// A project on GitLab (or a GitLab instance), fetched as the archive of [ref].
final class GitLabSource extends SkillSource {
  const GitLabSource(this.project, {this.ref, this.path, super.skill});

  /// `https://gitlab.com/group/sub/repo`.
  final Uri project;
  final String? ref;
  final String? path;

  @override
  String get id => '$project';

  @override
  Map<String, Object?> toJson() => {'type': 'gitlab', 'project': '$project', 'ref': ?ref, 'path': ?path};

  @override
  SkillSource _withSkill(String skill) => GitLabSource(project, ref: ref, path: path, skill: skill);

  @override
  String toString() => [id, if (path != null) '/$path', if (ref != null) '#$ref', if (skill != null) '@$skill'].join();
}

/// A file: a lone SKILL.md, or an archive of skills.
final class DownloadSource extends SkillSource {
  const DownloadSource(this.url, {super.skill});

  final Uri url;

  @override
  String get id => '$url';

  @override
  Map<String, Object?> toJson() => {'type': 'download', 'url': '$url'};

  @override
  SkillSource _withSkill(String skill) => DownloadSource(url, skill: skill);

  @override
  String toString() => id;
}

/// A site that may publish its skills in a `/.well-known` index.
final class SiteSource extends SkillSource {
  const SiteSource(this.url, {super.skill});

  final Uri url;

  @override
  String get id => '$url';

  @override
  Map<String, Object?> toJson() => {'type': 'site', 'url': '$url'};

  @override
  SkillSource _withSkill(String skill) => SiteSource(url, skill: skill);

  @override
  String toString() => id;
}

/// A folder of skills, or an archive or SKILL.md, on this device.
final class LocalSource extends SkillSource {
  const LocalSource(this.path, {super.skill});

  final String path;

  @override
  String get id => path;

  @override
  Map<String, Object?> toJson() => {'type': 'local', 'path': path};

  @override
  SkillSource _withSkill(String skill) => LocalSource(path, skill: skill);

  @override
  String toString() => id;
}

/// A skill the app ships: installed and replaced by [Skills.syncBuiltin], as
/// the app is updated, and never fetched.
final class BuiltinSource extends SkillSource {
  const BuiltinSource({super.skill});

  @override
  String get id => 'builtin';

  @override
  Map<String, Object?> toJson() => {'type': 'builtin'};

  @override
  SkillSource _withSkill(String skill) => BuiltinSource(skill: skill);

  @override
  String toString() => id;
}
