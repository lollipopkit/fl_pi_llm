/// Where skills are installed from, as `npx skills add` takes it.
///
/// The formats are the `skills` CLI's (vercel-labs/skills,
/// `src/source-parser.ts`), minus the ones that need a local checkout or git
/// itself: a local path, ssh, Azure Repos and GitHub Enterprise.
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
    _ => null,
  };

  /// Reads what the user typed or pasted: a source, or a whole
  /// `npx skills add <source> [--skill <name>]` line. Throws [FormatException]
  /// when it is none.
  static SkillSource parse(String input) {
    var words = input.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    // A pasted command: `npx skills add`, `bunx skills add`, `skills add`...
    final add = words.indexOf('add');
    if (add > 0 && words[add - 1] == 'skills') words = words.sublist(add + 1);
    String? skill;
    String? source;
    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      if ((w == '--skill' || w == '-s') && i + 1 < words.length) {
        skill = words[++i];
      } else if (w.startsWith('--skill=')) {
        skill = w.substring('--skill='.length);
      } else if (w.startsWith('-')) {
        // Where to install, `-y`, `-g`...: the CLI's, not ours.
        continue;
      } else {
        source ??= w;
      }
    }
    if (source == null) throw const FormatException('No source');
    final parsed = _parse(source);
    return skill == null || skill == '*' ? parsed : parsed._withSkill(skill);
  }

  SkillSource _withSkill(String skill);

  static SkillSource _parse(String input) {
    // `#ref` or `#ref@skill`, on what looks like a repository.
    String? ref, fragSkill;
    var s = input;
    final hash = s.indexOf('#');
    if (hash > 0) {
      final frag = Uri.decodeComponent(s.substring(hash + 1));
      s = s.substring(0, hash);
      final at = frag.indexOf('@');
      ref = at < 0 ? frag : frag.substring(0, at);
      fragSkill = at < 0 ? null : frag.substring(at + 1);
      if (ref.isEmpty) ref = null;
    }
    if (s.startsWith('github:')) return _parse('${s.substring(7)}${_frag(ref, fragSkill)}');
    if (s.startsWith('gitlab:')) return _parse('https://gitlab.com/${s.substring(7)}${_frag(ref, fragSkill)}');

    final uri = Uri.tryParse(s);
    if (uri != null && (uri.isScheme('https') || uri.isScheme('http')) && uri.host.isNotEmpty) {
      return _parseUrl(uri, ref, fragSkill);
    }
    // `owner/repo@skill`
    final atSkill = RegExp(r'^([^/:.][^/:]*)/([^/@:]+)@(.+)$').firstMatch(s);
    if (atSkill != null) {
      return GitHubSource(atSkill[1]!, _repo(atSkill[2]!), ref: ref, skill: fragSkill ?? atSkill[3]);
    }
    // `owner/repo[/subpath]`
    final short = RegExp(r'^([^/:.][^/:]*)/([^/:]+?)(?:/(.+?))?/?$').firstMatch(s);
    if (short != null) {
      return GitHubSource(short[1]!, _repo(short[2]!), ref: ref, path: _subpath(short[3]), skill: fragSkill);
    }
    throw FormatException('Not a skill source', input);
  }

  static String _frag(String? ref, String? skill) =>
      ref == null && skill == null ? '' : '#${ref ?? ''}${skill == null ? '' : '@$skill'}';

  static String _repo(String r) => r.endsWith('.git') ? r.substring(0, r.length - 4) : r;

  /// A path inside the source, which may not climb out of it.
  static String? _subpath(String? p) {
    if (p == null) return null;
    final parts = p.replaceAll(r'\', '/').split('/').where((e) => e.isNotEmpty && e != '.').toList();
    if (parts.contains('..')) throw FormatException('A path out of the source', p);
    return parts.isEmpty ? null : parts.join('/');
  }

  /// [segs] on [u]'s host, and nothing else of [u].
  static Uri _at(Uri u, List<String> segs) => Uri(scheme: u.scheme, host: u.host, port: u.port, pathSegments: segs);

  static SkillSource _parseUrl(Uri u, String? ref, String? skill) {
    final host = u.host.toLowerCase();
    final segs = u.pathSegments.where((e) => e.isNotEmpty).toList();

    // A file to download: an archive, a release asset, a raw SKILL.md.
    final isDownload = switch (host) {
      'raw.githubusercontent.com' || 'codeload.github.com' || 'objects.githubusercontent.com' => true,
      'github.com' => segs.length > 2 && const {'archive', 'raw', 'releases'}.contains(segs[2]),
      'gitlab.com' => RegExp(r'/-/(archive|raw)/').hasMatch(u.path),
      _ => false,
    };
    if (isDownload) return DownloadSource(u, skill: skill);

    if (host == 'github.com' || host == 'www.github.com') {
      if (segs.length < 2) throw FormatException('Not a repository', '$u');
      final owner = segs[0], repo = _repo(segs[1]);
      // `/tree/<ref>/<path>` or `/blob/<ref>/<path>/SKILL.md`: a ref of one
      // segment, as the CLI takes it.
      if (segs.length >= 4 && (segs[2] == 'tree' || segs[2] == 'blob')) {
        var rest = segs.sublist(4);
        if (segs[2] == 'blob' && rest.isNotEmpty && rest.last.toLowerCase() == 'skill.md') {
          rest = rest.sublist(0, rest.length - 1);
        }
        return GitHubSource(owner, repo, ref: segs[3], path: _subpath(rest.join('/')), skill: skill);
      }
      return GitHubSource(owner, repo, ref: ref, skill: skill);
    }

    if (host == 'gitlab.com' || u.path.contains('/-/tree/')) {
      final tree = segs.indexOf('-');
      if (tree > 0 && segs.length > tree + 2 && segs[tree + 1] == 'tree') {
        return GitLabSource(
          _at(u, segs.sublist(0, tree)),
          ref: segs[tree + 2],
          path: _subpath(segs.sublist(tree + 3).join('/')),
          skill: skill,
        );
      }
      if (host == 'gitlab.com' && segs.length >= 2) {
        final last = _repo(segs.last);
        return GitLabSource(
          _at(u, [...segs.sublist(0, segs.length - 1), last]),
          ref: ref,
          skill: skill,
        );
      }
    }
    // A site: its `/.well-known` index, else the file itself.
    return SiteSource(u, skill: skill);
  }
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
