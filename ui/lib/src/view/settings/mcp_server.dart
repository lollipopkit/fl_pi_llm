import 'dart:async';

import 'package:fl_lib/fl_lib.dart';
import 'package:fl_pi_llm_ui/src/core/chats.dart';
import 'package:fl_pi_llm_ui/src/res/l10n.dart';
import 'package:fl_pi_llm_ui/src/store/stores.dart';
import 'package:fl_pi_llm_ui/src/tools/tool.dart';
import 'package:fl_pi_llm_ui/src/view/section_list.dart';
import 'package:fl_pi_llm_ui/src/view/settings/provider.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// One MCP server: its address and headers, its sign-in, and the tools it
/// offers. The address and headers are stored when saved; signing in and out
/// take effect at once.
class McpServerPage extends StatefulWidget {
  const McpServerPage({super.key, this.args});

  /// The server's URL, or null for a new one.
  final String? args;

  static const route = AppRoute<void, String>(page: McpServerPage.new, path: '/tools/mcp');

  /// Signs in to [id] in the browser, and says so if it failed.
  static Future<void> signIn(String id) async {
    try {
      await McpTools.signIn(id, open: _openBrowser);
    } finally {
      await _closeBrowser();
    }
    if (McpTools.errorOf(id) case final e? when !McpTools.isServerConnected(id)) Toast.error(e);
    Chats.reconfigureSoon();
  }

  /// In the app on a phone, where going to the browser and back is a trip
  /// through the app switcher; in the user's own browser on a desktop, where
  /// they are signed in already.
  static Future<void> _openBrowser(Uri uri) async {
    final inApp = isMobile && await supportsLaunchMode(LaunchMode.inAppBrowserView);
    final ok = await launchUrl(uri, mode: inApp ? LaunchMode.inAppBrowserView : LaunchMode.externalApplication);
    if (!ok) throw StateError('Cannot open $uri');
  }

  static Future<void> _closeBrowser() async {
    if (!isMobile) return;
    try {
      if (await supportsCloseForLaunchMode(LaunchMode.inAppBrowserView)) await closeInAppWebView();
    } catch (_) {}
  }

  @override
  State<McpServerPage> createState() => _McpServerPageState();
}

/// A header being edited.
typedef _Header = ({TextEditingController name, TextEditingController value});

class _McpServerPageState extends State<McpServerPage> {
  static final _store = LlmStores.tool;

  late final _url = TextEditingController(text: widget.args);
  final _headers = <_Header>[];

  String? get _saved => widget.args;
  String? get _id => _saved == null ? null : McpTools.nameFor(_saved!);

  @override
  void initState() {
    super.initState();
    if (_id case final id?) {
      for (final MapEntry(:key, :value) in McpTools.headersOf(id).entries) {
        _headers.add(_header(key, value));
      }
    }
  }

  @override
  void dispose() {
    _url.dispose();
    for (final h in _headers) {
      h.name.dispose();
      h.value.dispose();
    }
    super.dispose();
  }

  _Header _header([String name = '', String value = '']) =>
      (name: TextEditingController(text: name), value: TextEditingController(text: value));

  String get _address => _url.text.trim();

  bool get _urlValid {
    final u = Uri.tryParse(_address);
    return u != null && u.host.isNotEmpty && (u.isScheme('https') || u.isScheme('http'));
  }

  /// The headers as typed, or null after saying why they cannot be saved.
  Map<String, String>? _readHeaders() {
    final out = <String, String>{};
    for (final h in _headers) {
      final name = h.name.text.trim(), value = h.value.text.trim();
      if (name.isEmpty && value.isEmpty) continue;
      if (!McpSecret.isHeaderName(name) || value.isEmpty || value.contains('\n')) {
        Toast.warn(llmL10n.mcpHeadersInvalid);
        return null;
      }
      out[name] = value;
    }
    if (out.isNotEmpty && !McpAuth.canCarrySecrets(_address)) {
      Toast.warn(llmL10n.mcpInsecure);
      return null;
    }
    return out;
  }

  Future<void> _save() async {
    if (!_urlValid) {
      Toast.warn(libL10n.fail);
      return;
    }
    final headers = _readHeaders();
    if (headers == null) return;
    final url = _address;
    final (_, err) = await context.showLoadingDialog(
      fn: () => McpTools.saveServer(old: _saved, url: url, headers: headers),
    );
    Chats.reconfigureSoon();
    if (err != null || !mounted) return;
    final id = McpTools.nameFor(url);
    context.pop();
    // Just saved by a tap, so the browser may open without another one.
    if (McpTools.needsSignIn(id) && McpAuth.canCarrySecrets(url)) unawaited(McpServerPage.signIn(id));
  }

  Future<void> _delete() async {
    final url = _saved;
    if (url == null) return;
    final ok = await context.showRoundDialog<bool>(
      title: libL10n.delete,
      child: Text(libL10n.askContinue('${libL10n.delete} $url')),
      actions: Btnx.cancelRedOk,
    );
    if (ok != true || !mounted) return;
    _store.mcpServers.set([..._store.mcpServers.get().where((e) => e != url)]);
    try {
      await McpTools.removeServer(McpTools.nameFor(url));
    } catch (e, s) {
      Loggers.app.warning('Remove MCP server', e, s);
    }
    Chats.reconfigureSoon();
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final body = ListenableBuilder(
      listenable: McpTools.changes,
      builder: (context, _) => SectionList(
        header: ProviderHeader(
          title: _id == null ? llmL10n.addServer : McpTools.labelOf(_id!) ?? _saved!,
          subtitle: _id == null ? llmL10n.mcpServers : _status(_id!),
          onBack: context.pop,
          onRefresh: _id == null
              ? null
              : () async {
                  await McpTools.retryConnection(_id!);
                  Chats.reconfigureSoon();
                },
        ),
        children: [
          SettingsGroup(
            title: llmL10n.endpoint,
            header: Input(
              controller: _url,
              autoFocus: _saved == null,
              label: 'URL',
              hint: 'https://mcp.example.net/mcp',
              type: TextInputType.url,
            ),
          ),
          _buildHeaders(),
          if (_id case final id?) ...[
            if (McpAuth.canCarrySecrets(_saved!)) _buildSignIn(id),
            _buildTools(id),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (_saved != null)
                Btn.text(
                  text: libL10n.delete,
                  textStyle: TextStyle(color: context.theme.colorScheme.error),
                  onTap: _delete,
                ),
              Btn.text(text: libL10n.save, onTap: _save),
            ],
          ),
        ],
      ),
    );
    return Scaffold(body: SafeArea(child: body));
  }

  static String _status(String id) {
    if (McpTools.isSigningIn(id)) return llmL10n.mcpSigningIn;
    if (McpTools.isServerConnected(id)) return llmL10n.connectedFmt(McpTools.toolCounts[id] ?? 0);
    if (McpTools.needsSignIn(id)) return llmL10n.mcpNeedsSignIn;
    return [llmL10n.disconnected, ?McpTools.errorOf(id)].join(' · ');
  }

  Widget _buildHeaders() {
    return SettingsGroup(
      title: llmL10n.mcpHeaders,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, h) in _headers.indexed)
            Row(
              children: [
                Expanded(flex: 2, child: Input(controller: h.name, label: libL10n.name, hint: 'Authorization')),
                Expanded(flex: 3, child: Input(controller: h.value, label: libL10n.value, obscureText: true)),
                Btn.icon(
                  icon: const Icon(Icons.remove_circle_outline, size: 19),
                  text: libL10n.delete,
                  onTap: () => setState(() {
                    final removed = _headers.removeAt(i);
                    // After the frame: the fields are still in this one.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      removed.name.dispose();
                      removed.value.dispose();
                    });
                  }),
                ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 0, 13, 6),
            child: Text(llmL10n.mcpHeadersTip, style: UIs.text12Grey),
          ),
        ],
      ),
      rows: [
        SettingsRow(
          icon: Icons.add,
          title: llmL10n.mcpAddHeader,
          onTap: () => setState(() => _headers.add(_header())),
        ),
      ],
    );
  }

  Widget _buildSignIn(String id) {
    final signingIn = McpTools.isSigningIn(id);
    final signedIn = McpTools.isSignedIn(id);
    return SettingsGroup(
      title: libL10n.login,
      rows: [
        SettingsRow(
          icon: signedIn ? Icons.verified_user_outlined : Icons.login,
          title: signingIn
              ? llmL10n.mcpSigningIn
              : signedIn
              ? llmL10n.mcpSignedInShort
              : McpTools.needsSignIn(id)
              ? llmL10n.mcpNeedsSignIn
              : llmL10n.mcpNotSignedIn,
          subtitle: llmL10n.mcpSignInTip,
          trailing: signingIn
              ? Btn.text(text: libL10n.cancel, onTap: () => McpTools.cancelSignIn(id))
              : signedIn
              ? Btn.text(
                  text: libL10n.logout,
                  onTap: () async {
                    await McpTools.signOut(id);
                    Chats.reconfigureSoon();
                  },
                )
              : Btn.text(text: libL10n.login, onTap: () => McpServerPage.signIn(id)),
        ),
      ],
    );
  }

  Widget _buildTools(String id) {
    final tools = McpTools.toolsOf(id);
    return SettingsGroup(
      title: '${llmL10n.tool} · ${tools.length}',
      rows: [
        for (final t in tools)
          SettingsRow(title: t.title, subtitle: t.description, mono: true),
      ],
    );
  }
}
