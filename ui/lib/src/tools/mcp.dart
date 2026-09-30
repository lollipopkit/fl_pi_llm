part of 'tool.dart';

/// One MCP server the user added, by URL.
final class _McpServer {
  _McpServer(this.url);

  final String url;
  McpClient? client;
  Transport? transport;
  List<Tool> tools = const [];
  bool connected = false;
  String? error;
  Timer? retry;
  int attempts = 0;

  /// Its headers and tokens, read from the keychain when connecting.
  McpSecret secret = const McpSecret();

  /// It answered that it wants a sign-in.
  bool needsSignIn = false;

  /// Completed to stop waiting for the browser, while a sign-in is.
  Completer<void>? signingIn;

  /// What the server calls itself; its host until it has said.
  String get label => client?.getServerVersion()?.name ?? Uri.tryParse(url)?.host ?? url;
}

/// The MCP servers (Streamable HTTP) and their tools.
abstract final class McpTools {
  static final _servers = <String, _McpServer>{};

  static const _maxAttempts = 3;
  static const _retryDelay = Duration(seconds: 5);
  static const _callTimeout = Duration(minutes: 5);

  /// Providers take tool names of at most this many characters.
  static const _maxNameLength = 64;

  static const _maxInstructions = 2000;

  /// Notified when a server connects, drops or relists its tools.
  static final changes = RNode();

  /// Connects every stored server. Run at launch; each connects on its own.
  static Future<void> connectStored() =>
      Future.wait([for (final url in LlmStores.tool.mcpServers.get()) connect(url)]);

  /// The id a server's tools are prefixed with: from its URL, so it stays the
  /// same across launches and when another server is removed.
  static String nameFor(String url) => 'mcp${_fnv(url)}';

  /// FNV-1a: `String.hashCode` is not stable across runs.
  static String _fnv(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  /// Connects [url], or reconnects it. Failures are kept for [errorOf] and
  /// retried a few times.
  static Future<void> connect(String url) async {
    final id = nameFor(url);
    final s = _servers[id] ??= _McpServer(url);
    s.retry?.cancel();
    await _close(s);
    s.secret = McpAuth.canCarrySecrets(url) ? McpSecrets.read(id) : const McpSecret();
    // A fresh transport each time: a closed one cannot be started again.
    final transport = StreamableHttpClientTransport(
      Uri.parse(url),
      opts: StreamableHttpClientTransportOptions(
        // Only with a token to give: a provider with none makes the transport
        // give up before asking, and a header could have been enough.
        authProvider: s.secret.oauth == null ? null : _McpTokens(s),
        oauthUriValidator: McpAuth.acceptEndpoint,
        requestInit: {'headers': s.secret.headers},
      ),
    );
    final client = McpClient(Implementation(name: LlmUi.appName, version: LlmUi.appVersion));
    s
      ..transport = transport
      ..client = client;
    // The client's, not the transport's: the client takes those over.
    client
      ..onerror = ((e) => _dropped(s, transport, '$e'))
      ..onclose = (() => _dropped(s, transport, null));
    try {
      await client.connect(transport);
      if (!identical(s.transport, transport)) return;
      client.setNotificationHandler<JsonRpcToolListChangedNotification>(
        Method.notificationsToolsListChanged,
        (_) => _listTools(s),
        (params, meta) => JsonRpcToolListChangedNotification(meta: meta),
      );
      s
        ..connected = true
        ..needsSignIn = false
        ..error = null
        ..attempts = 0;
      await _listTools(s);
      Loggers.app.info('MCP ${s.label}: ${s.tools.length} tools');
    } catch (e, s_) {
      if (!identical(s.transport, transport)) return;
      Loggers.app.warning('MCP connect $url', e, s_);
      // Asking again would get the same answer: it waits for a sign-in.
      final unauthorized = _isUnauthorized(e);
      s
        ..connected = false
        ..needsSignIn = unauthorized
        ..error = unauthorized ? null : '$e';
      if (!unauthorized) _retryLater(s);
    }
    changes.notify();
  }

  /// A 401 or 403. The transport says so with [UnauthorizedError] where it had
  /// a token to offer, and only in the message otherwise.
  static bool _isUnauthorized(Object e) =>
      e is UnauthorizedError || (e is McpError && RegExp(r'\(HTTP 40[13]\)').hasMatch(e.message));

  /// [transport] errored or closed. Only the current one counts: an old one
  /// closing after a reconnect says nothing about the server.
  static void _dropped(_McpServer s, Transport transport, String? error) {
    if (!identical(s.transport, transport) || !s.connected) return;
    Loggers.app.warning('MCP ${s.label} dropped: ${error ?? 'closed'}');
    s
      ..connected = false
      ..error = error;
    changes.notify();
    _retryLater(s);
  }

  static void _retryLater(_McpServer s) {
    if (s.attempts >= _maxAttempts || !_servers.containsKey(nameFor(s.url))) return;
    s.attempts++;
    s.retry?.cancel();
    s.retry = Timer(_retryDelay * s.attempts, () => unawaited(connect(s.url)));
  }

  static Future<void> _listTools(_McpServer s) async {
    final client = s.client;
    if (client == null) return;
    try {
      final tools = <Tool>[];
      String? cursor;
      do {
        final r = await client.listTools(params: cursor == null ? null : ListToolsRequest(cursor: cursor));
        tools.addAll(r.tools);
        cursor = r.nextCursor;
      } while (cursor != null);
      s.tools = tools;
    } catch (e, st) {
      Loggers.app.warning('MCP ${s.label}: list tools', e, st);
      s.tools = const [];
    }
    changes.notify();
  }

  static Future<void> _close(_McpServer s) async {
    final t = s.transport;
    s
      ..transport = null
      ..client = null
      ..connected = false
      ..tools = const [];
    if (t == null) return;
    try {
      await t.close();
    } catch (e) {
      Loggers.app.fine('MCP close ${s.url}: $e');
    }
  }

  /// Retries [id] now, from the start.
  static Future<void> retryConnection(String id) async {
    final s = _servers[id];
    if (s == null) return;
    s.attempts = 0;
    await connect(s.url);
  }

  static Future<void> removeServer(String id) async {
    final s = _servers.remove(id);
    McpSecrets.delete(id);
    if (s == null) return;
    s.retry?.cancel();
    s.signingIn?.complete();
    await _close(s);
    changes.notify();
  }

  /// Stores [url] with [headers] in place of [old] (null for a new server),
  /// and connects it. A sign-in stays with the address: moving to another
  /// forgets it, being for another server.
  static Future<void> saveServer({String? old, required String url, required Map<String, String> headers}) async {
    if (headers.isNotEmpty && !McpAuth.canCarrySecrets(url)) throw StateError('Not sending headers to $url over plain http');
    final list = LlmStores.tool.mcpServers.get();
    if (url != old && list.contains(url)) throw StateError('$url is added already');
    if (old != null && old != url) await removeServer(nameFor(old));
    final id = nameFor(url);
    McpSecrets.write(id, McpSecrets.read(id).withHeaders(headers));
    // In the list before connecting: a server that is down now is still one
    // the user added, and it shows as disconnected with a retry.
    LlmStores.tool.mcpServers.set([
      for (final e in list) e == old ? url : e,
      if (old == null || !list.contains(old)) url,
    ]);
    await connect(url);
  }

  /// Signs in to [id] in the browser, then connects with what it got.
  /// Returns quietly when the user stopped waiting.
  static Future<void> signIn(String id, {required Future<void> Function(Uri) open}) async {
    final s = _servers[id];
    if (s == null || s.signingIn != null) return;
    final cancel = s.signingIn = Completer<void>();
    s.error = null;
    changes.notify();
    try {
      final secret = McpSecrets.read(id);
      final tokens = await McpAuth.signIn(s.url, headers: secret.headers, open: open, cancel: cancel.future);
      McpSecrets.write(id, secret.withOAuth(tokens));
    } on McpSignInCancelled {
      return;
    } catch (e, st) {
      Loggers.app.warning('MCP ${s.label}: sign in', e, st);
      s.error = '$e';
      return;
    } finally {
      s.signingIn = null;
      changes.notify();
    }
    s.attempts = 0;
    await connect(s.url);
  }

  /// Stops waiting for the browser.
  static void cancelSignIn(String id) {
    final c = _servers[id]?.signingIn;
    if (c != null && !c.isCompleted) c.complete();
  }

  /// Forgets [id]'s tokens, and connects without them.
  static Future<void> signOut(String id) async {
    final s = _servers[id];
    if (s == null) return;
    McpSecrets.write(id, McpSecrets.read(id).withOAuth(null));
    s.attempts = 0;
    await connect(s.url);
  }

  /// Replaces [id]'s headers, and connects with them.
  static Future<void> setHeaders(String id, Map<String, String> headers) async {
    final s = _servers[id];
    if (s == null) return;
    if (headers.isNotEmpty && !McpAuth.canCarrySecrets(s.url)) throw StateError('Not sending headers to ${s.url} over plain http');
    McpSecrets.write(id, McpSecrets.read(id).withHeaders(headers));
    s.attempts = 0;
    await connect(s.url);
  }

  /// The headers [id] is sent, to edit them.
  static Map<String, String> headersOf(String id) => McpSecrets.read(id).headers;

  /// [id]'s tools, as the user reads them.
  static List<({String title, String? description})> toolsOf(String id) => [
    for (final t in _servers[id]?.tools ?? const <Tool>[]) (title: t.title ?? t.name, description: t.description),
  ];

  static bool needsSignIn(String id) => _servers[id]?.needsSignIn ?? false;

  static bool isSigningIn(String id) => _servers[id]?.signingIn != null;

  static bool isSignedIn(String id) => _servers[id]?.secret.oauth != null;

  static bool isServerConnected(String id) => _servers[id]?.connected ?? false;

  /// Why [id] last failed, if it did.
  static String? errorOf(String id) => _servers[id]?.error;

  /// What [id] calls itself.
  static String? labelOf(String id) => _servers[id]?.label;

  static Map<String, int> get toolCounts => {
    for (final MapEntry(:key, :value) in _servers.entries)
      if (value.connected) key: value.tools.length,
  };

  /// A tool's name as the model sees it: providers take `[a-zA-Z0-9_-]`,
  /// at most [_maxNameLength], and two servers may both have a `search`.
  static String toolName(String id, String tool) {
    final n = '${id}__$tool'.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    if (n.length <= _maxNameLength) return n;
    return '${n.substring(0, _maxNameLength - 9)}_${_fnv(tool)}';
  }

  /// `server · tool` for a tool name of [toolName]'s making, as the user
  /// reads it.
  static String? toolLabel(String name) {
    for (final MapEntry(key: id, value: s) in _servers.entries) {
      if (!name.startsWith('${id}__')) continue;
      final t = s.tools.firstWhereOrNull((t) => toolName(id, t.name) == name);
      return '${s.label} · ${t?.title ?? t?.name ?? name.substring(id.length + 2)}';
    }
    return null;
  }

  /// Every tool of every connected server, as the model gets it.
  static List<LlmTool> get llmTools => [
    for (final MapEntry(key: id, value: s) in _servers.entries)
      if (s.connected)
        for (final t in s.tools)
          LlmTool(
            name: toolName(id, t.name),
            description: '[${s.label}] ${t.description ?? t.title ?? ''}'.trim(),
            parameters: t.inputSchema.toJson(),
            label: '${s.label} · ${t.title ?? t.name}',
            execute: (call, cancel) => Tools.timed(() => _call(s, t.name, call.args, cancel)),
          ),
  ];

  /// What connected servers say about using them, for the system prompt.
  static String? get instructions {
    final parts = [
      for (final s in _servers.values)
        if (s.connected && (s.client?.getInstructions()?.trim() ?? '').isNotEmpty)
          '## ${s.label}\n\n${_cap(s.client!.getInstructions()!.trim(), _maxInstructions)}',
    ];
    if (parts.isEmpty) return null;
    return '# MCP servers\n\nInstructions from the MCP servers whose tools you have:\n\n${parts.join('\n\n')}';
  }

  static String _cap(String s, int n) => s.length <= n ? s : '${s.substring(0, n)}…';

  static Future<LlmToolResult> _call(_McpServer s, String tool, _Map args, LlmCancelToken cancel) async {
    final client = s.client;
    if (client == null || !s.connected) throw StateError('${s.label} is not connected');
    _log('MCP ${s.label} · $tool');
    final abort = BasicAbortController();
    unawaited(cancel.whenCancelled.then((_) => abort.abort('Stopped by the user')));
    final res = await client.callTool(
      CallToolRequest(name: tool, arguments: args),
      options: RequestOptions(signal: abort.signal, timeout: _callTimeout),
    );
    final parts = <Map<String, Object?>>[
      for (final c in res.content)
        switch (c) {
          TextContent() => LlmContent.text(c.text),
          ImageContent() => LlmContent.image(c.data, c.mimeType),
          AudioContent() => LlmContent.text('[Audio: ${c.mimeType}, not shown]'),
          EmbeddedResource(resource: final TextResourceContents r) => LlmContent.text('[${r.uri}]\n${r.text}'),
          EmbeddedResource(resource: final r) => LlmContent.text('[Resource: ${r.uri}, binary, not shown]'),
          ResourceLink() => LlmContent.text('[${c.title ?? c.name}](${c.uri})${c.description == null ? '' : ' ${c.description}'}'),
          _ => LlmContent.text(jsonEncode(c.toJson())),
        },
      if (res.content.isEmpty && res.structuredContent != null) LlmContent.text(jsonEncode(res.structuredContent)),
    ];
    if (res.isError) throw StateError(parts.map((p) => p['text'] ?? '').join('\n'));
    return LlmToolResult(content: parts);
  }
}
