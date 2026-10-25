import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fl_pi_llm/fl_pi_llm.dart';
import 'package:fl_pi_llm/legacy.dart';
import 'package:test/test.dart';

/// An OpenAI chat-completions server that streams. A request offering tools
/// gets a tool call first; one carrying a tool result, or none, gets text one
/// word per chunk. A summarisation request gets `SUMMARY`.
class MockServer {
  MockServer._(this._server, this.delay);

  static Future<MockServer> start({Duration delay = const Duration(milliseconds: 100)}) async =>
      MockServer._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0), delay).._serve();

  final HttpServer _server;
  final Duration delay;
  final requests = <Map<String, Object?>>[];
  final authHeaders = <String?>[];

  String get baseUrl => 'http://127.0.0.1:${_server.port}/v1';

  void _serve() {
    _server.listen((req) async {
      // An endpoint that sends its caller elsewhere.
      if (req.uri.path.startsWith('/moved/')) {
        authHeaders.add(req.headers.value('authorization'));
        req.response
          ..statusCode = HttpStatus.found
          ..headers.set(HttpHeaders.locationHeader, '$baseUrl/models');
        await req.response.close();
        return;
      }
      if (req.method == 'GET' && req.uri.path.endsWith('/models')) {
        authHeaders.add(req.headers.value('authorization'));
        req.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'data': [
              {'id': 'mock'},
              // A window smaller than the 1024-token output floor.
              {'id': 'mock-2', 'context_length': 512},
              // What the server was started with wins; a length that is no whole number is not one.
              {'id': 'mock-served', 'max_model_len': 2048, 'context_length': 512},
              {'id': 'mock-text', 'max_model_len': 2048.5, 'context_length': '4096'},
              {'id': 'text-embedding-3-small'},
            ],
          }));
        await req.response.close();
        return;
      }
      final body = jsonDecode(await utf8.decodeStream(req)) as Map<String, Object?>;
      requests.add(body);
      authHeaders.add(req.headers.value('authorization'));
      final msgs = (body['messages'] as List).cast<Map>();
      final hasTool = msgs.any((m) => m['role'] == 'tool');
      final isSummary = msgs.any((m) => jsonEncode(m['content']).contains('<conversation>'));
      final res = req.response
        ..statusCode = 200
        ..headers.contentType = ContentType('text', 'event-stream')
        ..bufferOutput = false;
      final base = {'id': 'c1', 'object': 'chat.completion.chunk', 'created': 1, 'model': body['model']};
      Future<void> send(Map<String, Object?> delta, [String? finish]) async {
        res.write('data: ${jsonEncode({
          ...base,
          'choices': [{'index': 0, 'delta': delta, 'finish_reason': finish}],
          if (finish != null) 'usage': {'prompt_tokens': 10, 'completion_tokens': 5, 'total_tokens': 15},
        })}\n\n');
        await res.flush();
      }

      if (isSummary) {
        await send({'role': 'assistant', 'content': 'SUMMARY'});
        await send({}, 'stop');
      } else if (!hasTool && body['tools'] != null) {
        await send({
          'role': 'assistant',
          'tool_calls': [
            {'index': 0, 'id': 'call_1', 'type': 'function', 'function': {'name': 'get_time', 'arguments': ''}},
          ],
        });
        await Future<void>.delayed(delay);
        await send({
          'tool_calls': [
            {'index': 0, 'function': {'arguments': '{"tz":"UTC"}'}},
          ],
        });
        await send({}, 'tool_calls');
      } else {
        for (final w in ['It ', 'is ', '12:00', '.']) {
          await send({'content': w});
          await Future<void>.delayed(delay);
        }
        await send({}, 'stop');
      }
      res.write('data: [DONE]\n\n');
      await res.close();
    });
  }

  Future<void> close() => _server.close(force: true);
}

/// Where `dart test` puts the library the build hook produced.
ExternalLibrary testLibrary() {
  final name = Platform.isMacOS
      ? 'libfl_pi_llm.dylib'
      : Platform.isWindows
      ? 'fl_pi_llm.dll'
      : 'libfl_pi_llm.so';
  return ExternalLibrary.open('.dart_tool/lib/$name');
}

const mock = LlmModelRef('mock', 'mock');

/// The mock server as the custom provider `mock`.
LlmCustomProvider mockProvider(MockServer s, {bool listed = false}) => LlmCustomProvider(
  id: 'mock',
  name: 'Mock',
  api: LlmApi.openaiCompletions,
  baseUrl: s.baseUrl,
  models: listed ? null : const ['mock'],
);

LlmTool timeTool(List<LlmToolCall> calls) => LlmTool(
  name: 'get_time',
  description: 'Get the time',
  parameters: {
    'type': 'object',
    'properties': {'tz': {'type': 'string'}},
  },
  execute: (call, _) async {
    calls.add(call);
    return LlmToolResult.text('12:00 ${call.args['tz']}');
  },
);

List<String> roles(List<LlmEntry> entries) =>
    [for (final e in entries) e.type == 'message' ? e.message!.role : e.type];

/// A directory of its own, deleted after the test file.
String tempDir() {
  final d = Directory.systemTemp.createTempSync('fl_pi_llm');
  addTearDown(() => d.deleteSync(recursive: true));
  return d.path;
}

/// Sessions from before pi-durable, as appended chunks by path.
final class MemoryLegacySessions implements LlmLegacySessions {
  MemoryLegacySessions(this.files);

  final Map<String, List<String>> files;

  @override
  Future<List<StoredFile>> list() async => [
    for (final MapEntry(:key, :value) in files.entries) StoredFile(key, value.join().length, DateTime.now()),
  ];

  @override
  Future<List<(int, String)>> read(String path, {required int after, required int maxChars}) async {
    final out = <(int, String)>[];
    var n = 0;
    final chunks = files[path] ?? const [];
    for (var seq = after + 1; seq < chunks.length; seq++) {
      if (out.isNotEmpty && n + chunks[seq].length > maxChars) break;
      n += chunks[seq].length;
      out.add((seq, chunks[seq]));
    }
    return out;
  }

  @override
  Future<void> remove(String path) async => files.remove(path);
}

/// What the tests' sessions are encrypted with.
final testKey = Uint8List.fromList(List.filled(32, 7));

void main() {
  late FlPiLlm llm;
  late MockServer server;
  late String dir;
  final credentials = MemoryCredentials({'mock': LlmCredential.apiKey('sk-test')});

  setUpAll(() async => llm = await FlPiLlm.start(
    key: testKey,
    directory: dir = Directory.systemTemp.createTempSync('fl_pi_llm').path,
    credentials: credentials,
    externalLibrary: testLibrary(),
  ));
  tearDownAll(() async {
    await llm.dispose();
    Directory(dir).deleteSync(recursive: true);
  });
  setUp(() async {
    server = await MockServer.start();
    await llm.setCustomProviders([mockProvider(server)]);
  });
  tearDown(() => server.close());

  test('info', () async {
    final info = await llm.info();
    expect(info['piDurable'], '1.1.0');
    expect(info['apis'], contains('anthropic-messages'));
  });

  test('streams, asks for approval, runs the tool, answers', () async {
    final calls = <LlmToolCall>[];
    final approvals = <LlmToolCall>[];
    final s = await llm.openSession(
      id: 'stream',
      model: mock,
      systemPrompt: 'test',
      tools: [timeTool(calls)],
      approve: (call) async {
        approvals.add(call);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return const LlmApproval.allow();
      },
    );
    final deltas = <(DateTime, String)>[];
    final types = <String>[];
    s.events.listen((e) {
      types.add(e.type);
      if (e.textDelta case final d?) deltas.add((DateTime.now(), d));
    });

    final r = await s.prompt('What time is it?');
    expect(r.status, 'completed');
    final entries = await s.entries();
    expect(roles(entries), ['user', 'assistant', 'toolResult', 'assistant']);
    expect(entries.last.message!.text, 'It is 12:00.');
    expect(approvals.single.name, 'get_time');
    expect(calls.single.args, {'tz': 'UTC'});
    // pi-durable commits a partial answer at most every 100 ms: deltas sent
    // closer together arrive as one.
    expect(deltas.map((d) => d.$2).join(), 'It is 12:00.');
    expect(deltas.length, greaterThanOrEqualTo(2));
    expect(
      deltas.last.$1.difference(deltas.first.$1),
      greaterThanOrEqualTo(const Duration(milliseconds: 150)),
      reason: 'the deltas should arrive as they are sent, not all at the end',
    );
    expect(types, containsAllInOrder(['run_start', 'tool_start', 'tool_end', 'run_end']));
    expect(server.authHeaders.first, 'Bearer sk-test');
    await s.close();
  });

  test('a session is stored, listed, reopened and deleted', () async {
    var s = await llm.openSession(id: 'kept', model: mock);
    await s.prompt('hi');
    await s.setName('Greeting');
    await s.close();

    expect((await llm.sessions()).map((i) => i.id), contains('kept'));
    s = await llm.openSession(id: 'kept', model: mock);
    expect(s.name, 'Greeting');
    expect(roles(await s.entries()), ['user', 'assistant']);
    await s.close();

    await llm.deleteSession('kept');
    expect((await llm.sessions()).map((i) => i.id), isNot(contains('kept')));
  });

  test('sessions are searched by what was said in them', () async {
    final s = await llm.openSession(id: 'searched', model: mock);
    await s.prompt('Where is the NEEDLE?');
    expect(await llm.searchSessions('needle'), contains('searched'));
    expect(await llm.searchSessions('12:00'), contains('searched'), reason: "the model's answer counts");
    expect(await llm.searchSessions('get_time'), isNot(contains('searched')), reason: 'a tool call is not text');
    await s.close();
    await llm.deleteSession('searched');
  });

  test("a built-in provider's key can come from the environment", () async {
    final rt = await FlPiLlm.start(
      key: testKey,
      directory: tempDir(),
      credentials: MemoryCredentials({'anthropic': LlmCredential.apiKey('sk-stored')}),
      environment: () => {'OPENAI_API_KEY': 'sk-env', 'ANTHROPIC_API_KEY': 'sk-env-too', 'GEMINI_API_KEY': ''},
    );
    addTearDown(rt.dispose);
    final sources = await rt.authSources();
    expect(sources['openai'], 'OPENAI_API_KEY');
    expect(sources['anthropic'], 'stored credential', reason: 'a stored key comes first');
    expect(sources, isNot(contains('google')), reason: 'an empty variable is no key');
    expect(await rt.availableModels(providerId: 'openai'), isNotEmpty);
  });

  test('with no environment, only stored keys count', () async {
    final rt = await FlPiLlm.start(key: testKey, directory: tempDir(), credentials: MemoryCredentials({}), environment: () => {});
    addTearDown(rt.dispose);
    expect(await rt.authSources(), isEmpty);
  });

  test('a session outlives the runtime', () async {
    final disk = tempDir();
    // A second runtime over its own directory, as after a relaunch.
    var rt = await FlPiLlm.start(key: testKey, directory: disk, credentials: credentials);
    await rt.setCustomProviders([mockProvider(server)]);
    var s = await rt.openSession(id: 'relaunch', model: mock);
    await s.prompt('remember me');
    await rt.dispose();

    rt = await FlPiLlm.start(key: testKey, directory: disk, credentials: credentials);
    await rt.setCustomProviders([mockProvider(server)]);
    s = await rt.openSession(id: 'relaunch', model: mock);
    final entries = await s.entries();
    expect(entries.first.message!.text, 'remember me');
    await rt.dispose();
  });

  // TODO: remove with package:fl_pi_llm/legacy.dart.
  test('a session from before pi-durable moves over, a few chunks at a time', () async {
    final log = File('rust/tests/fixtures/legacy-0.87.1.jsonl').readAsStringSync();
    const path = '/sessions/----/2026-10-12T13-14-14-726Z_chat-1.jsonl';
    final legacy = MemoryLegacySessions({
      path: [for (var i = 0; i < log.length; i += 97) log.substring(i, (i + 97).clamp(0, log.length))],
    });
    final rt = await FlPiLlm.start(key: testKey, directory: tempDir(), credentials: credentials)..legacySessions = legacy;
    addTearDown(rt.dispose);
    await rt.setCustomProviders([mockProvider(server)]);
    expect((await rt.sessions()).map((i) => i.id), ['chat-1'], reason: 'listed before it is moved');

    expect(await rt.migrateLegacy(), isEmpty);
    expect(legacy.files, isEmpty);
    final s = await rt.openSession(id: 'chat-1', model: mock);
    expect(s.name, 'Named');
    expect(roles(await s.entries()), ['user', 'assistant', 'toolResult', 'assistant', 'user', 'assistant', 'custom', 'compaction']);
    await s.close();
  });

  test('a session syncs to another device and back', () async {
    final a = await FlPiLlm.start(key: testKey, directory: tempDir(), credentials: credentials);
    final b = await FlPiLlm.start(key: Uint8List.fromList(List.filled(32, 8)), directory: tempDir(), credentials: credentials);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    for (final rt in [a, b]) {
      await rt.setCustomProviders([mockProvider(server)]);
    }
    Future<int> sync(FlPiLlm from, FlPiLlm to, {bool newHere = false}) async {
      var added = 0;
      int? after;
      do {
        final page = await from.exportSession('synced', after: after, maxChars: 1);
        after = page.next;
        final r = await to.importSession('synced', page.entries, tip: after == null && newHere ? page.tip : null);
        expect(r.orphans, isEmpty);
        added += r.added;
      } while (after != null);
      return added;
    }

    final sa = await a.openSession(id: 'synced', model: mock);
    await sa.prompt('from a');
    await sa.close();
    expect(await sync(a, b, newHere: true), 2);
    final sb = await b.openSession(id: 'synced', model: mock);
    await sb.prompt('from b');
    expect(await sync(b, a), 2);
    expect(await sync(a, b), 0, reason: 'settled');
    final again = await a.openSession(id: 'synced', model: mock);
    expect([for (final e in await again.entries()) e.message!.text], [for (final e in await sb.entries()) e.message!.text]);
    await again.close();
    await sb.close();
  });

  test('an answer that comes after dispose goes nowhere', () async {
    // A host call — here an approval — still waiting when the runtime is
    // disposed answered into an engine that was already freed.
    final rt = await FlPiLlm.start(key: testKey, directory: tempDir(), credentials: credentials);
    await rt.setCustomProviders([mockProvider(server)]);
    final asked = Completer<void>();
    final disposed = Completer<void>();
    final s = await rt.openSession(
      id: 'late-answer',
      model: mock,
      tools: [timeTool([])],
      approve: (_) async {
        asked.complete();
        await disposed.future;
        return const LlmApproval.allow();
      },
    );
    unawaited(s.prompt('What time is it?').then<void>((_) {}, onError: (_) {}));
    await asked.future;
    await rt.dispose();
    disposed.complete();
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });

  test('editing a message grows a branch and keeps the old one', () async {
    final s = await llm.openSession(id: 'branch', model: mock);
    await s.prompt('first');
    final original = (await s.entries()).first;
    await s.navigate(null);
    await s.prompt('edited');
    final entries = await s.entries();
    expect(entries.first.message!.text, 'edited');
    final tree = await s.tree();
    expect(tree.map((e) => e.id), contains(original.id));
    expect((await s.entry(original.id))!.message!.text, 'first');
    await s.close();
  });

  test('a branch is read in pages, its versions with it', () async {
    final s = await llm.openSession(id: 'pages', model: mock);
    for (final q in ['q0', 'q1', 'q2']) {
      await s.prompt(q);
    }
    final q2 = (await s.entries())[4];
    await s.navigate(q2.parentId);
    await s.prompt('q2 edited');

    final last = await s.page(limit: 2);
    expect(last.more, isTrue);
    expect([for (final e in last.entries) e.message!.role], ['user', 'assistant']);
    expect(last.entries.first.versions!.map((v) => v.message!.text), ['q2', 'q2 edited']);
    final earlier = await s.page(limit: 2, before: last.entries.first.id);
    expect(earlier.entries.first.message!.text, 'q1');
    expect(earlier.entries.first.versions, isNull);

    await s.switchTo(q2.id);
    expect((await s.entries()).map((e) => e.message!.text).skip(4).first, 'q2');
    expect((await s.page()).more, isFalse);
    await s.close();
  });

  test('appended messages and custom entries are part of the branch, not of the prompt', () async {
    final s = await llm.openSession(id: 'append', model: mock);
    await s.append([
      LlmMessage({'role': 'user', 'content': 'imported question', 'timestamp': 1}),
    ]);
    await s.appendCustom('image', {'url': 'https://example.com/a.png'});
    await s.prompt('next');
    final entries = await s.entries();
    expect(roles(entries), ['user', 'custom', 'user', 'assistant']);
    expect(entries[1].customType, 'image');
    final sent = jsonEncode(server.requests.last);
    expect(sent, contains('imported question'));
    expect(sent, isNot(contains('example.com')));
    await s.close();
  });

  test('a denied tool call does not run', () async {
    final calls = <LlmToolCall>[];
    final s = await llm.openSession(
      id: 'deny',
      model: mock,
      tools: [timeTool(calls)],
      approve: (_) async => const LlmApproval.deny('not now'),
    );
    await s.prompt('time?');
    expect(calls, isEmpty);
    final result = (await s.entries()).firstWhere((e) => e.message?.role == 'toolResult');
    expect(result.message!.text, contains('not now'));
    await s.close();
  });

  test('abort ends a running prompt', () async {
    await server.close();
    server = await MockServer.start(delay: const Duration(milliseconds: 400));
    await llm.setCustomProviders([mockProvider(server)]);
    final s = await llm.openSession(id: 'abort', model: mock);
    final sw = Stopwatch()..start();
    unawaited(Future<void>.delayed(const Duration(milliseconds: 500), s.abort));
    final r = await s.prompt('hi');
    expect(r.status, 'aborted');
    expect(sw.elapsed, lessThan(const Duration(milliseconds: 1500)));
    await s.close();
  });

  test('compaction summarises for the model and keeps the originals', () async {
    final s = await llm.openSession(
      id: 'compact',
      model: mock,
      compaction: const CompactionSettings(keepRecentTokens: 1),
    );
    final long = List.filled(200, 'word').join(' ');
    for (var i = 0; i < 3; i++) {
      await s.prompt('turn$i $long');
    }
    final first = (await s.entries()).first;
    await s.compact();
    final c = (await s.entries()).firstWhere((e) => e.type == 'compaction');
    expect(c.summary, startsWith('SUMMARY'));
    expect((await s.entry(first.id))!.message!.text, startsWith('turn0'));

    await s.prompt('next');
    final last = jsonEncode(server.requests.last);
    expect(last, contains('SUMMARY'));
    await s.setSystemPrompt('NEW PROMPT');
    await s.prompt('again');
    expect(jsonEncode(server.requests.last), contains('NEW PROMPT'));
    expect(last, isNot(contains('turn0')));
    await s.close();
  });

  test('one-shot completion streams', () async {
    final events = <LlmEvent>[];
    final m = await llm.complete(
      model: mock,
      messages: [LlmMessage({'role': 'user', 'content': 'hi', 'timestamp': 1})],
      onEvent: events.add,
    );
    expect(m.text, 'It is 12:00.');
    expect(events.where((e) => e.type == 'text_delta'), hasLength(4));
  });

  test('an unreachable endpoint fails the run, not the runtime', () async {
    await llm.setCustomProviders([
      const LlmCustomProvider(id: 'down', name: 'Down', api: LlmApi.openaiCompletions, baseUrl: 'http://127.0.0.1:9/v1', models: ['x']),
    ]);
    final s = await llm.openSession(id: 'down', model: const LlmModelRef('down', 'x'));
    final r = await s.prompt('hi').timeout(const Duration(seconds: 60));
    expect(r.completed, isFalse);
    await s.close();
    expect(await llm.info(), isNotEmpty);
  });

  test('an unknown model rejects', () async {
    expect(
      () => llm.openSession(id: 'bad', model: const LlmModelRef('nope', 'nope')),
      throwsA(isA<LlmException>()),
    );
  });

  test("the catalog is pi-ai's, with custom providers listed from their endpoint", () async {
    await llm.setCustomProviders([mockProvider(server, listed: true)]);
    final errors = await llm.refreshModels(providers: ['mock'], force: true);
    expect(errors, isEmpty);
    final providers = await llm.providers();
    final ids = providers.map((p) => p.id);
    expect(ids, containsAll(['openai', 'anthropic', 'google', 'openrouter', 'deepseek']));
    final m = providers.firstWhere((p) => p.id == 'mock');
    expect(m.custom, isTrue);
    expect(m.models.map((e) => e.id), ['mock', 'mock-2', 'mock-served', 'mock-text'], reason: 'embeddings cannot chat');
    final tiny = m.models[1];
    expect(tiny.contextWindow, 512);
    expect(tiny.maxTokens, 128, reason: 'a quarter of the window, never past it');
    expect((m.models[2].contextWindow, m.models[2].maxTokens), (2048, 512));
    expect((m.models[3].contextWindow, m.models[3].maxTokens), (128000, 16384));
    expect(server.authHeaders.last, 'Bearer sk-test');
    final available = await llm.availableModels();
    expect(available.map((e) => e.provider).toSet(), {'mock'});
    final openai = providers.firstWhere((p) => p.id == 'openai');
    expect(openai.models.every((e) => e.contextWindow > 0), isTrue);
    final flash = providers.firstWhere((p) => p.id == 'deepseek').models.firstWhere((e) => e.id == 'deepseek-flash');
    expect(flash.thinkingLevels, [ThinkingLevel.off, ThinkingLevel.low, ThinkingLevel.high, ThinkingLevel.max]);
  });

  test('an OpenAI-compatible endpoint lists its models beside the typed ones', () async {
    await llm.setCustomProviders([
      LlmCustomProvider(id: 'mock', name: 'Mock', api: LlmApi.openaiCompletions, baseUrl: server.baseUrl, models: const ['extra']),
    ]);
    expect(await llm.refreshModels(providers: ['mock']), isEmpty);
    final m = (await llm.providers()).firstWhere((p) => p.id == 'mock');
    expect(m.models.map((e) => e.id), ['extra', 'mock', 'mock-2', 'mock-served', 'mock-text']);
  });

  test('other APIs keep to the typed models', () async {
    final before = server.authHeaders.length;
    await llm.setCustomProviders([
      LlmCustomProvider(id: 'mock', name: 'Mock', api: LlmApi.anthropicMessages, baseUrl: server.baseUrl, models: const ['claude-x']),
    ]);
    expect(await llm.refreshModels(providers: ['mock']), isEmpty);
    final m = (await llm.providers()).firstWhere((p) => p.id == 'mock');
    expect(m.models.map((e) => e.id), ['claude-x']);
    expect(server.authHeaders.length, before, reason: 'nothing was fetched');
  });

  test("a changed endpoint does not reuse the old endpoint's list", () async {
    await llm.setCustomProviders([mockProvider(server, listed: true)]);
    expect(await llm.refreshModels(providers: ['mock']), isEmpty);
    final dead = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = dead.port;
    await dead.close();
    await llm.setCustomProviders([
      LlmCustomProvider(id: 'mock', name: 'Mock', api: LlmApi.openaiCompletions, baseUrl: 'http://127.0.0.1:$port/v1'),
    ]);
    expect(await llm.refreshModels(providers: ['mock']), contains('mock'));
    final m = (await llm.providers()).firstWhere((p) => p.id == 'mock');
    expect(m.models, isEmpty);
  });

  test('an endpoint being set up lists its models without being registered', () async {
    final probe = LlmCustomProvider(id: 'new', name: 'New', api: LlmApi.openaiResponses, baseUrl: server.baseUrl);
    final listed = await llm.listModels(probe, credential: LlmCredential.apiKey('sk-probe'));
    expect(listed.map((e) => e.id), ['mock', 'mock-2', 'mock-served', 'mock-text']);
    expect(server.authHeaders.last, 'Bearer sk-probe');
    expect((await llm.providers()).map((p) => p.id), isNot(contains('new')));
    await expectLater(
      llm.listModels(LlmCustomProvider(id: 'a', name: 'A', api: LlmApi.anthropicMessages, baseUrl: server.baseUrl)),
      throwsA(isA<LlmException>()),
    );
  });

  // The address the fetch policy judged is the only one a request goes to:
  // a redirect is not followed on to somewhere it never saw.
  test('a redirect is not followed', () async {
    final moved = LlmCustomProvider(
      id: 'moved',
      name: 'Moved',
      api: LlmApi.openaiCompletions,
      baseUrl: server.baseUrl.replaceFirst('/v1', '/moved'),
    );
    final before = server.authHeaders.length;
    await expectLater(llm.listModels(moved, credential: LlmCredential.apiKey('sk-moved')), throwsA(isA<LlmException>()));
    expect(server.authHeaders.sublist(before), ['Bearer sk-moved'], reason: 'asked once, at the address given');
  });
}
