import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:fl_pi_llm_ui/src/skills/discover.dart';
import 'package:fl_pi_llm_ui/src/skills/source.dart';
import 'package:flutter/foundation.dart';

/// What a source turned out to hold.
typedef FetchedSkills = ({List<FoundSkill> skills, SkillSource source});

/// Fetches a [SkillSource] over HTTP and finds the skills in it.
///
/// Where the `skills` CLI clones with git, this downloads the archive of the
/// ref instead: GitHub's and GitLab's are what a clone of depth one would
/// check out. A site is asked for its `/.well-known` index first.
abstract final class SkillFetch {
  static const maxDownload = 50 * 1024 * 1024;
  static const maxExtracted = 200 * 1024 * 1024;
  static const maxEntries = 20000;

  /// Where GitHub and GitLab are, for tests.
  @visibleForTesting
  static String github = 'https://github.com';
  @visibleForTesting
  static String? gitlabApi;

  static final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
      headers: {'User-Agent': 'fl_pi_llm'},
    ),
  );

  static Future<FetchedSkills> fetch(SkillSource source) async {
    final skills = switch (source) {
      GitHubSource(:final owner, :final repo, :final ref, :final path) => SkillDiscovery.find(
        await _archive(Uri.parse('$github/$owner/$repo/archive/${ref ?? 'HEAD'}.tar.gz')),
        path: path,
      ),
      GitLabSource(:final project, :final ref, :final path) => SkillDiscovery.find(
        await _archive(_gitlabArchive(project, ref)),
        path: path,
      ),
      DownloadSource(:final url) => await _download(url),
      SiteSource(:final url) => await _wellKnown(url) ?? await _download(url),
    };
    final wanted = source.skill?.toLowerCase();
    return (
      skills: wanted == null ? skills : skills.where((s) => s.name.toLowerCase() == wanted).toList(),
      source: source,
    );
  }

  static Uri _gitlabArchive(Uri project, String? ref) {
    final api = gitlabApi ?? '${project.scheme}://${project.host}${project.hasPort ? ':${project.port}' : ''}/api/v4';
    final id = Uri.encodeComponent(project.pathSegments.where((e) => e.isNotEmpty).join('/'));
    return Uri.parse('$api/projects/$id/repository/archive.tar.gz${ref == null ? '' : '?sha=${Uri.encodeQueryComponent(ref)}'}');
  }

  /// [url]'s body, refused past [max] bytes. Only `https`, or `http` to this
  /// device: a skill is instructions the model follows, and one that crossed
  /// the network in the clear could have been rewritten on the way.
  static Future<Uint8List> _get(Uri url, {int max = maxDownload}) async {
    if (!_secure(url)) throw StateError('Not fetching $url over plain http');
    final res = await _dio.getUri<ResponseBody>(url, options: Options(responseType: ResponseType.stream));
    final out = BytesBuilder(copy: false);
    await for (final chunk in res.data!.stream) {
      out.add(chunk);
      if (out.length > max) throw StateError('$url is larger than ${max ~/ 1024 ~/ 1024} MB');
    }
    return out.takeBytes();
  }

  static bool _secure(Uri u) =>
      u.isScheme('https') || (u.isScheme('http') && (u.host == 'localhost' || (InternetAddress.tryParse(u.host)?.isLoopback ?? false)));

  static Future<SkillFiles> _archive(Uri url) async => extract(await _get(url));

  /// A lone SKILL.md, or an archive of skills.
  static Future<List<FoundSkill>> _download(Uri url) async {
    final bytes = await _get(url);
    final text = _asText(bytes);
    if (text != null && SkillDiscovery.parse(text) != null) {
      return SkillDiscovery.find({'SKILL.md': bytes});
    }
    return SkillDiscovery.find(extract(bytes));
  }

  static String? _asText(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return null;
    }
  }

  /// The files in a zip, tar or gzipped tar, from the one directory they are
  /// all in when they are. Absolute paths, `..` and links are left out.
  static SkillFiles extract(Uint8List bytes) {
    final Archive archive;
    if (bytes.length > 3 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
      archive = ZipDecoder().decodeBytes(bytes);
    } else {
      final tar = bytes.length > 2 && bytes[0] == 0x1F && bytes[1] == 0x8B ? GZipDecoder().decodeBytes(bytes) : bytes;
      if (tar.length > maxExtracted) throw StateError('The archive is larger than ${maxExtracted ~/ 1024 ~/ 1024} MB');
      archive = TarDecoder().decodeBytes(tar);
    }
    if (archive.length > maxEntries) throw StateError('The archive has more than $maxEntries entries');
    final files = <String, Uint8List>{};
    var total = 0;
    for (final f in archive) {
      if (!f.isFile || f.isSymbolicLink) continue;
      final name = f.name.replaceAll(r'\', '/');
      final parts = name.split('/').where((e) => e.isNotEmpty && e != '.').toList();
      if (name.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(name) || parts.contains('..') || parts.isEmpty) {
        continue;
      }
      if (parts.first == '__MACOSX' || parts.last == 'pax_global_header') continue;
      final content = f.content;
      total += content.length;
      if (total > maxExtracted) throw StateError('The archive is larger than ${maxExtracted ~/ 1024 ~/ 1024} MB');
      files[parts.join('/')] = content;
    }
    // GitHub's and GitLab's archives put everything under `<repo>-<ref>/`.
    final tops = {for (final p in files.keys) p.contains('/') ? p.substring(0, p.indexOf('/')) : ''};
    if (tops.length == 1 && tops.first.isNotEmpty) {
      final cut = tops.first.length + 1;
      return {for (final MapEntry(:key, :value) in files.entries) key.substring(cut): value};
    }
    return files;
  }

  static Uri _path(Uri u, String path) => Uri(scheme: u.scheme, host: u.host, port: u.port, path: path);

  /// The skills a site lists at `/.well-known/agent-skills/index.json` (or
  /// the older `/.well-known/skills/`), under [url]'s path first; null when
  /// it has no index.
  static Future<List<FoundSkill>?> _wellKnown(Uri url) async {
    final base = url.path.endsWith('/') ? url.path.substring(0, url.path.length - 1) : url.path;
    final scoped = base.isNotEmpty;
    final candidates = [
      for (final dir in ['agent-skills', 'skills']) ...[
        if (scoped) _path(url, '$base/.well-known/$dir/index.json'),
        // A URL with a path of its own is not answered from the root's index.
        if (!scoped) _path(url, '/.well-known/$dir/index.json'),
      ],
    ];
    for (final index in candidates) {
      Map<String, Object?> json;
      try {
        final body = await _get(index, max: 1024 * 1024);
        json = (jsonDecode(utf8.decode(body)) as Map).cast();
      } catch (_) {
        continue;
      }
      final entries = (json['skills'] as List?)?.whereType<Map>().toList();
      if (entries == null) continue;
      final dir = index.resolve('.');
      final out = <FoundSkill>[];
      for (final e in entries) {
        final name = e['name'], description = e['description'];
        if (name is! String || !RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$').hasMatch(name) || name.length > 64) continue;
        if (description is! String || description.isEmpty) continue;
        final SkillFiles files;
        if (json[r'$schema'] != null) {
          // v0.2: one artifact, a SKILL.md or an archive, checked by digest.
          final artifact = e['url'], digest = e['digest'];
          if (artifact is! String || digest is! String || !digest.startsWith('sha256:')) continue;
          final bytes = await _get(dir.resolve(artifact));
          if ('sha256:${sha256.convert(bytes)}' != digest) throw StateError('$name does not match its digest');
          files = e['type'] == 'archive' ? extract(bytes) : {'SKILL.md': bytes};
        } else {
          // v0.1: its files, one by one, beside the index.
          final names = (e['files'] as List?)?.whereType<String>().toList() ?? const [];
          if (!names.contains('SKILL.md')) continue;
          files = {
            for (final f in names)
              if (!f.startsWith('/') && !f.contains('..') && !f.contains(r'\') && !f.contains('\x00'))
                f: await _get(dir.resolve('$name/$f')),
          };
        }
        out.addAll(SkillDiscovery.find(files).take(1));
      }
      return out;
    }
    return null;
  }
}
