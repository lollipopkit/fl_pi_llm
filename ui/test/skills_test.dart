// Skills, installed the way `npx skills add` installs them, over HTTP from a
// server on this device standing in for GitHub and for a site.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:fl_pi_llm/fl_pi_llm.dart';
import 'package:fl_pi_llm_ui/src/skills/discover.dart';
import 'package:fl_pi_llm_ui/src/skills/fetch.dart';
import 'package:fl_pi_llm_ui/src/skills/skills.dart';
import 'package:fl_pi_llm_ui/src/skills/source.dart';
import 'package:fl_pi_llm_ui/src/tools/tool.dart';
import 'package:flutter_test/flutter_test.dart';

String _md(String name, [String description = 'Does a thing.', String body = 'Steps.']) =>
    '---\nname: $name\ndescription: $description\n---\n$body\n';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

/// [files] as GitHub serves a repository's archive: gzipped tar, under one
/// `<repo>-<ref>/` directory.
Uint8List _targz(Map<String, String> files, {String top = 'repo-main'}) {
  final a = Archive();
  for (final MapEntry(:key, :value) in files.entries) {
    a.addFile(ArchiveFile.bytes('$top/$key', utf8.encode(value)));
  }
  return GZipEncoder().encodeBytes(TarEncoder().encodeBytes(a));
}

void main() {
  // Real sockets to the mock: `flutter test` stubs `HttpClient` otherwise.
  setUpAll(() => HttpOverrides.global = null);

  group('a source', () {
    SkillSource p(String s) => SkillSource.parse(s);

    test('in the forms `npx skills add` takes', () {
      expect(p('anthropics/skills'), isA<GitHubSource>().having((s) => s.id, 'id', 'anthropics/skills'));
      expect(
        p('anthropics/skills@pdf'),
        isA<GitHubSource>().having((s) => s.skill, 'skill', 'pdf').having((s) => s.path, 'path', isNull),
      );
      expect(p('o/r/skills/pdf'), isA<GitHubSource>().having((s) => s.path, 'path', 'skills/pdf'));
      expect(
        p('o/r#dev@pdf'),
        isA<GitHubSource>().having((s) => s.ref, 'ref', 'dev').having((s) => s.skill, 'skill', 'pdf'),
      );
      expect(p('github:o/r'), isA<GitHubSource>());
      expect(
        p('https://github.com/o/r/tree/main/skills/pdf'),
        isA<GitHubSource>().having((s) => s.ref, 'ref', 'main').having((s) => s.path, 'path', 'skills/pdf'),
      );
      expect(
        p('https://github.com/o/r/blob/main/skills/pdf/SKILL.md'),
        isA<GitHubSource>().having((s) => s.path, 'path', 'skills/pdf'),
      );
      expect(p('https://github.com/o/r.git'), isA<GitHubSource>().having((s) => s.repo, 'repo', 'r'));
      expect(
        p('https://gitlab.com/g/sub/r/-/tree/v1/skills'),
        isA<GitLabSource>()
            .having((s) => '${s.project}', 'project', 'https://gitlab.com/g/sub/r')
            .having((s) => s.ref, 'ref', 'v1')
            .having((s) => s.path, 'path', 'skills'),
      );
      expect(p('gitlab:g/r'), isA<GitLabSource>());
      expect(p('https://raw.githubusercontent.com/o/r/main/SKILL.md'), isA<DownloadSource>());
      expect(p('https://github.com/o/r/archive/refs/heads/main.zip'), isA<DownloadSource>());
      expect(p('https://example.com/docs'), isA<SiteSource>());
      expect(p('/Users/me/skills'), isA<LocalSource>().having((s) => s.path, 'path', '/Users/me/skills'));
      expect(p('~/Downloads/pdf.zip'), isA<LocalSource>());
      expect(p(r'C:\skills'), isA<LocalSource>());
    });

    test('pasted as a whole command', () {
      final s = p('npx skills add vercel-labs/agent-skills --skill frontend-design -g -y');
      expect(s, isA<GitHubSource>().having((s) => s.id, 'id', 'vercel-labs/agent-skills'));
      expect(s.skill, 'frontend-design');
      expect(p('bunx skills add o/r -s=x --skill=y').skill, 'y');
    });

    test('not one', () {
      for (final bad in ['', 'npx skills add', 'just-a-word', 'o/r/../../etc']) {
        expect(() => p(bad), throwsFormatException, reason: bad);
      }
    });

    test('kept in the lock, and read back', () {
      for (final s in [p('o/r/skills#dev'), p('https://gitlab.com/g/r'), p('https://example.com/x'), p('/tmp/s')]) {
        expect(SkillSource.fromJson(s.toJson())!.toJson(), s.toJson());
      }
    });
  });

  group('finding skills', () {
    SkillFiles f(Map<String, String> m) => {for (final e in m.entries) e.key: _b(e.value)};

    test('a SKILL.md at the root is the one skill', () {
      final found = SkillDiscovery.find(f({'SKILL.md': _md('root'), 'skills/other/SKILL.md': _md('other')}));
      expect(found.map((s) => s.name), ['root']);
      expect(found.single.skillPath, 'SKILL.md');
    });

    test('in the usual places, the nearest SKILL.md taking in what is below it', () {
      final found = SkillDiscovery.find(
        f({
          'README.md': '#',
          'skills/pdf/SKILL.md': _md('pdf'),
          'skills/pdf/reference/forms.md': 'forms',
          'skills/pdf/inner/SKILL.md': _md('inner'),
          '.claude/skills/review/skill.md': _md('review'),
          'top/SKILL.md': _md('top'),
          'node_modules/x/SKILL.md': _md('dep'),
        }),
      );
      expect(found.map((s) => s.name), ['top', 'pdf', 'review']);
      final pdf = found[1];
      expect(pdf.files.keys, unorderedEquals(['SKILL.md', 'reference/forms.md', 'inner/SKILL.md']));
      expect(found[2].files.keys, ['SKILL.md'], reason: 'named SKILL.md whatever its case');
    });

    test('anywhere a few levels down when the usual places have none', () {
      final found = SkillDiscovery.find(f({'a/b/c/SKILL.md': _md('deep'), 'a/b/c/d/e/f/g/SKILL.md': _md('too-deep')}));
      expect(found.map((s) => s.name), ['deep']);
    });

    test('only with a name and a description, and one of each name', () {
      final found = SkillDiscovery.find(
        f({
          'skills/a/SKILL.md': '# no frontmatter',
          'skills/b/SKILL.md': '---\nname: b\n---\n',
          'skills/c/SKILL.md': '---\nname: [x]\ndescription: y\n---\n',
          'skills/d/SKILL.md': _md('same'),
          'skills/e/SKILL.md': _md('same', 'Another.'),
        }),
      );
      expect(found.map((s) => s.dir), ['skills/d']);
    });

    test('under the path a source names', () {
      final files = f({'skills/a/SKILL.md': _md('a'), 'skills/b/SKILL.md': _md('b')});
      expect(SkillDiscovery.find(files, path: 'skills/b').map((s) => s.name), ['b']);
    });

    test('names made safe for a directory', () {
      expect(SkillDiscovery.dirName('My Skill: PDF!'), 'my-skill-pdf');
      expect(SkillDiscovery.dirName('../..'), 'unnamed-skill');
      expect(SkillDiscovery.clean('a\n\x1B[31mb\x07'), 'a b');
    });
  });

  test('an archive is unpacked without anything outside it', () {
    final a = Archive()
      ..addFile(ArchiveFile.bytes('repo-main/skills/x/SKILL.md', utf8.encode(_md('x'))))
      ..addFile(ArchiveFile.bytes('repo-main/../../escape', [1]))
      ..addFile(ArchiveFile.bytes('/abs', [1]));
    final files = SkillFetch.extract(GZipEncoder().encodeBytes(TarEncoder().encodeBytes(a)));
    expect(files.keys, ['skills/x/SKILL.md']);
    final zip = SkillFetch.extract(
      ZipEncoder().encodeBytes(Archive()..addFile(ArchiveFile.bytes('SKILL.md', utf8.encode(_md('z'))))),
    );
    expect(zip.keys, ['SKILL.md']);
  });

  group('installed', () {
    late HttpServer server;
    late Map<String, Uint8List> served;
    late String base;
    late Directory root;

    setUp(() async {
      served = {};
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final body = served[req.uri.path];
        req.response.statusCode = body == null ? 404 : 200;
        if (body != null) req.response.add(body);
        await req.response.close();
      });
      base = 'http://127.0.0.1:${server.port}';
      SkillFetch.github = base;
      root = Directory.systemTemp.createTempSync('skills');
      Skills.root = root.path;
    });

    tearDown(() async {
      await server.close(force: true);
      root.deleteSync(recursive: true);
    });

    Future<void> installAll(String input) async {
      final found = await Skills.find(SkillSource.parse(input));
      for (final s in found.skills) {
        await Skills.install(s, found.source);
      }
    }

    test('from GitHub: the default branch, its files, and the lock', () async {
      served['/o/r/archive/HEAD.tar.gz'] = _targz({
        'skills/pdf/SKILL.md': _md('pdf', 'Fill PDF forms.'),
        'skills/pdf/forms.md': 'How to fill a form.',
        'skills/pdf/metadata.json': '{}',
        'skills/web/SKILL.md': _md('web'),
      });
      await installAll('npx skills add o/r --skill pdf');

      expect(Skills.all.map((s) => s.name), ['pdf']);
      final pdf = Skills.all.single;
      expect(pdf.skillPath, 'skills/pdf/SKILL.md');
      expect(Skills.filesOf('pdf'), ['SKILL.md', 'forms.md'], reason: 'metadata.json is left out');
      final lock = jsonDecode(File('${root.path}/.lock.json').readAsStringSync()) as Map;
      expect((lock['skills'] as Map)['pdf']['source'], {'type': 'github', 'owner': 'o', 'repo': 'r'});
    });

    test('an update installs only what changed', () async {
      served['/o/r/archive/HEAD.tar.gz'] = _targz({
        'skills/a/SKILL.md': _md('a'),
        'skills/b/SKILL.md': _md('b'),
      });
      await installAll('o/r');
      Skills.setEnabled('b', false);
      expect((await Skills.update()).updated, isEmpty);

      served['/o/r/archive/HEAD.tar.gz'] = _targz({
        'skills/a/SKILL.md': _md('a'),
        'skills/b/SKILL.md': _md('b', 'Does a thing.', 'New steps.'),
      });
      expect((await Skills.update()).updated, ['b']);
      expect(Skills.read('b'), contains('New steps.'));
      expect(Skills.byDir('b')!.enabled, isFalse, reason: 'an update keeps the switch');
    });

    test('a lone SKILL.md by its link', () async {
      served['/SKILL.md'] = _b(_md('lone'));
      await installAll('$base/SKILL.md');
      expect(Skills.all.single.name, 'lone');
    });

    test("a site's well-known index, both versions", () async {
      served['/docs/.well-known/agent-skills/index.json'] = _b(
        jsonEncode({
          'skills': [
            {'name': 'v1-skill', 'description': 'One.', 'files': ['SKILL.md', 'ref/a.md', '../escape']},
          ],
        }),
      );
      served['/docs/.well-known/agent-skills/v1-skill/SKILL.md'] = _b(_md('v1-skill', 'One.'));
      served['/docs/.well-known/agent-skills/v1-skill/ref/a.md'] = _b('A');
      await installAll('$base/docs');
      expect(Skills.filesOf('v1-skill'), ['SKILL.md', 'ref/a.md']);

      final md = _b(_md('v2-skill', 'Two.'));
      served['/.well-known/skills/index.json'] = _b(
        jsonEncode({
          r'$schema': 'https://schemas.agentskills.io/discovery/0.2.0/schema.json',
          'skills': [
            {'name': 'v2-skill', 'type': 'skill-md', 'description': 'Two.', 'url': 'v2.md', 'digest': 'sha256:${sha256.convert(md)}'},
          ],
        }),
      );
      served['/.well-known/skills/v2.md'] = md;
      await installAll(base);
      expect(Skills.byDir('v2-skill'), isNotNull);

      served['/.well-known/skills/v2.md'] = _b(_md('v2-skill', 'Tampered.'));
      await expectLater(Skills.find(SkillSource.parse(base)), throwsStateError, reason: 'the digest no longer matches');
    });

    test('never over plain http to another machine', () async {
      await expectLater(Skills.find(SkillSource.parse('http://example.com/SKILL.md')), throwsStateError);
    });

    test('from a folder, without what a repository keeps beside it', () async {
      final dir = Directory.systemTemp.createTempSync('src');
      addTearDown(() => dir.deleteSync(recursive: true));
      void write(String rel, String text) => (File('${dir.path}/$rel')..createSync(recursive: true)).writeAsStringSync(text);
      write('skills/pdf/SKILL.md', _md('pdf'));
      write('skills/pdf/forms.md', 'Forms.');
      write('.git/skills/x/SKILL.md', _md('from-git'));
      write('node_modules/y/SKILL.md', _md('from-deps'));
      await installAll(dir.path);
      expect(Skills.all.map((s) => s.name), ['pdf']);
      expect(Skills.filesOf('pdf'), ['SKILL.md', 'forms.md']);

      // Read again by an update, while it is there.
      write('skills/pdf/SKILL.md', _md('pdf', 'Does a thing.', 'Changed.'));
      expect((await Skills.update()).updated, ['pdf']);
      dir.deleteSync(recursive: true);
      dir.createSync();
      final gone = await Skills.update();
      expect(gone.updated, isEmpty);
      expect(gone.failed, isEmpty, reason: 'a folder that is gone is left alone');
    });

    test('from a .zip on this device', () async {
      final dir = Directory.systemTemp.createTempSync('zip');
      addTearDown(() => dir.deleteSync(recursive: true));
      final zip = File('${dir.path}/pdf.zip')
        ..writeAsBytesSync(
          ZipEncoder().encodeBytes(
            Archive()
              ..addFile(ArchiveFile.bytes('pdf/SKILL.md', utf8.encode(_md('pdf'))))
              ..addFile(ArchiveFile.bytes('pdf/a.md', utf8.encode('A'))),
          ),
        );
      await installAll(zip.path);
      expect(Skills.filesOf('pdf'), ['SKILL.md', 'a.md']);
    });

    test('an update goes on past a source it cannot reach', () async {
      served['/o/r/archive/HEAD.tar.gz'] = _targz({'SKILL.md': _md('a')});
      served['/o/s/archive/HEAD.tar.gz'] = _targz({'SKILL.md': _md('b')});
      await installAll('o/r');
      await installAll('o/s');
      served.remove('/o/r/archive/HEAD.tar.gz');
      served['/o/s/archive/HEAD.tar.gz'] = _targz({'SKILL.md': _md('b', 'Does a thing.', 'New.')});
      final res = await Skills.update();
      expect(res.updated, ['b']);
      expect(res.failed.keys, ['o/r']);
    });

    test("the app's own: kept current with the app, switched off rather than removed", () async {
      FoundSkill help(String body) => SkillDiscovery.find({'SKILL.md': _b(_md('app-help', 'Help.', body))}).single;
      await Skills.syncBuiltin([help('v1')]);
      final first = Skills.byDir('app-help')!;
      expect(first.builtin, isTrue);
      expect(() => Skills.remove('app-help'), throwsStateError);

      await Skills.syncBuiltin([help('v1')]);
      expect(Skills.byDir('app-help')!.updatedAt, first.updatedAt, reason: 'unchanged, not rewritten');

      Skills.setEnabled('app-help', false);
      await Skills.syncBuiltin([help('v2')]);
      expect(Skills.read('app-help'), contains('v2'));
      expect(Skills.byDir('app-help')!.enabled, isFalse);
      expect((await Skills.update()).failed, isEmpty, reason: 'never fetched');

      await Skills.syncBuiltin(const []);
      expect(Skills.byDir('app-help'), isNull);
    });

    test("one the user installed under the app's name stays theirs", () async {
      served['/SKILL.md'] = _b(_md('app-help', 'Mine.'));
      await installAll('$base/SKILL.md');
      await Skills.syncBuiltin(SkillDiscovery.find({'SKILL.md': _b(_md('app-help', 'Theirs.'))}));
      expect(Skills.byDir('app-help')!.description, 'Mine.');
      expect(Skills.byDir('app-help')!.builtin, isFalse);
    });

    test('removed, files and all', () async {
      served['/SKILL.md'] = _b(_md('gone'));
      await installAll('$base/SKILL.md');
      Skills.remove('gone');
      expect(Skills.all, isEmpty);
      expect(Directory('${root.path}/gone').existsSync(), isFalse);
    });

    test('the model is told of the ones on, and loads one', () async {
      served['/o/r/archive/HEAD.tar.gz'] = _targz({
        'skills/pdf/SKILL.md': _md('pdf', 'Fill PDF forms.', 'Read forms.md first.'),
        'skills/pdf/forms.md': 'Field by field.',
        'skills/off/SKILL.md': _md('off'),
      });
      await installAll('o/r');
      Skills.setEnabled('off', false);

      final prompt = Skills.prompt('skill')!;
      expect(prompt, contains('- pdf: Fill PDF forms.'));
      expect(prompt, isNot(contains('off')));

      String text(LlmToolResult r) => r.content.single['text'] as String;
      final ctx = ToolCtx('c', LlmCancelToken());
      final loaded = text(await TfSkill.instance.run({'name': 'pdf'}, ctx));
      expect(loaded, contains('Read forms.md first.'));
      expect(loaded, contains('- forms.md'));
      expect(text(await TfSkill.instance.run({'name': 'pdf', 'file': 'forms.md'}, ctx)), 'Field by field.');
      await expectLater(TfSkill.instance.run({'name': 'pdf', 'file': '../off/SKILL.md'}, ctx), throwsArgumentError);
      await expectLater(TfSkill.instance.run({'name': 'off'}, ctx), throwsArgumentError);
    });
  });
}
