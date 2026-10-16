import 'dart:async';

import 'package:fl_lib/fl_lib.dart';
import 'package:fl_pi_llm_ui/src/core/chats.dart';
import 'package:fl_pi_llm_ui/src/res/l10n.dart';
import 'package:fl_pi_llm_ui/src/store/stores.dart';
import 'package:fl_pi_llm_ui/src/tools/tool.dart';
import 'package:fl_pi_llm_ui/src/view/section_list.dart';
import 'package:fl_pi_llm_ui/src/view/settings/mcp_server.dart';
import 'package:fl_pi_llm_ui/src/view/settings/memory.dart';
import 'package:material_ui/material_ui.dart';

/// Tools: the switch, the built-in ones, and the MCP servers.
class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key});

  static final _store = LlmStores.tool;

  static IconData _iconOf(ToolFunc t) => switch (t) {
    ToolFunc(:final groupIcon?) => groupIcon,
    ToolFunc(:final icon?) => icon,
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
              trailing: StoreSwitch(
                prop: _store.enabled,
                callback: (on) {
                  // Not connected at launch while off.
                  if (on) unawaited(McpTools.connectStored());
                  Chats.reconfigureSoon();
                },
              ),
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
                SettingsRow(icon: Icons.add, title: llmL10n.addServer, onTap: () => McpServerPage.route.go(context)),
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
    final String subtitle;
    final Widget? trailing;
    if (McpTools.isConnecting(name)) {
      subtitle = llmL10n.mcpConnecting;
      trailing = null;
    } else if (McpTools.isSigningIn(name)) {
      subtitle = llmL10n.mcpSigningIn;
      trailing = Btn.text(text: libL10n.cancel, onTap: () => McpTools.cancelSignIn(name));
    } else if (on) {
      subtitle = [
        ?McpTools.labelOf(name),
        llmL10n.connectedFmt(McpTools.toolCounts[name] ?? 0),
        if (McpTools.isSignedIn(name)) llmL10n.mcpSignedInShort,
      ].join(' · ');
      trailing = null;
    } else if (McpTools.needsSignIn(name) && McpAuth.canCarrySecrets(url)) {
      subtitle = llmL10n.mcpNeedsSignIn;
      trailing = Btn.text(text: libL10n.login, onTap: () => McpServerPage.signIn(name));
    } else {
      subtitle = [llmL10n.disconnected, ?err].join(' · ');
      trailing = Btn.text(
        text: libL10n.retry,
        onTap: () async {
          await McpTools.retryConnection(url);
          Chats.reconfigureSoon();
        },
      );
    }
    return SettingsRow(
      leading: RowDot(on ? StateColors.running : StateColors.failed),
      title: url.replaceFirst(RegExp(r'^https?://'), ''),
      mono: true,
      subtitle: subtitle,
      trailing: trailing,
      onTap: () => McpServerPage.route.go(context, args: url),
    );
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
