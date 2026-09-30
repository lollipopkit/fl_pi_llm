// MCP servers that want more than a URL: a header, or an OAuth sign-in (the
// MCP authorization spec), against a server on this device that is both the
// MCP server and its authorization server.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_lib/fl_lib.dart';
import 'package:fl_pi_llm_ui/src/config.dart';
import 'package:fl_pi_llm_ui/src/store/stores.dart';
import 'package:fl_pi_llm_ui/src/tools/tool.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the mock accepts, and what it saw.
final class _Mock {
  late final HttpServer server;
  String get base => 'http://127.0.0.1:${server.port}';
  String get url => '$base/mcp';

  /// A header that lets a request in, when the test uses one.
  String? apiKey;

  /// Access tokens that let a request in.
  final valid = <String>{};

  /// Added to the server's `serverInfo`.
  Map<String, Object?> serverInfo = const {};

  /// Token expiry in seconds, per grant.
  int codeExpiresIn = 3600;
  bool refreshFails = false;

  final grants = <String>[];
  final bearers = <String>[];
  String? registeredRedirect;
  Map? registration;
  int _issued = 0;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handle);
  }

  Future<void> _json(HttpRequest req, Object body, [int status = 200]) async {
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await req.response.close();
  }

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    switch (path) {
      case '/.well-known/oauth-protected-resource/mcp' || '/.well-known/oauth-protected-resource':
        return _json(req, {'resource': url, 'authorization_servers': [base]});
      case '/.well-known/oauth-authorization-server':
        return _json(req, {
          'issuer': base,
          'authorization_endpoint': '$base/authorize',
          'token_endpoint': '$base/token',
          'registration_endpoint': '$base/register',
          'response_types_supported': ['code'],
          'grant_types_supported': ['authorization_code', 'refresh_token'],
          'code_challenge_methods_supported': ['S256'],
          'token_endpoint_auth_methods_supported': ['none'],
        });
      case '/register':
        final body = jsonDecode(await utf8.decodeStream(req)) as Map;
        registration = body;
        registeredRedirect = (body['redirect_uris'] as List).single as String;
        return _json(req, {'client_id': 'client-1', 'token_endpoint_auth_method': 'none'}, 201);
      case '/token':
        final form = Uri.splitQueryString(await utf8.decodeStream(req));
        final grant = form['grant_type']!;
        grants.add(grant);
        if (grant == 'refresh_token' && (refreshFails || form['client_id'] != 'client-1')) {
          return _json(req, {'error': 'invalid_grant'}, 400);
        }
        final access = 'access-${++_issued}';
        valid.add(access);
        return _json(req, {
          'access_token': access,
          'token_type': 'Bearer',
          'refresh_token': 'refresh-$_issued',
          'expires_in': grant == 'authorization_code' ? codeExpiresIn : 3600,
        });
      case '/mcp':
        return _mcp(req);
    }
    req.response.statusCode = 404;
    await req.response.close();
  }

  Future<void> _mcp(HttpRequest req) async {
    final auth = req.headers.value('authorization');
    if (auth != null) bearers.add(auth);
    final byKey = apiKey != null && req.headers.value('x-api-key') == apiKey;
    final byToken = auth != null && valid.contains(auth.replaceFirst('Bearer ', ''));
    if (!byKey && !byToken) {
      await utf8.decodeStream(req);
      req.response
        ..statusCode = 401
        ..headers.set(
          'www-authenticate',
          'Bearer resource_metadata="$base/.well-known/oauth-protected-resource/mcp"',
        );
      await req.response.close();
      return;
    }
    if (req.method != 'POST') {
      req.response.statusCode = 405;
      await req.response.close();
      return;
    }
    final msg = jsonDecode(await utf8.decodeStream(req)) as Map;
    final id = msg['id'];
    if (id == null) {
      req.response.statusCode = 202;
      await req.response.close();
      return;
    }
    final result = switch (msg['method']) {
      'initialize' => {
        'protocolVersion': (msg['params'] as Map)['protocolVersion'],
        'capabilities': {'tools': {}},
        'serverInfo': {'name': 'mock', 'version': '1', ...serverInfo},
      },
      'tools/list' => {
        'tools': [
          {
            'name': 'echo',
            'inputSchema': {'type': 'object'},
          },
        ],
      },
      _ => null,
    };
    return _json(req, {
      'jsonrpc': '2.0',
      'id': id,
      if (result != null) 'result': result else 'error': {'code': -32601, 'message': 'no'},
    });
  }

  /// The browser: follows the authorization URL straight back to the app,
  /// the way a user who approves does.
  Future<void> approve(Uri authorize) async {
    expect(authorize.path, '/authorize');
    expect(authorize.queryParameters['code_challenge_method'], 'S256');
    final redirect = Uri.parse(authorize.queryParameters['redirect_uri']!);
    expect(redirect.host, '127.0.0.1');
    final back = redirect.replace(
      queryParameters: {'code': 'code-1', 'state': authorize.queryParameters['state']!, 'iss': base},
    );
    final client = HttpClient();
    final res = await (await client.getUrl(back)).close();
    await res.drain<void>();
    client.close();
  }
}

Map<String, Object?>? _stored(String url) =>
    LlmStores.mcpSecret.get<Map>(McpTools.nameFor(url))?.cast();

void main() {
  // No `TestWidgetsFlutterBinding`: it answers every HTTP request with a 400.
  late _Mock mock;

  // Real sockets to the mock: `flutter test` stubs `HttpClient` otherwise.
  setUpAll(() {
    HttpOverrides.global = null;
    LlmUi.appName = 'Test App';
    LlmUi.appUri = Uri.parse('https://app.example/');
  });

  setUp(() async {
    SqliteDb.openInMemory();
    mock = _Mock();
    await mock.start();
  });

  tearDown(() async {
    await McpTools.removeServer(McpTools.nameFor(mock.url));
    await mock.server.close(force: true);
    await SqliteDb.close();
  });

  test('are kept apart from the tool settings, which apps back up', () {
    expect(LlmStores.all, isNot(contains(LlmStores.mcpSecret)));
  });

  group('headers', () {
    test('a server that wants one asks until it has it', () async {
      mock.apiKey = 'k-1';
      final id = McpTools.nameFor(mock.url);
      await McpTools.connect(mock.url);
      expect(McpTools.isServerConnected(id), isFalse);
      expect(McpTools.needsSignIn(id), isTrue);

      await McpTools.setHeaders(id, {'X-Api-Key': 'k-1'});
      expect(McpTools.isServerConnected(id), isTrue);
      expect(McpTools.toolCounts[id], 1);
      expect(_stored(mock.url)!['headers'], {'X-Api-Key': 'k-1'});
    });

    test('have names of token characters only', () {
      expect(McpSecret.isHeaderName('X-Api-Key'), isTrue);
      expect(McpSecret.isHeaderName('Authorization'), isTrue);
      expect(McpSecret.isHeaderName('Bad Name'), isFalse);
      expect(McpSecret.isHeaderName('X:Key'), isFalse);
      expect(McpSecret.isHeaderName(''), isFalse);
    });

    test('are never sent over plain http to another machine', () async {
      expect(McpAuth.canCarrySecrets('https://mcp.example.net/mcp'), isTrue);
      expect(McpAuth.canCarrySecrets('http://127.0.0.1:1/mcp'), isTrue);
      expect(McpAuth.canCarrySecrets('http://localhost/mcp'), isTrue);
      expect(McpAuth.canCarrySecrets('http://mcp.example.net/mcp'), isFalse);
      await expectLater(
        McpAuth.signIn('http://mcp.example.net/mcp', open: (_) async {}),
        throwsStateError,
      );
    });
  });

  group('saving', () {
    test('adds a server with its headers, and connects it', () async {
      mock.apiKey = 'k-1';
      await McpTools.saveServer(url: mock.url, headers: {'X-Api-Key': 'k-1'});
      expect(LlmStores.tool.mcpServers.get(), [mock.url]);
      expect(McpTools.isServerConnected(McpTools.nameFor(mock.url)), isTrue);
    });

    test("a new address takes the old one's place, and not its sign-in", () async {
      await McpTools.connect(mock.url);
      await McpTools.signIn(McpTools.nameFor(mock.url), open: mock.approve);
      LlmStores.tool.mcpServers.set(['https://a.example/mcp', mock.url, 'https://b.example/mcp']);

      final moved = '${mock.base}/mcp?v=2';
      await McpTools.saveServer(old: mock.url, url: moved, headers: {'X-K': 'v'});

      expect(LlmStores.tool.mcpServers.get(), ['https://a.example/mcp', moved, 'https://b.example/mcp']);
      expect(_stored(mock.url), isNull);
      expect(_stored(moved), {'headers': {'X-K': 'v'}});
      await McpTools.removeServer(McpTools.nameFor(moved));
    });

    test('keeps the sign-in when only the headers change', () async {
      await McpTools.connect(mock.url);
      await McpTools.signIn(McpTools.nameFor(mock.url), open: mock.approve);
      LlmStores.tool.mcpServers.set([mock.url]);
      await McpTools.saveServer(old: mock.url, url: mock.url, headers: {'X-K': 'v'});
      expect(_stored(mock.url)!['oauth'], isNotNull);
      expect(McpTools.isServerConnected(McpTools.nameFor(mock.url)), isTrue);
    });

    test('refuses an address already added, and headers over plain http', () async {
      LlmStores.tool.mcpServers.set([mock.url, 'https://b.example/mcp']);
      await expectLater(
        McpTools.saveServer(old: 'https://b.example/mcp', url: mock.url, headers: const {}),
        throwsStateError,
      );
      await expectLater(
        McpTools.saveServer(url: 'http://mcp.example.net/mcp', headers: {'X-K': 'v'}),
        throwsStateError,
      );
      expect(LlmStores.tool.mcpServers.get(), [mock.url, 'https://b.example/mcp']);
    });
  });

  test('icons: declared ones from its own hosts, then favicons', () async {
    mock
      ..apiKey = 'k'
      ..serverInfo = {
        'websiteUrl': 'https://example.com/about',
        'icons': [
          {'src': 'https://tracker.example.net/i.png'},
          {'src': 'data:image/png;base64,AAAA', 'theme': 'light'},
          {'src': 'https://cdn.example.com/dark.svg', 'theme': 'dark'},
          {'src': 'http://example.com/plain.png'},
        ],
      };
    await McpTools.saveServer(url: mock.url, headers: {'X-Api-Key': 'k'});
    final id = McpTools.nameFor(mock.url);
    final dark = McpTools.iconsOf(id, dark: true);
    expect([for (final i in dark) '${i.uri}'.substring(0, 24)], [
      'https://cdn.example.com/',
      'data:image/png;base64,AA',
      'https://example.com/favi',
      '${mock.base}/favicon.ico'.substring(0, 24),
    ]);
    expect(dark.first.svg, isTrue);
    expect('${dark[3].uri}', '${mock.base}/favicon.ico');
    expect('${McpTools.iconsOf(id, dark: false).first.uri}', startsWith('data:'));
    expect(McpTools.serverOfTool(McpTools.toolName(id, 'echo')), id);
    expect(McpTools.serverOfTool('memory_read'), isNull);
  });

  test('a stored server connects at launch, and asks for a sign-in', () async {
    LlmStores.tool.mcpServers.set([mock.url]);
    final id = McpTools.nameFor(mock.url);
    final connecting = McpTools.connectStored();
    expect(McpTools.isConnecting(id), isTrue);
    await connecting;
    expect(McpTools.isConnecting(id), isFalse);
    expect(McpTools.needsSignIn(id), isTrue);
  });

  test('a retry connects a server never tried this run', () async {
    mock.apiKey = 'k';
    McpSecrets.write(McpTools.nameFor(mock.url), const McpSecret(headers: {'X-Api-Key': 'k'}));
    await McpTools.retryConnection(mock.url);
    expect(McpTools.isServerConnected(McpTools.nameFor(mock.url)), isTrue);
  });

  group('sign-in', () {
    test('goes through the browser, and connects with what it got', () async {
      final id = McpTools.nameFor(mock.url);
      await McpTools.connect(mock.url);
      expect(McpTools.needsSignIn(id), isTrue);

      await McpTools.signIn(id, open: mock.approve);

      expect(McpTools.isServerConnected(id), isTrue);
      expect(McpTools.isSignedIn(id), isTrue);
      expect(mock.grants, ['authorization_code']);
      expect(mock.bearers.last, 'Bearer access-1');
      expect(Uri.parse(mock.registeredRedirect!).host, '127.0.0.1');
      // What the consent page calls the client: the app, not the library.
      expect(mock.registration!['client_name'], LlmUi.appName);
      expect(mock.registration!['client_uri'], 'https://app.example/');
      final oauth = _stored(mock.url)!['oauth'] as Map;
      expect(oauth['accessToken'], 'access-1');
      expect(oauth['clientId'], 'client-1');
      expect(oauth['tokenEndpoint'], '${mock.base}/token');
      expect(oauth['resource'], mock.url);
    });

    test('renews an expired token by itself, and keeps the new one', () async {
      // Within the minute a token is renewed early.
      mock.codeExpiresIn = 30;
      final id = McpTools.nameFor(mock.url);
      await McpTools.connect(mock.url);
      await McpTools.signIn(id, open: mock.approve);

      expect(McpTools.isServerConnected(id), isTrue);
      expect(mock.grants, ['authorization_code', 'refresh_token']);
      expect(mock.bearers.last, 'Bearer access-2');
      final oauth = _stored(mock.url)!['oauth'] as Map;
      expect(oauth['accessToken'], 'access-2');
      expect(oauth['refreshToken'], 'refresh-2', reason: 'rotated');
    });

    test('a refused refresh asks for a sign-in again', () async {
      mock
        ..codeExpiresIn = 30
        ..refreshFails = true;
      final id = McpTools.nameFor(mock.url);
      await McpTools.connect(mock.url);
      await McpTools.signIn(id, open: mock.approve);

      expect(McpTools.isServerConnected(id), isFalse);
      expect(McpTools.needsSignIn(id), isTrue);
      expect(_stored(mock.url)?['oauth'], isNull);
    });

    test('signing out forgets the tokens', () async {
      final id = McpTools.nameFor(mock.url);
      await McpTools.connect(mock.url);
      await McpTools.signIn(id, open: mock.approve);
      await McpTools.signOut(id);

      expect(McpTools.isSignedIn(id), isFalse);
      expect(McpTools.needsSignIn(id), isTrue);
      expect(_stored(mock.url), isNull);
    });

    test('can be given up on while the browser is open', () async {
      final id = McpTools.nameFor(mock.url);
      await McpTools.connect(mock.url);
      final opened = Completer<void>();
      final signing = McpTools.signIn(id, open: (_) async => opened.complete());
      await opened.future;
      expect(McpTools.isSigningIn(id), isTrue);

      McpTools.cancelSignIn(id);
      await signing;
      expect(McpTools.isSigningIn(id), isFalse);
      expect(McpTools.errorOf(id), isNull);
      expect(_stored(mock.url), isNull);
    });

    test('removing the server takes its secrets with it', () async {
      final id = McpTools.nameFor(mock.url);
      await McpTools.connect(mock.url);
      await McpTools.signIn(id, open: mock.approve);
      await McpTools.removeServer(id);
      expect(_stored(mock.url), isNull);
    });
  });
}
