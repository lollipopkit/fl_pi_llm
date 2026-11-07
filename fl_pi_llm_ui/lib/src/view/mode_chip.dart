import 'package:fl_lib/fl_lib.dart';
import 'package:fl_pi_llm/fl_pi_llm.dart';
import 'package:fl_pi_llm_ui/src/core/permissions.dart';
import 'package:fl_pi_llm_ui/src/res/l10n.dart';
import 'package:fl_pi_llm_ui/src/store/stores.dart';
import 'package:fl_pi_llm_ui/src/view/menu.dart';
import 'package:fl_pi_llm_ui/src/view/settings/permissions.dart';
import 'package:material_ui/material_ui.dart';

/// The mode new chats or tasks run in, under the message box: picking one
/// changes it for all of them, as the permissions page does.
class PermissionModeChip extends StatelessWidget {
  const PermissionModeChip({super.key, required this.mode, required this.bypassAllowed, required this.onPick});

  final LlmPermissionMode mode;
  final bool bypassAllowed;
  final void Function(LlmPermissionMode mode)? onPick;

  /// This app's own, for its chats.
  static Widget local() => LlmStores.tool.permissions.listenable().listenVal((_) {
    final p = LlmApprovals.stored;
    return PermissionModeChip(mode: p.mode, bypassAllowed: !p.disableBypass, onPick: LlmApprovals.pickMode);
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The default neutral, auto in the accent, allow-all a warning.
    final color = switch (mode) {
      LlmPermissionMode.auto => scheme.primary,
      LlmPermissionMode.bypass => scheme.error,
      LlmPermissionMode.manual => scheme.onSurfaceVariant,
    };
    final pick = onPick;
    return MenuBtn(
      actions: [
        for (final m in LlmPermissionMode.values)
          ContextMenuAction(
            text: permissionModeLabel(m),
            icon: permissionModeIcon(m),
            checked: m == mode,
            enabled: pick != null && (m != LlmPermissionMode.bypass || bypassAllowed),
            note: m == LlmPermissionMode.bypass && !bypassAllowed ? llmL10n.permModeBypassOff : null,
            onTap: () => pick?.call(m),
          ),
      ],
      builder: (toggle) => Tooltip(
        message: llmL10n.permMode,
        child: Btn.row(
          icon: Icon(permissionModeIcon(mode), size: 16, color: color),
          text: permissionModeLabel(mode),
          textStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color),
          mainAxisSize: MainAxisSize.min,
          onTap: toggle,
          padding: const EdgeInsets.all(5),
        ),
      ),
    );
  }
}
