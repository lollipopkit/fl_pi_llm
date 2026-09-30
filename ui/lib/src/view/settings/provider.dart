import 'dart:async';

import 'package:fl_lib/fl_lib.dart';
import 'package:fl_pi_llm/fl_pi_llm.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fl_pi_llm_ui/src/core/llm.dart';
import 'package:fl_pi_llm_ui/src/res/l10n.dart';
import 'package:fl_pi_llm_ui/src/view/settings/providers.dart';
import 'package:fl_pi_llm_ui/src/view/section_list.dart';

/// A provider of pi-ai's catalog: its key, and its models.
class ProviderPage extends StatefulWidget {
  const ProviderPage({super.key, this.args, this.onBack});

  /// The provider's id.
  final String? args;

  /// Back to the list, where this is shown in its place. Pushed, the route
  /// is popped instead.
  final VoidCallback? onBack;

  static const route = AppRoute<void, String>(page: ProviderPage.new, path: '/provider');

  @override
  State<ProviderPage> createState() => _ProviderPageState();
}

class _ProviderPageState extends State<ProviderPage> {
  late final String _id = widget.args ?? '';
  final _key = TextEditingController();
  final _env = TextEditingController();
  var _stored = false;
  var _allModels = false;

  /// Shown before "N more".
  static const _shownModels = 5;

  @override
  void initState() {
    super.initState();
    Llm.readCredential(_id).then((c) {
      if (!mounted || c == null) return;
      setState(() => _stored = true);
      _key.text = c.key ?? '';
      _env.text = c.env?.entries.map((e) => '${e.key}=${e.value}').join('\n') ?? '';
    });
  }

  @override
  void dispose() {
    _key.dispose();
    _env.dispose();
    super.dispose();
  }

  void _back() => widget.onBack != null ? widget.onBack!() : context.pop();

  Future<void> _save() async {
    final key = _key.text.trim();
    if (key.isEmpty) {
      Toast.show(libL10n.empty);
      return;
    }
    final vars = <String, String>{
      for (final line in _env.text.split('\n'))
        if (line.contains('=')) line.substring(0, line.indexOf('=')).trim(): line.substring(line.indexOf('=') + 1).trim(),
    };
    await Llm.setCredential(_id, LlmCredential.apiKey(key, env: vars.isEmpty ? null : vars));
    if (mounted) setState(() => _stored = true);
    Toast.success(libL10n.success);
    unawaited(_refresh());
  }

  Future<void> _deleteKey() async {
    final ok = await context.showRoundDialog<bool>(
      title: llmL10n.deleteKey,
      child: Text(libL10n.askContinue(llmL10n.deleteKey)),
      actions: Btnx.cancelRedOk,
    );
    if (ok != true) return;
    await Llm.setCredential(_id, null);
    _key.clear();
    _env.clear();
    if (mounted) setState(() => _stored = false);
  }

  /// Lists the models again; a failure is shown.
  Future<void> _refresh() async {
    final err = (await Llm.refresh(only: [_id]))[_id];
    if (err != null) Toast.show(err);
  }

  @override
  Widget build(BuildContext context) {
    final body = Llm.providers.listenVal((_) {
      final p = Llm.provider(_id);
      final models = p?.models ?? const <LlmModelInfo>[];
      final shown = _allModels ? models : models.take(_shownModels).toList();
      return DetailPage(
        embedded: widget.onBack != null,
        header: () => ProviderHeader(
          title: p?.name ?? _id,
          subtitle: [_id, ?(models.firstOrNull?.json['api'] as String?), llmL10n.modelsCountFmt(models.length)].join(' · '),
          onBack: _back,
          onRefresh: _refresh,
        ),
        children: [
          SettingsGroup(
            title: llmL10n.key,
            header: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Input(controller: _key, label: libL10n.apiKey, obscureText: true),
                Padding(
                  padding: const EdgeInsets.fromLTRB(13, 0, 13, 6),
                  child: Text(
                    switch (Llm.envAuth.value[_id]) {
                      final name? => '${llmL10n.keyFromEnvTipFmt(name)} ${llmL10n.keyInKeychain}',
                      null => llmL10n.keyInKeychain,
                    },
                    style: UIs.text12Grey,
                  ),
                ),
                Input(controller: _env, label: llmL10n.extraVars, hint: llmL10n.extraVarsTip, maxLines: 3, minLines: 1),
              ],
            ),
          ),
          SettingsGroup(
            title: '${llmL10n.model} · ${models.length}',
            rows: [
              for (final m in shown)
                SettingsRow(title: m.name, subtitle: modelSubtitle(m), trailing: FavoriteStar(model: m.ref)),
              if (!_allModels && models.length > _shownModels)
                SettingsRow(
                  icon: Icons.expand_more,
                  title: llmL10n.moreFmt(models.length - _shownModels),
                  muted: true,
                  onTap: () => setState(() => _allModels = true),
                ),
            ],
            footer: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_stored)
                  Btn.text(
                    text: llmL10n.deleteKey,
                    textStyle: TextStyle(color: context.theme.colorScheme.error),
                    onTap: _deleteKey,
                  ),
                Btn.text(text: libL10n.save, onTap: _save),
              ],
            ),
          ),
        ],
      );
    });
    return body;
  }
}

/// A provider's or an MCP server's page, under [header].
///
/// [embedded] — in the list's place, where the app puts it — the header is a
/// row above the content, as wide as it. Pushed, it is the app bar, across
/// the window like every other page's, with the route's own back button.
class DetailPage extends StatelessWidget {
  const DetailPage({super.key, required this.header, required this.children, required this.embedded, this.listenable});

  /// Built again when [listenable] notifies.
  final ProviderHeader Function() header;
  final Listenable? listenable;
  final List<Widget> children;
  final bool embedded;

  Widget _header(Widget Function(ProviderHeader) build) => listenable == null
      ? build(header())
      : ListenableBuilder(listenable: listenable!, builder: (_, _) => build(header()));

  @override
  Widget build(BuildContext context) {
    if (embedded) return SectionList(header: _header((h) => h), children: children);
    final refresh = header().onRefresh;
    return Scaffold(
      appBar: CustomAppBar(
        title: _header(
          (h) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(h.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(h.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: UIs.text12Grey),
            ],
          ),
        ),
        actions: [
          if (refresh != null) IconButton(icon: const Icon(Icons.refresh), tooltip: llmL10n.refreshModels, onPressed: refresh),
        ],
      ),
      body: SafeArea(top: false, child: SectionList(children: children)),
    );
  }
}

/// The title row of a provider's page: back, its name and what it is, and a
/// refresh of its models.
class ProviderHeader extends StatelessWidget {
  const ProviderHeader({super.key, required this.title, required this.subtitle, this.onBack, this.onRefresh});

  final String title;
  final String subtitle;
  final VoidCallback? onBack;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (onBack != null)
          Btn.icon(icon: const Icon(Icons.arrow_back, size: 24), text: llmL10n.back, onTap: onBack),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 17, height: 24 / 17, fontWeight: FontWeight.w500),
                ),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: UIs.text12Grey),
              ],
            ),
          ),
        ),
        if (onRefresh != null)
          Btn.icon(icon: const Icon(Icons.refresh, size: 18), text: llmL10n.refreshModels, onTap: onRefresh),
      ].joinWith(const SizedBox(width: 7)),
    );
  }
}
