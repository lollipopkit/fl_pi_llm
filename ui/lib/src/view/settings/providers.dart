import 'package:fl_lib/fl_lib.dart';
import 'package:fl_pi_llm/fl_pi_llm.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fl_pi_llm_ui/src/core/chats.dart';
import 'package:fl_pi_llm_ui/src/core/llm.dart';
import 'package:fl_pi_llm_ui/src/res/l10n.dart';
import 'package:fl_pi_llm_ui/src/store/stores.dart';
import 'package:fl_pi_llm_ui/src/view/model_picker.dart';
import 'package:fl_pi_llm_ui/src/view/settings/custom_provider.dart';
import 'package:fl_pi_llm_ui/src/view/settings/provider.dart';
import 'package:fl_pi_llm_ui/src/config.dart';
import 'package:fl_pi_llm_ui/src/view/section_list.dart';
import 'package:shortid/shortid.dart';

/// Providers, their keys, and which models to use by default.
///
/// The catalog is pi-ai's. A key goes into the system keychain; a provider
/// without one is listed but offers no models. Custom providers and the ones
/// with a key always come first.
class ProvidersPage extends StatefulWidget {
  const ProvidersPage({super.key});

  /// Opens a provider — [id], or '' for a new custom one: where the app
  /// shows it ([LlmUi.showProvider]), else pushed.
  static void open(BuildContext context, String id) {
    if (LlmUi.showProvider(context, id)) return;
    final spec = LlmStores.llm.customProviders.get()?.firstWhereOrNull((e) => e.id == id);
    if (id.isEmpty || spec != null) {
      CustomProviderPage.route.go(context, args: spec);
    } else {
      ProviderPage.route.go(context, args: id);
    }
  }

  /// The page for provider [id] ('' for a new custom one), in the settings'
  /// content area.
  static Widget detail(String id, {required VoidCallback onBack}) {
    final spec = LlmStores.llm.customProviders.get()?.firstWhereOrNull((e) => e.id == id);
    if (id.isEmpty || spec != null) return CustomProviderPage(key: ValueKey(id), args: spec, onBack: onBack);
    return ProviderPage(key: ValueKey(id), args: id, onBack: onBack);
  }

  /// Opens the custom provider a deep link describes, prefilled; nothing is
  /// stored until the user saves it. A link never carries a key.
  static Future<void> addFromLink(BuildContext context, Map<String, String> p) async {
    final name = p['name'], baseUrl = p['baseUrl'];
    final api = LlmApi.fromWire(p['api']) ?? LlmApi.openaiCompletions;
    final models = [
      for (final m in (p['models'] ?? '').split(',')) if (m.trim().isNotEmpty) m.trim(),
    ];
    final uri = baseUrl == null ? null : Uri.tryParse(baseUrl);
    if (name == null || uri == null || !uri.isScheme('https') && !uri.isScheme('http')) {
      Toast.show(llmL10n.invalidLinkFmt(p.toString()));
      return;
    }
    await CustomProviderPage.route.go(
      context,
      args: LlmCustomProvider(
        id: 'custom_${shortid.generate()}',
        name: name,
        api: api,
        baseUrl: baseUrl!,
        models: models.isEmpty ? null : models,
      ),
    );
  }

  @override
  State<ProvidersPage> createState() => _ProvidersPageState();
}

class _ProvidersPageState extends State<ProvidersPage> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([Llm.providers, Llm.configured, Llm.modelErrors]),
      builder: (context, _) {
        final q = _query.text.trim().toLowerCase();
        bool matches(LlmProviderInfo p) => q.isEmpty || p.name.toLowerCase().contains(q) || p.id.contains(q);
        bool pinned(LlmProviderInfo p) => p.custom || Llm.configured.value.contains(p.id);
        final all = Llm.providers.value;
        final top = [
          for (final p in all) if (p.custom) p,
          for (final p in all) if (!p.custom && pinned(p)) p,
        ];
        return SectionList(
          children: [
            _models(),
            SettingsGroup(
              title: libL10n.configured,
              rows: top.isEmpty
                  ? [SettingsRow(icon: Icons.key_off_outlined, title: llmL10n.noProviderKey, muted: true)]
                  : [for (final p in top) _tile(p)],
            ),
            SettingsGroup(
              title: llmL10n.allProviders,
              header: Input(
                controller: _query,
                hint: llmL10n.searchProviders,
                icon: Icons.search,
                onChanged: (_) => setState(() {}),
              ),
              rows: [
                SettingsRow(
                  icon: Icons.add,
                  title: llmL10n.customProvider,
                  onTap: () => ProvidersPage.open(context, ''),
                ),
                for (final p in all)
                  if (!pinned(p) && matches(p)) _tile(p),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _models() {
    String nameOf(LlmModelRef? r) => r == null ? libL10n.empty : Llm.info(r)?.name ?? r.toString();
    final prompt = LlmStores.llm.systemPrompt.get();
    return SettingsGroup(
      title: llmL10n.model,
      rows: [
        SettingsRow(
          icon: Icons.auto_awesome,
          title: llmL10n.defaultModel,
          subtitle: nameOf(Llm.defaultModel),
          trailing: const RowChevron(),
          onTap: () async {
            final m = await pickModel(context, current: Llm.defaultModel);
            if (m == null) return;
            LlmStores.llm.defaultModel.set(m);
            if (mounted) setState(() {});
          },
        ),
        SettingsRow(
          icon: Icons.title,
          title: llmL10n.titleModel,
          subtitle: LlmStores.llm.titleModel.get() == null ? llmL10n.sameAsChat : nameOf(LlmStores.llm.titleModel.get()),
          // Back to the chat's own model: a button, as a long press is not
          // found on a computer.
          trailing: LlmStores.llm.titleModel.get() == null
              ? const RowChevron()
              : Btn.icon(
                  icon: const Icon(Icons.close, size: 17),
                  text: llmL10n.sameAsChat,
                  onTap: () => setState(() => LlmStores.llm.titleModel.remove()),
                ),
          onTap: () async {
            final m = await pickModel(context, current: LlmStores.llm.titleModel.get());
            if (m == null) return;
            LlmStores.llm.titleModel.set(m);
            if (mounted) setState(() {});
          },
        ),
        SettingsRow(
          icon: Icons.notes,
          title: llmL10n.systemPrompt,
          subtitle: prompt.isEmpty ? libL10n.empty : prompt.replaceAll('\n', ' '),
          trailing: const RowChevron(),
          onTap: _editSystemPrompt,
        ),
        SettingsRow(
          icon: Icons.compress,
          title: llmL10n.compaction,
          subtitle: llmL10n.compactionTip,
          trailing: StoreSwitch(prop: LlmStores.llm.compaction, callback: (_) => Chats.reconfigure()),
        ),
      ],
    );
  }

  Future<void> _editSystemPrompt() async {
    final ctrl = TextEditingController(text: LlmStores.llm.systemPrompt.get());
    final v = await context.showRoundDialog<String>(
      title: llmL10n.systemPrompt,
      child: SizedBox(width: 520, child: Input(controller: ctrl, maxLines: 12, minLines: 4, autoFocus: true)),
      actions: [Btn.ok(onTap: () => context.popDialog(ctrl.text))],
    );
    ctrl.dispose();
    if (v == null) return;
    LlmStores.llm.systemPrompt.set(v);
    await Chats.reconfigure();
    if (mounted) setState(() {});
  }

  Widget _tile(LlmProviderInfo p) {
    final has = Llm.configured.value.contains(p.id);
    return SettingsRow(
      icon: has ? Icons.key : Icons.key_off_outlined,
      iconColor: has ? context.theme.colorScheme.primary : null,
      title: p.name,
      subtitle: [if (p.custom) p.baseUrl ?? '' else p.id, llmL10n.modelsCountFmt(p.models.length)].join(' · '),
      error: Llm.modelErrors.value[p.id],
      trailing: p.custom
          ? Btn.icon(
              icon: const Icon(Icons.edit_outlined, size: 19),
              text: libL10n.edit,
              onTap: () => ProvidersPage.open(context, p.id),
            )
          : const RowChevron(),
      onTap: () => ProvidersPage.open(context, p.id),
    );
  }
}

/// A model as its rows describe it: `id · 200K · thinking · image`.
String modelSubtitle(LlmModelInfo m) {
  final w = m.contextWindow;
  final ctx = w >= 1000000
      ? '${(w / 1000000).toStringAsFixed(w % 1000000 == 0 ? 0 : 1)}M'
      : w >= 1000
      ? '${(w / 1000).round()}K'
      : '$w';
  return [m.id, ctx, if (m.reasoning) llmL10n.supportsThinking.toLowerCase(), if (m.imageInput) llmL10n.image.toLowerCase()].join(' · ');
}

/// A favorite star at the end of a model's row.
class FavoriteStar extends StatelessWidget {
  const FavoriteStar({super.key, required this.model});

  final LlmModelRef model;

  @override
  Widget build(BuildContext context) {
    return LlmStores.llm.favoriteModels.listenable().listenVal((favs) {
      final key = model.toString();
      final on = favs.contains(key);
      return Btn.icon(
        icon: Icon(
          on ? Icons.star_rounded : Icons.star_outline_rounded,
          size: 20,
          color: on ? context.theme.colorScheme.primary : UIs.textGrey.color,
        ),
        text: llmL10n.favorite,
        onTap: () => LlmStores.llm.favoriteModels.set(on ? [...favs.where((e) => e != key)] : [...favs, key]),
      );
    });
  }
}
