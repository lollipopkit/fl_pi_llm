import 'package:fl_lib/fl_lib.dart';
import 'package:fl_pi_llm/fl_pi_llm.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fl_pi_llm_ui/src/core/llm.dart';
import 'package:fl_pi_llm_ui/src/res/l10n.dart';
import 'package:fl_pi_llm_ui/src/store/stores.dart';
import 'package:fl_pi_llm_ui/src/view/settings/providers.dart';
import 'package:fl_pi_llm_ui/src/config.dart';
import 'package:fl_pi_llm_ui/src/view/section_list.dart';

/// Picks a model among those whose provider has a key, favorites first, then
/// by provider. A dialog on a wide window, a sheet on a phone. Offers the
/// provider settings, in a toast, when there is nothing to pick.
Future<LlmModelRef?> pickModel(BuildContext context, {LlmModelRef? current}) async {
  if (Llm.usableModels.isEmpty) {
    final open = LlmUi.openProviders;
    Toast.warn(
      llmL10n.noProviderKey,
      tag: 'llm.noProviderKey',
      action: open == null
          ? null
          : ToastAction(
              label: llmL10n.configure,
              onTap: () {
                if (context.mounted) open(context);
              },
            ),
    );
    return null;
  }
  if (MediaQuery.sizeOf(context).width >= AdaptivePanes.kSplitWidth) {
    return showDialog<LlmModelRef>(
      context: context,
      builder: (ctx) => Dialog(
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(borderRadius: CardX.borderRadius),
        child: SizedBox(
          width: 500,
          height: 580,
          child: ColoredBox(color: context.theme.colorScheme.surfaceContainerHigh, child: _ModelSheet(current: current)),
        ),
      ),
    );
  }
  return showModalBottomSheet<LlmModelRef>(
    context: context,
    // Over the app's nav bar rather than above it, when opened from a tab
    // with a navigator of its own.
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    // The theme's sheet — its colour, corners and handle — as the app's other
    // tall sheets are. A colour of its own here covered the corners, which a
    // sheet does not clip to.
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(heightFactor: 0.82, child: _ModelSheet(current: current)),
  );
}

class _ModelSheet extends StatefulWidget {
  const _ModelSheet({required this.current});

  final LlmModelRef? current;


  @override
  State<_ModelSheet> createState() => _ModelSheetState();
}

class _ModelSheetState extends State<_ModelSheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([Llm.providers, Llm.configured, LlmStores.llm.favoriteModels.listenable()]),
      builder: (context, _) {
        final models = Llm.usableModels;
        final favs = LlmStores.llm.favoriteModels.get().toSet();
        final q = _query.text.trim().toLowerCase();
        final shown = [
          for (final m in models)
            if (q.isEmpty || m.id.toLowerCase().contains(q) || m.name.toLowerCase().contains(q)) m,
        ];
        final byProvider = <String, List<LlmModelInfo>>{};
        for (final m in shown) {
          if (favs.contains(m.ref.toString())) continue;
          (byProvider[m.provider] ??= []).add(m);
        }
        final favorites = [for (final m in shown) if (favs.contains(m.ref.toString())) m];
        final providers = models.map((m) => m.provider).toSet().length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(13, 13, 13, 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(
                          child: Text(llmL10n.model, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
                        ),
                        Text(
                          llmL10n.usableModelsFmt(models.length, providers),
                          style: UIs.text12Grey.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 9),
                  Input(
                    controller: _query,
                    hint: llmL10n.searchModels,
                    icon: Icons.search,
                    autoFocus: isDesktop,
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(7, 0, 7, 13),
                children: [
                  if (favorites.isNotEmpty) ..._group(llmL10n.favorite, favorites, favs),
                  for (final MapEntry(key: pid, value: list) in byProvider.entries)
                    ..._group(Llm.provider(pid)?.name ?? pid, list, favs),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _group(String title, List<LlmModelInfo> models, Set<String> favs) => [
    GroupTitle(title, padding: const EdgeInsets.fromLTRB(10, 13, 10, 5)),
    for (final m in models) _row(m),
  ];

  Widget _row(LlmModelInfo m) {
    final scheme = context.theme.colorScheme;
    final sel = m.ref == widget.current;
    return Material(
      color: sel ? scheme.secondaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () => Navigator.of(context).pop(m.ref),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(11, 4, 3, 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        height: 20 / 14,
                        fontWeight: sel ? FontWeight.w500 : FontWeight.w400,
                        color: sel ? scheme.onSecondaryContainer : null,
                      ),
                    ),
                    Text(
                      modelSubtitle(m),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: UIs.text12Grey.copyWith(height: 16 / 12),
                    ),
                  ],
                ),
              ),
              if (sel) Icon(Icons.check, size: 20, color: scheme.onSecondaryContainer),
              FavoriteStar(model: m.ref),
            ],
          ),
        ),
      ),
    );
  }
}
