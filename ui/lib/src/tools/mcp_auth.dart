part of 'tool.dart';

/// What a server is reached with besides its URL: headers the user typed, and
/// the tokens a sign-in got. Never backed up: see [McpSecretStore].
@immutable
final class McpSecret {
  const McpSecret({this.headers = const {}, this.oauth});

  final Map<String, String> headers;
  final McpOAuthTokens? oauth;

  bool get isEmpty => headers.isEmpty && oauth == null;

  McpSecret withHeaders(Map<String, String> headers) => McpSecret(headers: headers, oauth: oauth);
  McpSecret withOAuth(McpOAuthTokens? oauth) => McpSecret(headers: headers, oauth: oauth);

  factory McpSecret.fromJson(Map<String, Object?> json) => McpSecret(
    headers: (json['headers'] as Map?)?.cast<String, String>() ?? const {},
    oauth: switch (json['oauth']) {
      final Map m => McpOAuthTokens.fromJson(m.cast()),
      _ => null,
    },
  );

  Map<String, Object?> toJson() => {
    if (headers.isNotEmpty) 'headers': headers,
    if (oauth != null) 'oauth': oauth!.toJson(),
  };

  /// An RFC 9110 field name.
  static bool isHeaderName(String name) => RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$").hasMatch(name);
}

/// What a sign-in got, and what renewing it takes.
@immutable
final class McpOAuthTokens {
  const McpOAuthTokens({
    required this.accessToken,
    required this.issuer,
    required this.resource,
    this.refreshToken,
    this.expiresAt,
    this.clientId,
    this.tokenEndpoint,
    this.scope,
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;

  /// The authorization server's, as its metadata names it.
  final String issuer;

  /// The server the token is for (RFC 8707).
  final String resource;

  /// The client registered for the sign-in. With [tokenEndpoint], what a
  /// refresh takes; either missing means signing in again instead.
  final String? clientId;
  final String? tokenEndpoint;
  final String? scope;

  /// Renewed a minute early, so that a request does not go out with a token
  /// about to expire.
  bool get expired => expiresAt != null && DateTime.now().isAfter(expiresAt!.subtract(const Duration(minutes: 1)));

  bool get canRefresh => refreshToken != null && clientId != null && tokenEndpoint != null;

  factory McpOAuthTokens.fromJson(Map<String, Object?> json) => McpOAuthTokens(
    accessToken: json['accessToken'] as String,
    refreshToken: json['refreshToken'] as String?,
    expiresAt: switch (json['expiresAt']) {
      final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
      _ => null,
    },
    issuer: json['issuer'] as String,
    resource: json['resource'] as String,
    clientId: json['clientId'] as String?,
    tokenEndpoint: json['tokenEndpoint'] as String?,
    scope: json['scope'] as String?,
  );

  Map<String, Object?> toJson() => {
    'accessToken': accessToken,
    'refreshToken': ?refreshToken,
    'expiresAt': ?expiresAt?.millisecondsSinceEpoch,
    'issuer': issuer,
    'resource': resource,
    'clientId': ?clientId,
    'tokenEndpoint': ?tokenEndpoint,
    'scope': ?scope,
  };

  OAuthTokens get forTransport => OAuthIssuerBoundAuthorizationCodeTokens(
    accessToken: accessToken,
    refreshToken: refreshToken,
    authorizationServerIssuer: issuer,
    resource: Uri.parse(resource),
  );
}

/// [McpSecret]s, by server, in [LlmStores.mcpSecret].
abstract final class McpSecrets {
  static McpSecret read(String id) {
    final raw = LlmStores.mcpSecret.get<Map>(id);
    if (raw == null) return const McpSecret();
    try {
      return McpSecret.fromJson(raw.cast());
    } catch (e) {
      Loggers.app.warning('MCP secret of $id is unreadable', e);
      return const McpSecret();
    }
  }

  static void write(String id, McpSecret secret) {
    if (secret.isEmpty) return delete(id);
    LlmStores.mcpSecret.set(id, secret.toJson());
  }

  static void delete(String id) => LlmStores.mcpSecret.remove(id);
}

/// Hands the transport a connection's token, renewed when it has expired.
///
/// Never starts a sign-in: that opens a browser, which only a tap may do. A
/// server that wants one fails to connect with [UnauthorizedError], and asks.
final class _McpTokens implements OAuthClientProvider {
  _McpTokens(this.s);

  final _McpServer s;
  Future<McpOAuthTokens?>? _refreshing;

  @override
  Future<OAuthTokens?> tokens() async {
    var t = s.secret.oauth;
    if (t == null) return null;
    if (t.expired) {
      t = await (_refreshing ??= _refresh(t).whenComplete(() => _refreshing = null));
    }
    return t?.forTransport;
  }

  @override
  Future<void> redirectToAuthorization() async {}

  /// The renewed tokens, or null for a sign-in again: the old ones are dropped
  /// either way, being of no more use.
  Future<McpOAuthTokens?> _refresh(McpOAuthTokens t) async {
    McpOAuthTokens? next;
    if (t.canRefresh) {
      try {
        next = await McpAuth.refresh(t);
      } catch (e) {
        Loggers.app.warning('MCP ${s.label}: refresh', e);
      }
    }
    s.secret = s.secret.withOAuth(next);
    McpSecrets.write(McpTools.nameFor(s.url), s.secret);
    return next;
  }
}

/// The sign-in's side of OAuth: the browser, and the tokens it ends with.
final class _McpSignIn implements OAuthAuthorizationCodeProvider {
  _McpSignIn(this.redirectUri, this.open);

  @override
  final Uri redirectUri;

  final Future<void> Function(Uri) open;

  /// Where the browser went, with the client the transport registered in it.
  Uri? authorizationUri;
  OAuthIssuerBoundAuthorizationCodeTokens? saved;

  /// Registered anew each time: the redirect names a port picked for this
  /// sign-in, and a client registered for another port cannot use it.
  @override
  String get clientId => '';

  @override
  String? get clientSecret => null;

  @override
  List<String> get scopes => const [];

  @override
  Future<OAuthTokens?> tokens() async => null;

  @override
  Future<void> redirectToAuthorization() async {}

  @override
  Future<void> redirectToAuthorizationUrl(Uri uri) async {
    authorizationUri = uri;
    await open(uri);
  }

  @override
  Future<void> saveTokens(OAuthTokens tokens) async {
    if (tokens is! OAuthIssuerBoundAuthorizationCodeTokens) {
      throw StateError('Tokens not bound to an authorization server');
    }
    saved = tokens;
  }
}

/// Signing in to an MCP server (the MCP authorization spec: OAuth 2.1 with
/// PKCE, the server's metadata and dynamic client registration), mostly by
/// `mcp_dart`'s transport. What it leaves out is here: the browser and the
/// redirect back, keeping the tokens, and renewing them.
abstract final class McpAuth {
  /// How long a sign-in waits for the browser to come back.
  static const timeout = Duration(minutes: 5);

  static const _callbackPath = '/callback';

  static final _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(seconds: 30)));

  /// Whether [url] may be sent a secret. Plain `http` only to this device:
  /// anywhere else a header or a token would cross the network unencrypted.
  static bool canCarrySecrets(String url) {
    final u = Uri.tryParse(url);
    if (u == null) return false;
    return u.scheme == 'https' || (u.scheme == 'http' && _isLoopback(u.host));
  }

  static bool _isLoopback(String host) =>
      host == 'localhost' || (InternetAddress.tryParse(host)?.isLoopback ?? false);

  /// An authorization server on another host than the MCP server is common
  /// (`mcp.example.com` signing in at `auth.example.com`), and the user sees
  /// where they sign in. What is refused is anything but `https`.
  static bool acceptEndpoint(Uri uri, OAuthEndpointKind _) => uri.scheme == 'https';

  /// Signs in to [url] in the browser; the tokens, or null if [url] turned
  /// out to need none.
  ///
  /// The browser comes back to a port on this device the sign-in listens on
  /// (RFC 8252's loopback redirect), which every platform can do without an
  /// app link or a URL scheme of its own. [cancel] ends the wait.
  static Future<McpOAuthTokens?> signIn(
    String url, {
    Map<String, String> headers = const {},
    required Future<void> Function(Uri) open,
    Future<void>? cancel,
  }) async {
    if (!canCarrySecrets(url)) throw StateError('Not signing in to $url over plain http');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final provider = _McpSignIn(Uri.parse('http://127.0.0.1:${server.port}$_callbackPath'), open);
    final transport = StreamableHttpClientTransport(
      Uri.parse(url),
      opts: StreamableHttpClientTransportOptions(
        authProvider: provider,
        oauthUriValidator: acceptEndpoint,
        requestInit: {'headers': headers},
      ),
    );
    // Listening before the browser opens: it can come back before the call
    // that opened it returns.
    final (callback, stopListening) = _awaitCallback(server, cancel);
    try {
      await transport.start();
      // Straight on the transport, not through a client: a client closes it
      // when connecting fails, and with it the verifier the code is
      // exchanged with.
      try {
        await transport.send(
          JsonRpcInitializeRequest(
            id: 0,
            initParams: InitializeRequest(
              protocolVersion: latestInitializationProtocolVersion,
              capabilities: const ClientCapabilities(),
              clientInfo: Implementation(name: LlmUi.appName, version: LlmUi.appVersion),
            ),
          ),
        );
        return null;
      } on UnauthorizedError {
        if (provider.authorizationUri == null) rethrow;
      }

      final q = (await callback).queryParameters;
      if (q['error'] case final error?) throw StateError(q['error_description'] ?? error);
      final code = q['code'];
      final state = q['state'];
      if (code == null || state == null) throw StateError('The sign-in came back without a code');
      await transport.finishAuthRedirect(code, state: state, issuer: q['iss']);

      final t = provider.saved;
      if (t == null) throw StateError('The sign-in ended without tokens');
      final meta = await _metadata(t.authorizationServerIssuer);
      final methods = (meta?['token_endpoint_auth_methods_supported'] as List?)?.cast<String>();
      // The transport registers a public client where the server allows one,
      // and a confidential one otherwise — whose secret it keeps to itself,
      // so a refresh is not possible and the next sign-in is in the browser.
      final public = methods?.contains('none') ?? false;
      return McpOAuthTokens(
        accessToken: t.accessToken,
        refreshToken: public ? t.refreshToken : null,
        expiresAt: t.expiresIn == null ? null : DateTime.now().add(Duration(seconds: t.expiresIn!)),
        issuer: t.authorizationServerIssuer,
        resource: t.resource.toString(),
        clientId: provider.authorizationUri?.queryParameters['client_id'],
        tokenEndpoint: meta?['token_endpoint'] as String?,
        scope: t.scope,
      );
    } finally {
      stopListening();
      await server.close(force: true);
      await transport.close();
    }
  }

  /// The first request to [_callbackPath], answered with a page saying the
  /// browser can be closed. Anything else, a favicon, is a 404. The function
  /// stops listening, whether or not it came.
  static (Future<Uri>, void Function()) _awaitCallback(HttpServer server, Future<void>? cancel) {
    final done = Completer<Uri>();
    // Handled here: a sign-in that ends before it waits never reads it.
    done.future.ignore();
    final sub = server.listen((req) async {
      if (req.uri.path != _callbackPath || done.isCompleted) {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
        return;
      }
      final ok = req.uri.queryParameters['code'] != null;
      req.response
        ..headers.contentType = ContentType.html
        ..write(_page(ok ? llmL10n.mcpSignedIn : llmL10n.mcpSignInFailed));
      await req.response.close();
      done.complete(req.uri);
    });
    void fail(Object e) {
      if (!done.isCompleted) done.completeError(e);
    }

    final timer = Timer(timeout, () => fail(TimeoutException('No sign-in in the browser', timeout)));
    unawaited(cancel?.then((_) => fail(const McpSignInCancelled())));
    return (
      done.future,
      () {
        timer.cancel();
        unawaited(sub.cancel());
        fail(const McpSignInCancelled());
      },
    );
  }

  static String _page(String text) {
    final t = const HtmlEscape().convert(text);
    return '<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width">'
        '<title>${const HtmlEscape().convert(LlmUi.appName)}</title>'
        '<body style="font:16px system-ui;display:grid;place-items:center;height:90vh;margin:0">'
        '<p>$t</p>';
  }

  /// Renews [t] with its refresh token. Throws when the server says no.
  static Future<McpOAuthTokens> refresh(McpOAuthTokens t) async {
    final res = await _dio.post<Map<String, Object?>>(
      t.tokenEndpoint!,
      data: {
        'grant_type': 'refresh_token',
        'refresh_token': t.refreshToken,
        'client_id': t.clientId,
        'resource': t.resource,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType, responseType: ResponseType.json),
    );
    final body = res.data ?? const {};
    final access = body['access_token'];
    if (access is! String || access.isEmpty) throw StateError('The refresh had no access_token');
    final expiresIn = body['expires_in'];
    return McpOAuthTokens(
      accessToken: access,
      // Rotated where the server rotates them, kept where it does not.
      refreshToken: body['refresh_token'] as String? ?? t.refreshToken,
      expiresAt: expiresIn is num ? DateTime.now().add(Duration(seconds: expiresIn.toInt())) : null,
      issuer: t.issuer,
      resource: t.resource,
      clientId: t.clientId,
      tokenEndpoint: t.tokenEndpoint,
      scope: body['scope'] as String? ?? t.scope,
    );
  }

  /// The authorization server's metadata (RFC 8414, then OpenID Connect's),
  /// for its token endpoint. Null when there is none to be had: that only
  /// costs the refresh.
  static Future<Map<String, Object?>?> _metadata(String issuer) async {
    final u = Uri.parse(issuer);
    final path = u.path == '/' ? '' : u.path;
    final candidates = [
      u.replace(path: '/.well-known/oauth-authorization-server$path'),
      u.replace(path: '/.well-known/openid-configuration$path'),
      if (path.isNotEmpty) u.replace(path: '$path/.well-known/openid-configuration'),
    ];
    for (final c in candidates) {
      try {
        final res = await _dio.getUri<Map<String, Object?>>(c, options: Options(responseType: ResponseType.json));
        final m = res.data;
        // Only the issuer's own: metadata naming another is not about it.
        if (m != null && m['issuer'] == issuer && m['token_endpoint'] is String) {
          final endpoint = Uri.tryParse(m['token_endpoint'] as String);
          if (endpoint != null && canCarrySecrets(endpoint.toString())) return m;
        }
      } catch (_) {}
    }
    return null;
  }
}

/// The user stopped waiting for the browser.
final class McpSignInCancelled implements Exception {
  const McpSignInCancelled();
}
