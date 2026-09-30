import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart' show ExternalLibrary;
import 'package:meta/meta.dart';

import 'event.dart';
import 'model.dart';
import 'rust/api.dart';
import 'rust/frb_generated.dart';
import 'credentials.dart';
import 'store.dart';
import 'tool.dart';

/// Where the runtime's own log lines go. `level` is `debug`, `info`, `warn`
/// or `error`.
typedef LlmLogger = void Function(String level, String message);

/// The LLM runtime: pi-agent-core and pi-ai running in QuickJS, with the
/// network, the tools and the approvals on this side.
///
/// One per app is enough — sessions are cheap and share it. HTTP goes through
/// [HttpClient], so the platform's proxy and certificate settings apply.
/// Sessions are kept in the [PiSessionStore] the runtime is started with.
final class FlPiLlm {
  FlPiLlm._(this._http, this._log, this._store, this._credentials, this._environment);

  static Future<void>? _libInit;

  /// Starts a runtime.
  ///
  /// [httpClient] is used for every request the models make; one is created
  /// when omitted and closed by [dispose].
  ///
  /// [externalLibrary] is the native library, for where the platform's own
  /// loading does not find it — `dart test` puts it in `.dart_tool/lib/`. Only
  /// the first call's value counts.
  static Future<FlPiLlm> start({
    required PiSessionStore store,
    required LlmCredentials credentials,
    HttpClient? httpClient,
    LlmLogger? logger,
    ExternalLibrary? externalLibrary,
    Map<String, String> Function()? environment,
  }) async {
    await (_libInit ??= RustLib.init(externalLibrary: externalLibrary));
    final rt = FlPiLlm._(
      httpClient ?? HttpClient(),
      logger,
      store,
      credentials,
      environment ?? () => Platform.environment,
    );
    rt._ownsHttp = httpClient == null;
    rt._start();
    return rt;
  }

  final HttpClient _http;
  final LlmLogger? _log;
  final PiSessionStore _store;
  final LlmCredentials _credentials;

  /// Where a provider without a stored credential finds its key, as pi-ai
  /// does under Node: `OPENAI_API_KEY` and the like. The app's own
  /// environment by default, which on a desktop is what it was started with.
  final Map<String, String> Function() _environment;
  bool _ownsHttp = false;

  late final LlmEngine _engine;
  StreamSubscription<HostMessage>? _sub;
  var _nextReq = 1;
  var _nextStream = 1;
  final _pending = <int, Completer<Object?>>{};
  final _sessions = <String, LlmSession>{};
  final _completions = <int, void Function(LlmEvent)>{};
  final _requests = <int, HttpClientRequest>{};
  final _bodies = <int, StreamSubscription<List<int>>>{};
  final _toolCancels = <String, LlmCancelToken>{};
  String? _fatal;

  void _start() {
    _engine = LlmEngine();
    _sub = _engine.start().listen(_onMessage, onError: (Object e) => _die('$e'));
  }

  /// Versions of what is running, and the APIs it can speak.
  Future<Map<String, Object?>> info() async =>
      (await _request('runtime.info', const {}) as Map).cast<String, Object?>();

  /// Every provider and its models: pi-ai's catalog, then the custom ones.
  Future<List<LlmProviderInfo>> providers() async => [
    for (final p in await _request('providers.list', const {}) as List)
      LlmProviderInfo((p as Map).cast<String, Object?>()),
  ];

  /// Models whose provider has a usable credential — of one provider, or all.
  Future<List<LlmModelInfo>> availableModels({String? providerId}) async => [
    for (final m in await _request('providers.available', {'providerId': ?providerId}) as List)
      LlmModelInfo((m as Map).cast<String, Object?>()),
  ];

  /// The models [provider]'s endpoint lists, fetched with [credential]
  /// without registering it — while the user is still setting it up. Only
  /// for an API that [LlmApi.listsModels].
  Future<List<LlmModelInfo>> listModels(LlmCustomProvider provider, {LlmCredential? credential}) async {
    // The probe goes to an endpoint that is not registered yet, on the terms
    // it is being set up with.
    final origin = provider.allowInsecure ? _originOf(provider.baseUrl) : null;
    final added = origin != null && _probeOrigins.add(origin);
    try {
      return [
        for (final m in await _request('providers.probe', {
          'provider': provider.toJson(),
          'credential': ?credential?.json,
        }) as List)
          LlmModelInfo((m as Map).cast<String, Object?>()),
      ];
    } finally {
      if (added) _probeOrigins.remove(origin);
    }
  }

  /// Replaces the user's custom providers.
  Future<void> setCustomProviders(List<LlmCustomProvider> providers) {
    _insecureOrigins
      ..clear()
      ..addAll([
        for (final p in providers)
          if (p.allowInsecure) ?_originOf(p.baseUrl),
      ]);
    return _request('providers.setCustom', {'providers': [for (final p in providers) p.toJson()]});
  }

  /// The origins of custom providers allowed plain `http` off this device,
  /// and of one being probed with that allowance.
  final _insecureOrigins = <String>{};
  final _probeOrigins = <String>{};

  static String? _originOf(String url) {
    final u = Uri.tryParse(url);
    return u == null || u.host.isEmpty ? null : u.origin;
  }

  /// Whether a request to [uri] may go out: `https` anywhere, `http` only to
  /// this device or to an origin in [insecureOrigins], and nothing else.
  ///
  /// Every request pi makes carries or may carry an API key, and plain `http`
  /// off the device hands it to anyone on the path. A provider on the local
  /// network that speaks nothing else has to be let through by name —
  /// [LlmCustomProvider.allowInsecure]. Public for a settings page to know
  /// before saving whether an address needs that.
  static bool fetchAllowed(Uri uri, Set<String> insecureOrigins) {
    if (uri.isScheme('https')) return true;
    if (!uri.isScheme('http')) return false;
    final host = uri.host.toLowerCase();
    if (host == 'localhost' || host == '::1' || host == '[::1]') return true;
    if (InternetAddress.tryParse(host)?.isLoopback ?? false) return true;
    return insecureOrigins.contains(uri.origin);
  }

  /// Where each provider with usable auth gets it, by provider id: `stored
  /// credential`, or the environment variable its key came from.
  Future<Map<String, String>> authSources() async =>
      ((await _request('providers.auth', const {})) as Map).cast<String, String>();

  /// Lists the models of dynamic providers again, over the network. Returns
  /// the error of each provider that failed.
  Future<Map<String, String>> refreshModels({List<String>? providers, bool force = false}) async {
    final v = await _request('providers.refresh', {'providers': ?providers, 'force': force}) as Map;
    return ((v['errors'] as Map?) ?? const {}).cast<String, String>();
  }

  /// Every stored session, newest first.
  Future<List<LlmSessionInfo>> sessions() async {
    final v = await _request('sessions.list', const {}) as List;
    return [for (final m in v) LlmSessionInfo.fromJson((m as Map).cast<String, Object?>())];
  }

  /// Deletes a stored session. Close it first.
  Future<void> deleteSession(String id) => _request('sessions.delete', {'sessionId': id});

  /// Opens the session [id], creating it when there is none.
  ///
  /// [model], [tools] and the rest are what the session runs with from now on;
  /// a reopened session keeps its history, not its settings. [approve] is
  /// asked before every tool call — the run waits for the answer — and without
  /// it tools run unasked.
  Future<LlmSession> openSession({
    required String id,
    required LlmModelRef model,
    String systemPrompt = '',
    List<LlmTool> tools = const [],
    ThinkingLevel thinkingLevel = ThinkingLevel.off,
    CompactionSettings compaction = const CompactionSettings(),
    LlmApprover? approve,
  }) async {
    if (_sessions.containsKey(id)) throw LlmException('Session is already open: $id');
    final s = LlmSession._(this, id, tools, approve);
    _sessions[id] = s;
    try {
      final v = await _request('session.open', {
        'sessionId': id,
        'model': model.toJson(),
        'systemPrompt': systemPrompt,
        'tools': [for (final t in tools) t.toJson()],
        'thinkingLevel': thinkingLevel.name,
        'compaction': compaction.toJson(),
        'approval': approve != null,
      }) as Map;
      s._interrupted = (v['interrupted'] as List).isNotEmpty;
      s.name = v['name'] as String?;
    } catch (_) {
      _sessions.remove(id);
      await s._events.close();
      rethrow;
    }
    return s;
  }

  /// One completion, outside any session: a chat title, a translation.
  ///
  /// [onEvent] receives pi's `AssistantMessageEvent`s as they stream.
  Future<LlmMessage> complete({
    required LlmModelRef model,
    required List<LlmMessage> messages,
    String? systemPrompt,
    void Function(LlmEvent event)? onEvent,
    Map<String, Object?>? options,
  }) async {
    final streamId = onEvent == null ? null : _nextStream++;
    if (streamId != null) _completions[streamId] = onEvent!;
    try {
      final v = await _request('complete', {
        'model': model.toJson(),
        'messages': [for (final m in messages) m.json],
        'systemPrompt': ?systemPrompt,
        'streamId': ?streamId,
        'options': ?options,
      });
      return LlmMessage((v as Map).cast<String, Object?>());
    } finally {
      if (streamId != null) _completions.remove(streamId);
    }
  }

  /// Stops the runtime. Every session ends with it.
  Future<void> dispose() async {
    for (final r in _requests.values) {
      r.abort();
    }
    for (final b in _bodies.values) {
      await b.cancel();
    }
    _fail(const LlmException('Runtime disposed'));
    for (final s in [..._sessions.values]) {
      await s._events.close();
    }
    _sessions.clear();
    // The engine first: stopping it ends the stream from the Rust side. Not
    // awaited, because cancelling that stream while the engine still holds
    // its sink never completes.
    _engine.dispose();
    unawaited(_sub?.cancel());
    if (_ownsHttp) _http.close(force: true);
  }

  // -------------------------------------------------------------------------

  Future<Object?> _request(String method, Map<String, Object?> payload) {
    final fatal = _fatal;
    if (fatal != null) return Future.error(LlmException(fatal));
    final id = _nextReq++;
    final c = Completer<Object?>();
    _pending[id] = c;
    if (!_engine.request(reqId: id, method: method, payload: jsonEncode(payload))) {
      _pending.remove(id);
      return Future.error(const LlmException('Runtime stopped'));
    }
    return c.future;
  }

  void _onMessage(HostMessage m) {
    switch (m.kind) {
      case HostMessageKind.result:
        final c = _pending.remove(m.id);
        if (c == null) return;
        final r = jsonDecode(m.payload) as Map<String, Object?>;
        if (r['ok'] == true) {
          c.complete(r['value']);
        } else {
          c.completeError(LlmException(r['error'] as String? ?? 'Unknown error'));
        }
      case HostMessageKind.hostCall:
        unawaited(_onHostCall(m.id, m.name, m.payload, m.body));
      case HostMessageKind.notify:
        _onNotify(m.name, jsonDecode(m.payload) as Map<String, Object?>);
      case HostMessageKind.event:
        _onEvent(jsonDecode(m.payload) as Map<String, Object?>);
      case HostMessageKind.log:
        _log?.call(m.name, m.payload);
      case HostMessageKind.fatal:
        _die(m.payload);
    }
  }

  void _die(String message) {
    _fatal = message;
    _log?.call('error', 'fl_pi_llm runtime stopped: $message');
    _fail(LlmException(message));
  }

  void _fail(LlmException e) {
    final pending = [..._pending.values];
    _pending.clear();
    for (final c in pending) {
      c.completeError(e);
    }
  }

  void _onEvent(Map<String, Object?> e) {
    switch (e['type']) {
      case 'session.event':
        _sessions[e['sessionId']]?._emit(
          LlmEvent.fromJson((e['event'] as Map).cast<String, Object?>()),
        );
      case 'complete.event':
        _completions[e['streamId']]?.call(
          LlmEvent.fromJson((e['event'] as Map).cast<String, Object?>()),
        );
    }
  }

  void _onNotify(String name, Map<String, Object?> p) {
    switch (name) {
      case 'fetch.cancel':
        final id = p['streamId'] as int;
        _requests.remove(id)?.abort();
        final body = _bodies.remove(id);
        if (body != null) {
          unawaited(body.cancel());
          // The body will never end on its own now, and a `read` may be
          // waiting on it.
          _engine.endBody(streamId: id, error: 'aborted');
        }
      case 'tool.cancel':
        _toolCancels.remove('${p['sessionId']}/${p['toolCallId']}')?.cancel();
    }
  }

  Future<void> _onHostCall(int callId, String name, String payload, Uint8List? body) async {
    try {
      final p = jsonDecode(payload) as Map<String, Object?>;
      switch (name) {
        case 'fetch':
          await _fetch(callId, p, body);
        case 'tool':
          _answer(callId, await _runTool(p));
        case 'approve':
          _answer(callId, await _approve(p));
        case final fs when fs.startsWith('fs.'):
          _answer(callId, await _fs(fs, p));
        case final auth when auth.startsWith('auth.'):
          _answer(callId, await _auth(auth, p));
        case 'env.get':
          final v = _environment()[p['name'] as String? ?? ''];
          _answer(callId, v == null || v.isEmpty ? null : v);
        default:
          _answerError(callId, 'Unknown host call: $name');
      }
    } catch (e) {
      _answerError(callId, '$e');
    }
  }

  void _answer(int callId, Object? value) =>
      _engine.answer(callId: callId, payload: jsonEncode(value));

  void _answerError(int callId, String error) =>
      _engine.answer(callId: callId, payload: '', error: error);

  /// Headers that describe the body as it came off the wire. [HttpClient]
  /// hands over the decompressed body, so these would describe something else.
  static const _hopHeaders = {'content-length', 'content-encoding', 'transfer-encoding'};

  Future<void> _fetch(int callId, Map<String, Object?> p, Uint8List? body) async {
    final uri = Uri.parse(p['url'] as String);
    if (!fetchAllowed(uri, {..._insecureOrigins, ..._probeOrigins})) {
      _answerError(callId, 'fetch refused: $uri is plain http off this device; allow it on its provider');
      return;
    }
    final HttpClientRequest req;
    try {
      req = await _http.openUrl(p['method'] as String, uri);
    } catch (e) {
      _answerError(callId, 'fetch failed: $e');
      return;
    }
    _requests[callId] = req;
    try {
      final headers = (p['headers'] as Map?)?.cast<String, Object?>() ?? const {};
      for (final MapEntry(:key, :value) in headers.entries) {
        if (key == 'host' || key == 'content-length') continue;
        req.headers.set(key, '$value', preserveHeaderCase: true);
      }
      if (body != null) {
        req.contentLength = body.length;
        req.add(body);
      }
      final res = await req.close();
      if (!_requests.containsKey(callId)) {
        // Cancelled while connecting.
        await res.drain<void>();
        return;
      }
      final h = <String, String>{};
      res.headers.forEach((k, v) {
        if (!_hopHeaders.contains(k)) h[k] = v.join(', ');
      });
      _answer(callId, {
        'status': res.statusCode,
        'statusText': res.reasonPhrase,
        'headers': h,
        'streamId': callId,
      });
      _bodies[callId] = res.listen(
        (chunk) => _engine.pushBody(streamId: callId, chunk: chunk),
        onDone: () {
          _requests.remove(callId);
          _bodies.remove(callId);
          _engine.endBody(streamId: callId);
        },
        onError: (Object e) {
          _requests.remove(callId);
          _bodies.remove(callId);
          _engine.endBody(streamId: callId, error: '$e');
        },
        cancelOnError: true,
      );
    } catch (e) {
      _requests.remove(callId);
      _answerError(callId, 'fetch failed: $e');
    }
  }

  Future<Object?> _auth(String op, Map<String, Object?> p) async {
    final id = p['providerId'] as String?;
    switch (op) {
      case 'auth.read':
        return (await _credentials.read(id!))?.json;
      case 'auth.list':
        return [
          for (final pid in await _credentials.list()) {'providerId': pid, 'type': 'api_key'},
        ];
      case 'auth.write':
        await _credentials.write(id!, LlmCredential((p['credential'] as Map).cast<String, Object?>()));
      case 'auth.delete':
        await _credentials.delete(id!);
      default:
        throw LlmException('Unknown auth call: $op');
    }
    return null;
  }

  Future<Object?> _fs(String op, Map<String, Object?> p) async {
    final path = p['path'] as String?;
    switch (op) {
      case 'fs.read':
        return {'text': await _store.read(path!, maxLines: p['maxLines'] as int?)};
      case 'fs.write':
        await _store.write(path!, p['text'] as String);
      case 'fs.append':
        await _store.append(path!, p['text'] as String);
      case 'fs.rename':
        await _store.rename(p['from'] as String, p['to'] as String);
      case 'fs.remove':
        await _store.remove(path!, recursive: p['recursive'] == true);
      case 'fs.stat':
        final f = await _store.stat(path!);
        return f == null ? null : {'size': f.size, 'mtimeMs': f.modified.millisecondsSinceEpoch};
      case 'fs.list':
        return {'files': [for (final f in await _store.list(p['dir'] as String)) f.toJson()]};
      default:
        throw LlmException('Unknown store call: $op');
    }
    return null;
  }

  Future<Map<String, Object?>> _runTool(Map<String, Object?> p) async {
    final session = _sessions[p['sessionId']];
    final name = p['name'] as String;
    final tool = session?._tools[name];
    if (session == null || tool == null) return {'error': 'Unknown tool: $name'};
    final key = '${session.id}/${p['toolCallId']}';
    final cancel = LlmCancelToken();
    _toolCancels[key] = cancel;
    try {
      final res = await tool.execute(
        LlmToolCall(
          sessionId: session.id,
          id: p['toolCallId'] as String,
          name: name,
          args: (p['args'] as Map?)?.cast<String, Object?>() ?? const {},
        ),
        cancel,
      );
      return res.toJson();
    } catch (e) {
      return {'error': '$e'};
    } finally {
      _toolCancels.remove(key);
    }
  }

  Future<Map<String, Object?>> _approve(Map<String, Object?> p) async {
    final session = _sessions[p['sessionId']];
    final approve = session?._approve;
    if (approve == null) return {'block': false};
    final a = await approve(
      LlmToolCall(
        sessionId: session!.id,
        id: p['toolCallId'] as String,
        name: p['name'] as String,
        args: (p['args'] as Map?)?.cast<String, Object?>() ?? const {},
      ),
    );
    return {'block': !a.allowed, 'reason': ?a.reason};
  }
}

/// One conversation: a pi session, open in the runtime.
final class LlmSession {
  LlmSession._(this._rt, this.id, List<LlmTool> tools, this._approve)
    : _tools = {for (final t in tools) t.name: t};

  final FlPiLlm _rt;
  final String id;
  Map<String, LlmTool> _tools;
  LlmApprover? _approve;
  final _events = StreamController<LlmEvent>.broadcast();
  var _closed = false;
  var _interrupted = false;

  /// The session's name, if it has been given one.
  String? name;

  /// Whether a previous launch left a run unfinished. [resume] picks it up.
  bool get interrupted => _interrupted;

  /// Everything that happens in this session, as it happens.
  Stream<LlmEvent> get events => _events.stream;

  void _emit(LlmEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  /// Sends [text] and runs until the agent is done, tools included. Watch
  /// [events] for the tokens as they arrive; read [entries] for the result.
  ///
  /// [images] are pi `ImageContent` parts — see [LlmContent.image].
  Future<LlmRunResult> prompt(String text, {List<Map<String, Object?>>? images}) async =>
      _result(await _call('session.prompt', {'text': text, 'images': ?images}));

  /// Continues an interrupted run, or retries after an error.
  Future<LlmRunResult> resume() async {
    _interrupted = false;
    return _result(await _call('session.resume', {}));
  }

  /// Stops the current run. [prompt] then returns `aborted`.
  Future<void> abort() => _call('session.abort', {});

  /// The current branch, root first.
  Future<List<LlmEntry>> entries() async => _entries(await _call('session.entries', {}));

  /// Every entry in the session, on every branch.
  Future<List<LlmEntry>> tree() async => _entries(await _call('session.tree', {}));

  /// One entry by id, on any branch — including what a compaction summarised.
  Future<LlmEntry?> entry(String id) async {
    final v = (await _call('session.entry', {'entryId': id}) as Map)['entry'];
    return v == null ? null : LlmEntry((v as Map).cast<String, Object?>());
  }

  /// Moves the branch tip to [targetId] — `null` for before the first entry —
  /// and returns the new branch. The next [prompt] grows a new branch from
  /// there; the old one stays in the [tree]. This is how a message is edited
  /// (navigate to its parent, prompt the new text) or an answer regenerated.
  ///
  /// With [summarize], what is left behind is summarised into the new branch.
  Future<List<LlmEntry>> navigate(String? targetId, {bool summarize = false}) async =>
      _entries(await _call('session.navigate', {
        'targetId': targetId,
        if (summarize) 'options': {'summarize': true},
      }));

  /// Appends [messages] to the branch without running the model — an import,
  /// or a result the app produced itself. Returns their entry ids.
  Future<List<String>> append(List<LlmMessage> messages) async {
    final v = await _call('session.append', {'messages': [for (final m in messages) m.json]}) as Map;
    return (v['ids'] as List).cast<String>();
  }

  /// Appends an entry of the app's own [customType]: something to show,
  /// which the model never sees. Returns its id.
  Future<String> appendCustom(String customType, Object? data) async {
    final v = await _call('session.appendCustom', {'customType': customType, 'data': data}) as Map;
    return v['id'] as String;
  }

  /// Compacts now, whatever the thresholds say. Returns the new branch.
  Future<List<LlmEntry>> compact({String? instructions}) async =>
      _entries(await _call('session.compact', {'customInstructions': ?instructions}));

  Future<void> setModel(LlmModelRef model) => _call('session.setModel', {'model': model.toJson()});

  /// Takes effect from the next request.
  Future<void> setSystemPrompt(String prompt) =>
      _call('session.setSystemPrompt', {'systemPrompt': prompt});

  Future<void> setThinkingLevel(ThinkingLevel level) =>
      _call('session.setThinkingLevel', {'thinkingLevel': level.name});

  Future<void> setCompaction(CompactionSettings compaction) =>
      _call('session.setCompaction', {'compaction': compaction.toJson()});

  Future<void> setTools(List<LlmTool> tools) async {
    _tools = {for (final t in tools) t.name: t};
    await _call('session.setTools', {'tools': [for (final t in tools) t.toJson()]});
  }

  /// Asks [approve] before every tool call; `null` runs tools unasked.
  Future<void> setApprover(LlmApprover? approve) async {
    _approve = approve;
    await _call('session.setApproval', {'approval': approve != null});
  }

  Future<void> setName(String? name) async {
    await _call('session.setName', {'name': name});
    this.name = name;
  }

  /// Closes the session. It stays stored; [FlPiLlm.openSession] reopens it.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _rt._sessions.remove(id);
    try {
      await _rt._request('session.close', {'sessionId': id});
    } finally {
      await _events.close();
    }
  }

  Future<Object?> _call(String method, Map<String, Object?> payload) {
    if (_closed) return Future.error(const LlmException('Session closed'));
    return _rt._request(method, {...payload, 'sessionId': id});
  }

  static LlmRunResult _result(Object? v) =>
      LlmRunResult(((v as Map)['result'] as Map).cast<String, Object?>());

  static List<LlmEntry> _entries(Object? v) => [
    for (final e in ((v as Map)['entries'] as List)) LlmEntry((e as Map).cast<String, Object?>()),
  ];

  @visibleForTesting
  Map<String, LlmTool> get tools => _tools;
}
