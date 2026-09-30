import 'package:fl_lib/fl_lib.dart';
import 'package:fl_pi_llm_ui/src/core/chats.dart';
import 'package:fl_pi_llm_ui/src/res/l10n.dart';
import 'package:fl_pi_llm_ui/src/store/stores.dart';
import 'package:fl_pi_llm_ui/src/tools/tool.dart';
import 'package:fl_pi_llm_ui/src/view/section_list.dart';
import 'package:fl_pi_llm_ui/src/view/settings/memory.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Tools: the switch, the built-in ones, and the MCP servers.
class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key});

  static final _store = LlmStores.tool;

  static IconData _iconOf(ToolFunc t) => switch (t) {
    TfHistory() => Icons.history,
    TfHttpReq() => Icons.language,
    TfMemory() => Icons.psychology_alt_outlined,
    _ => Icons.extension_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return SectionList(
      children: [
        SettingsGroup(
          title: llmL10n.tool,
          rows: [
            SettingsRow(
              icon: Icons.build_outlined,
              title: llmL10n.useTools,
              subtitle: llmL10n.useToolsTip,
              trailing: StoreSwitch(prop: _store.enabled, callback: (_) => Chats.reconfigureSoon()),
            ),
          ],
        ),
        ListenableBuilder(
          listenable: Listenable.merge([_store.disabledTools.listenable(), _store.enabledTools.listenable()]),
          builder: (context, _) => SettingsGroup(
            title: llmL10n.builtIn,
            rows: [
              SettingsRow(
                icon: Icons.psychology_alt_outlined,
                title: llmL10n.memory,
                subtitle: llmL10n.memoryToolTip,
                trailing: _switch(TfMemory.all.first),
                onTap: () => MemoryPage.route.go(context),
              ),
              for (final t in Tools.groups)
                if (t is! TfMemory)
                  SettingsRow(icon: _iconOf(t), title: t.groupLabel, subtitle: t.l10nTip, trailing: _switch(t)),
              _store.permittedTools.listenable().listenVal((list) {
                return SettingsRow(
                  icon: Icons.verified_user_outlined,
                  title: llmL10n.allowedWithoutAsking,
                  trailing: Flexible(
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: RowValue(list.isEmpty ? libL10n.empty : list.map(Tools.labelOf).join(', ')),
                    ),
                  ),
                  onTap: list.isEmpty ? null : () => _editPermitted(context, list),
                );
              }),
            ],
          ),
        ),
        ListenableBuilder(
          listenable: Listenable.merge([_store.mcpServers.listenable(), McpTools.changes]),
          builder: (context, _) {
            final urls = _store.mcpServers.get();
            return SettingsGroup(
              title: llmL10n.mcpServers,
              rows: [
                for (final url in urls) _server(context, url),
                SettingsRow(icon: Icons.add, title: llmL10n.addServer, onTap: () => _addServer(context)),
              ],
            );
          },
        ),
      ],
    );
  }

  /// The switch of the built-in tools in [t]'s group.
  static Widget _switch(ToolFunc t) => SwitchX(
    value: Tools.isOn(t),
    onChanged: (on) {
      Tools.setOn(t, on);
      Chats.reconfigureSoon();
    },
  );

  Widget _server(BuildContext context, String url) {
    final name = McpTools.nameFor(url);
    final on = McpTools.isServerConnected(name);
    final err = McpTools.errorOf(name);
    final signingIn = McpTools.isSigningIn(name);
    final needsSignIn = McpTools.needsSignIn(name);
    final signedIn = McpTools.isSignedIn(name);
    final secure = McpAuth.canCarrySecrets(url);
    void menu([Offset? at]) => showContextMenu(
      context,
      [
        if (secure) ...[
          ContextMenuAction(text: llmL10n.mcpHeaders, icon: Icons.vpn_key_outlined, onTap: () => _editHeaders(context, url)),
          if (signedIn)
            ContextMenuAction(text: libL10n.logout, icon: Icons.logout, onTap: () => _run(() => McpTools.signOut(name)))
          else if (!signingIn)
            ContextMenuAction(text: libL10n.login, icon: Icons.login, onTap: () => _signIn(name)),
        ],
        ContextMenuAction(text: libL10n.delete, icon: Icons.delete_outline, destructive: true, onTap: () => _removeServer(context, url)),
      ],
      title: url,
      at: at,
      sheet: at == null && isMobile,
    );
    final String subtitle;
    final Widget? trailing;
    if (signingIn) {
      subtitle = llmL10n.mcpSigningIn;
      trailing = Btn.text(text: libL10n.cancel, onTap: () => McpTools.cancelSignIn(name));
    } else if (on) {
      subtitle = [
        ?McpTools.labelOf(name),
        llmL10n.connectedFmt(McpTools.toolCounts[name] ?? 0),
        if (signedIn) llmL10n.mcpSignedInShort,
      ].join(' · ');
      trailing = null;
    } else if (needsSignIn && secure) {
      subtitle = [llmL10n.mcpNeedsSignIn, ?err].join(' · ');
      trailing = Btn.text(text: libL10n.login, onTap: () => _signIn(name));
    } else {
      subtitle = [llmL10n.disconnected, if (needsSignIn) llmL10n.mcpInsecure, ?err].join(' · ');
      trailing = Btn.text(text: libL10n.retry, onTap: () => _run(() => McpTools.retryConnection(name)));
    }
    return SettingsRow(
      leading: RowDot(on ? StateColors.running : StateColors.failed),
      title: url.replaceFirst(RegExp(r'^https?://'), ''),
      mono: true,
      subtitle: subtitle,
      trailing: trailing,
      onTap: menu,
      onLongPress: menu,
    ).onSecondary(menu);
  }

  /// [f], then the chats' tools again.
  static Future<void> _run(Future<void> Function() f) async {
    try {
      await f();
    } catch (e, s) {
      Loggers.app.warning('MCP', e, s);
      Toast.error('$e');
    }
    Chats.reconfigureSoon();
  }

  static Future<void> _signIn(String name) => _run(() async {
    await McpTools.signIn(name, open: _openBrowser);
    await _closeBrowser();
  });

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

  /// The headers as a text field: `Name: value`, a line each.
  static Widget _headersInput(TextEditingController ctrl) => Input(
    controller: ctrl,
    label: llmL10n.mcpHeaders,
    hint: 'Authorization: Bearer …',
    maxLines: 4,
    minLines: 2,
    type: TextInputType.multiline,
    noWrap: true,
  );

  /// The headers in [text], or null after saying why they are not.
  static Map<String, String>? _parseHeaders(String text, String url) {
    final headers = McpSecret.parseHeaders(text);
    if (headers == null) {
      Toast.warn(llmL10n.mcpHeadersInvalid);
      return null;
    }
    if (headers.isNotEmpty && !McpAuth.canCarrySecrets(url)) {
      Toast.warn(llmL10n.mcpInsecure);
      return null;
    }
    return headers;
  }

  Future<void> _addServer(BuildContext context) async {
    final urlCtrl = TextEditingController();
    final headersCtrl = TextEditingController();
    final ok = await context.showRoundDialog<bool>(
      title: llmL10n.addServer,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Input(controller: urlCtrl, autoFocus: true, hint: 'https://mcp.example.net/mcp', type: TextInputType.url),
          _headersInput(headersCtrl),
          Text(llmL10n.mcpHeadersTip, style: UIs.text12Grey),
        ],
      ),
      actions: [Btn.ok(onTap: () => context.pop(true))],
    );
    final u = urlCtrl.text.trim();
    final headersText = headersCtrl.text;
    urlCtrl.dispose();
    headersCtrl.dispose();
    if (ok != true || u.isEmpty || !context.mounted) return;
    if (_store.mcpServers.get().contains(u)) return;
    final headers = _parseHeaders(headersText, u);
    if (headers == null) return;
    final name = McpTools.nameFor(u);
    // Before connecting, so the first request carries them.
    McpSecrets.write(name, McpSecret(headers: headers));
    // Stored first: a server that is down now is still one the user added,
    // and it shows as disconnected with a retry.
    _store.mcpServers.set([..._store.mcpServers.get(), u]);
    if (!context.mounted) return;
    await context.showLoadingDialog(fn: () => McpTools.connect(u));
    // Just added by a tap, so the browser may open without another one.
    if (McpTools.needsSignIn(name) && McpAuth.canCarrySecrets(u)) {
      await _signIn(name);
    } else {
      Chats.reconfigureSoon();
    }
  }

  Future<void> _editHeaders(BuildContext context, String url) async {
    final name = McpTools.nameFor(url);
    final ctrl = TextEditingController(text: McpSecret.formatHeaders(McpTools.headersOf(name)));
    final ok = await context.showRoundDialog<bool>(
      title: llmL10n.mcpHeaders,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _headersInput(ctrl),
          Text(llmL10n.mcpHeadersTip, style: UIs.text12Grey),
        ],
      ),
      actions: [Btn.ok(onTap: () => context.pop(true))],
    );
    final text = ctrl.text;
    ctrl.dispose();
    if (ok != true) return;
    final headers = _parseHeaders(text, url);
    if (headers == null) return;
    await _run(() => McpTools.setHeaders(name, headers));
  }

  Future<void> _removeServer(BuildContext context, String url) async {
    final ok = await context.showRoundDialog<bool>(
      title: libL10n.delete,
      child: Text(libL10n.askContinue('${libL10n.delete} $url')),
      actions: Btnx.cancelRedOk,
    );
    if (ok != true) return;
    _store.mcpServers.set([..._store.mcpServers.get().where((e) => e != url)]);
    try {
      await McpTools.removeServer(McpTools.nameFor(url));
    } catch (e, s) {
      Loggers.app.warning('Remove MCP server', e, s);
    }
    Chats.reconfigureSoon();
  }

  Future<void> _editPermitted(BuildContext context, List<String> list) async {
    await context.showRoundDialog(
      title: llmL10n.allowedWithoutAsking,
      child: _store.permittedTools.listenable().listenVal((now) {
        if (now.isEmpty) return Text(libL10n.empty, style: UIs.textGrey);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final name in now)
              ListTile(
                title: Text(Tools.labelOf(name)),
                trailing: Btn.icon(
                  icon: const Icon(Icons.close, size: 19),
                  text: libL10n.delete,
                  onTap: () => _store.permittedTools.set([...now.where((e) => e != name)]),
                ),
              ),
          ],
        );
      }),
      actions: Btnx.oks,
    );
  }
}
