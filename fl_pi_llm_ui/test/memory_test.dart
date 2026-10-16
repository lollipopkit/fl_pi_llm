import 'package:fl_lib/fl_lib.dart';
import 'package:fl_pi_llm_ui/fl_pi_llm_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'library.dart';

void main() {
  late MemoryStore mem;

  setUpAll(loadLlmLibrary);

  setUp(() {
    SqliteDb.openInMemory();
    mem = LlmStores.memory;
  });
  tearDown(() => SqliteDb.close());

  Future<String> run(ToolFunc t, Map<String, Object?> args) async {
    final r = await t.run(args, ToolCtx('test', LlmCancelToken()));
    return r.content.map((e) => e['text'] ?? '').join();
  }

  group('paths', () {
    test('are relative to /memories, however written', () {
      expect(MemoryStore.keyOf('/memories/a/b.md'), 'a/b.md');
      expect(MemoryStore.keyOf('/a.md'), 'a.md');
      expect(MemoryStore.keyOf('a//b.md/'), 'a/b.md');
      expect(MemoryStore.keyOf('/memories'), '');
    });

    test('never leave it, nor reach the store bookkeeping', () {
      for (final p in ['../x', '/memories/../x', 'a/./b', r'a\b', '__lkpt_lastUpdateTs', 'a/_x', 'a\u202Eb']) {
        expect(() => MemoryStore.keyOf(p), throwsA(isA<MemoryError>()), reason: p);
      }
    });

    test('a file and a directory cannot share a name', () {
      mem.write('a', 'x');
      expect(() => mem.write('a/b', 'y'), throwsA(isA<MemoryError>()));
      mem.write('d/e', 'x');
      expect(() => mem.write('d', 'y'), throwsA(isA<MemoryError>()));
    });
  });

  group('tools', () {
    test('take their description and arguments from fl_pi_llm', () {
      expect(TfMemory.all.map((t) => t.name), LlmMemory.tools.map((t) => t.name));
      expect(TfMemoryWrite.instance.llmTool.parameters['required'], ['path', 'content']);
      expect(TfMemory.all.every((t) => t.trusted), isTrue);
    });

    test('write, view with line numbers and a range', () async {
      await run(TfMemoryWrite.instance, {'path': '/memories/u.md', 'content': 'a\nb\nc'});
      expect(await run(TfMemoryView.instance, {'path': '/memories/u.md'}), contains('     2\tb'));
      final part = await run(TfMemoryView.instance, {
        'path': 'u.md',
        'view_range': [2, -1],
      });
      expect(part, isNot(contains('\ta')));
      expect(part, contains('     3\tc'));
      expect(await run(TfMemoryView.instance, {}), contains('/memories/u.md'));
    });

    test('edit replaces one occurrence, or all when asked', () async {
      mem.write('u.md', 'x y x');
      await expectLater(run(TfMemoryEdit.instance, {'path': 'u.md', 'old_str': 'x', 'new_str': 'z'}), throwsA(isA<MemoryError>()));
      await run(TfMemoryEdit.instance, {'path': 'u.md', 'old_str': 'y', 'new_str': 'w'});
      await run(TfMemoryEdit.instance, {'path': 'u.md', 'old_str': 'x', 'new_str': 'z', 'replace_all': true});
      expect(mem.read('u.md'), 'z w z');
    });

    test('move and delete files and directories', () async {
      mem.write('d/a.md', '1');
      mem.write('d/b.md', '2');
      await run(TfMemoryMove.instance, {'from': 'd', 'to': 'e'});
      expect(mem.files().keys, ['e/a.md', 'e/b.md']);
      await expectLater(run(TfMemoryDelete.instance, {'path': '/memories'}), throwsA(isA<MemoryError>()));
      expect(mem.delete('absent'), 0);
      await run(TfMemoryDelete.instance, {'path': 'e'});
      expect(mem.files(), isEmpty);
    });
  });

  test('the prompt lists the files and holds the index', () {
    expect(TfMemory.prompt(tools: false), isNull);
    mem.write(MemoryStore.index, '- [User](user.md) — who');
    mem.write('user.md', 'x');
    final p = TfMemory.prompt(tools: true)!;
    expect(p, contains('persistent memory'));
    expect(p, contains('- /memories/user.md (1 chars'));
    expect(p, contains('<memory_index>\n- [User](user.md) — who\n</memory_index>'));
  });
}
