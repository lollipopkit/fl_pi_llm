// ignore_for_file: invalid_use_of_protected_member

import 'dart:convert';

import 'package:fl_lib/fl_lib.dart';
import 'package:fl_pi_llm/fl_pi_llm.dart';
import 'package:fl_pi_llm_ui/src/core/permissions.dart';
import 'package:fl_pi_llm_ui/src/res/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// Where the permissions a [PermissionsPage] edits are kept. The page
/// disposes it.
abstract class PermissionsSource {
  Future<LlmPermissionsView> load();

  /// Answers what was kept.
  Future<LlmPermissionsView> save(LlmPermissions p);

  void dispose() {}
}

/// This app's own, for its chats ([LlmApprovals]).
final class LocalPermissionsSource extends PermissionsSource {
  @override
  Future<LlmPermissionsView> load() async =>
      LlmPermissionsView(permissions: LlmApprovals.stored, defaults: LlmApprovals.defaults);

  @override
  Future<LlmPermissionsView> save(LlmPermissions p) async {
    LlmApprovals.store(p);
    return load();
  }
}

/// [mode] as the person reads it.
String permissionModeLabel(LlmPermissionMode mode) => switch (mode) {
  LlmPermissionMode.auto => llmL10n.permModeAuto,
  LlmPermissionMode.bypass => llmL10n.permModeBypass,
  LlmPermissionMode.manual => llmL10n.permModeManual,
};

IconData permissionModeIcon(LlmPermissionMode mode) => switch (mode) {
  LlmPermissionMode.auto => Icons.auto_mode,
  LlmPermissionMode.bypass => Icons.bolt,
  LlmPermissionMode.manual => Icons.rule,
};

/// How tool calls are approved — the mode new chats or tasks run in, the
/// command rules and the auto mode judge's — wherever [PermissionsSource]
/// keeps them: this app's ([LocalPermissionsSource]) or an agent's a host
/// reaches. One page for both: both decide by [LlmPermissionRules].
final class PermissionsPage extends StatefulWidget {
  final PermissionsSource args;

  const PermissionsPage({super.key, required this.args});

  @override
  State<PermissionsPage> createState() => _PermissionsPageState();
}

final class _PermissionsPageState extends State<PermissionsPage> {
  LlmPermissionsView? _view;
  Object? _err;
  bool _saving = false;

  /// Null while the agent's mode is one this app does not know.
  LlmPermissionMode? _mode;
  var _disableBypass = false;
  final _deny = TextEditingController();
  final _ask = TextEditingController();
  final _allow = TextEditingController();
  final _auto = {for (final k in LlmAutoRuleKind.values) k: TextEditingController()};
  LlmAutoRuleKind? _shown;

  /// What the agent last answered, as it would be sent: the form is dirty
  /// exactly when it would send something else.
  String? _saved;

  Iterable<TextEditingController> get _ctrls => [_deny, _ask, _allow, ..._auto.values];

  bool get _dirty => _saved != null && jsonEncode(_collect().toJson()) != _saved;

  @override
  void initState() {
    super.initState();
    for (final c in _ctrls) {
      c.addListener(_changed);
    }
    _load();
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    widget.args.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return PopGuard(
      enabled: _dirty,
      confirm: () => _confirmDiscard(context),
      child: Scaffold(
        appBar: CustomAppBar(
          title: Text(llmL10n.permTitle),
          actions: [
            if (_view != null)
              if (_saving)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                IconButton(
                  tooltip: libL10n.save,
                  icon: const Icon(Icons.save),
                  onPressed: _save,
                ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final err = _err;
    if (_view == null && err != null) {
      return PageIssueView(title: libL10n.error, detail: '$err', onRetry: _load);
    }
    final view = _view;
    if (view == null) return UIs.centerLoading;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: PageColumns.columnWidth),
        child: ListView(
          padding: const EdgeInsets.only(left: 7, right: 7, top: 7, bottom: 27),
          children: [
        _buildMode(),
        CenterGreyTitle(llmL10n.permRules),
        _buildRules(),
        CenterGreyTitle(llmL10n.permAutoRules),
        _buildAuto(view),
          ],
        ),
      ),
    );
  }

  Widget _buildMode() {
    final note = switch (_mode) {
      LlmPermissionMode.manual => llmL10n.permManualNote,
      LlmPermissionMode.auto => llmL10n.permAutoNote,
      LlmPermissionMode.bypass => llmL10n.permBypassNote,
      null => null,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          title: Text(llmL10n.permDefaultMode),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedTabs<LlmPermissionMode?>(
                  expand: true,
                  segments: [
                    for (final m in LlmPermissionMode.values)
                      if (m != LlmPermissionMode.bypass || !_disableBypass)
                        SegmentedTab(value: m, label: permissionModeLabel(m), icon: permissionModeIcon(m)),
                  ],
                  // A mode this build does not know shows as none of these
                  // until one is picked, and is kept until then.
                  selected: _mode,
                  onSelected: (m) {
                    if (m != null) setState(() => _mode = m);
                  },
                ),
                if (note != null) ...[
                  UIs.height7,
                  Text(note, style: UIs.textGrey),
                ],
              ],
            ),
          ),
        ).cardx,
        ListTile(
          title: Text(llmL10n.permDisableBypass),
          subtitle: Text(llmL10n.permDisableBypassSub, style: UIs.textGrey),
          trailing: Switch(
            value: _disableBypass,
            onChanged: (v) => setState(() {
              _disableBypass = v;
              if (v && _mode == LlmPermissionMode.bypass) _mode = LlmPermissionMode.manual;
            }),
          ),
        ).cardx,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 7),
          child: Text(llmL10n.permDangerAsks, style: UIs.text12Grey),
        ),
      ],
    );
  }

  Widget _buildRules() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _lines(_deny, llmL10n.permDeny, 'rm -rf *'),
        _lines(_ask, llmL10n.permAsk, 'systemctl stop *'),
        _lines(_allow, llmL10n.permAllow, 'systemctl restart nginx'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 7),
          child: Text(llmL10n.permRulesHint, style: UIs.text12Grey),
        ),
      ],
    );
  }

  Widget _buildAuto(LlmPermissionsView view) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 7),
          child: Text(llmL10n.permAutoHint, style: UIs.text12Grey),
        ),
        for (final k in LlmAutoRuleKind.values) ...[
          _lines(_auto[k]!, _autoLabel(k), llmL10n.permBuiltIn),
          _buildDefaults(k, view.defaults[k] ?? const []),
        ],
      ],
    );
  }

  Widget _buildDefaults(LlmAutoRuleKind k, List<String> defaults) {
    final shown = _shown == k;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7),
          child: Btn.text(
            text: llmL10n.permShowDefaults(defaults.length),
            textStyle: UIs.text13Grey,
            onTap: () => setState(() => _shown = shown ? null : k),
          ),
        ),
        if (shown)
          Padding(
            padding: const EdgeInsets.fromLTRB(17, 0, 17, 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final d in defaults)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text('· $d', style: UIs.text12Grey),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _lines(TextEditingController ctrl, String label, String hint) {
    return Input(
      controller: ctrl,
      label: label,
      hint: hint,
      minLines: 2,
      maxLines: 8,
      type: TextInputType.multiline,
      action: TextInputAction.newline,
      suggestion: false,
      autoCorrect: false,
    );
  }

  String _autoLabel(LlmAutoRuleKind k) => switch (k) {
    LlmAutoRuleKind.environment => llmL10n.permEnvironment,
    LlmAutoRuleKind.allow => llmL10n.permAllow,
    LlmAutoRuleKind.softDeny => llmL10n.permSoftDeny,
    LlmAutoRuleKind.hardDeny => llmL10n.permHardDeny,
  };
}

Future<bool> _confirmDiscard(BuildContext context) async {
  final ok = await context.showRoundDialog<bool>(
    title: libL10n.attention,
    child: Text(llmL10n.discardUnsaved),
    actions: Btnx.cancelRedOk,
  );
  return ok == true;
}

extension on _PermissionsPageState {
  Future<void> _load() async {
    setState(() => _err = null);
    try {
      _fill(await widget.args.load());
    } catch (e) {
      if (mounted) setState(() => _err = e);
    }
  }

  void _fill(LlmPermissionsView view) {
    final p = view.permissions;
    if (!mounted) return;
    setState(() {
      _view = view;
      _mode = p.defaultMode;
      _disableBypass = p.disableBypass;
      _deny.text = p.deny.join('\n');
      _ask.text = p.ask.join('\n');
      _allow.text = p.allow.join('\n');
      for (final k in LlmAutoRuleKind.values) {
        _auto[k]!.text = (p.autoMode[k] ?? const []).join('\n');
      }
      _saved = jsonEncode(_collect().toJson());
    });
  }

  LlmPermissions _collect() {
    List<String> lines(TextEditingController c) => [
      for (final l in c.text.split('\n'))
        if (l.trim().isNotEmpty) l.trim(),
    ];
    final base = _view?.permissions ?? const LlmPermissions();
    return base.copyWith(
      defaultMode: _mode,
      disableBypass: _disableBypass,
      deny: lines(_deny),
      ask: lines(_ask),
      allow: lines(_allow),
      autoMode: {
        // Empty is the built-in list.
        for (final k in LlmAutoRuleKind.values)
          if (lines(_auto[k]!) case final l when l.isNotEmpty) k: l,
      },
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final sent = jsonEncode(_collect().toJson());
      final view = await widget.args.save(_collect());
      if (!mounted) return;
      if (jsonEncode(_collect().toJson()) == sent) {
        _fill(view);
      } else {
        // Edited while it saved: what was typed since stays, and still counts
        // as unsaved.
        setState(() {
          _view = view;
          _saved = sent;
        });
      }
      Toast.show(libL10n.success);
    } catch (e) {
      if (mounted) context.showErrDialog(e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
