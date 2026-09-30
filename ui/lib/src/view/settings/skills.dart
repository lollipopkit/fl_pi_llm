import 'package:file_picker/file_picker.dart';
import 'package:fl_lib/fl_lib.dart';
import 'package:fl_pi_llm_ui/src/core/chats.dart';
import 'package:fl_pi_llm_ui/src/res/l10n.dart';
import 'package:fl_pi_llm_ui/src/skills/discover.dart';
import 'package:fl_pi_llm_ui/src/skills/skills.dart';
import 'package:fl_pi_llm_ui/src/skills/source.dart';
import 'package:fl_pi_llm_ui/src/view/message.dart';
import 'package:fl_pi_llm_ui/src/view/section_list.dart';
import 'package:fl_pi_llm_ui/src/view/settings/provider.dart';
import 'package:material_ui/material_ui.dart';

/// The skills: installing one from where `npx skills add` would, and the
/// ones installed, each on or off.
class SkillsPage extends StatefulWidget {
  const SkillsPage({super.key});

  @override
  State<SkillsPage> createState() => _SkillsPageState();
}

class _SkillsPageState extends State<SkillsPage> {
  final _source = TextEditingController();

  /// Long enough for a repository's archive on a slow connection.
  static const _timeout = Duration(minutes: 2);

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  Future<void> _install() async {
    final SkillSource source;
    try {
      source = SkillSource.parse(_source.text);
    } on FormatException {
      Toast.warn(llmL10n.skillSourceInvalid);
      return;
    }
    if (await _installFrom(source)) _source.clear();
  }

  Future<void> _fromFolder() async {
    final dir = await FilePicker.getDirectoryPath();
    if (dir != null) await _installFrom(LocalSource(dir));
  }

  Future<void> _fromZip() async {
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['zip']);
    if (file?.path case final path?) await _installFrom(LocalSource(path));
  }

  /// Finds the skills in [source], asks which when there are several, and
  /// installs them. Whether it did.
  Future<bool> _installFrom(SkillSource source) async {
    if (!mounted) return false;
    final (found, err) = await context.showLoadingDialog(fn: () => Skills.find(source), timeout: _timeout);
    if (found == null || err != null || !mounted) return false;
    if (found.skills.isEmpty) {
      Toast.warn(llmL10n.skillsNotFound);
      return false;
    }
    final chosen = found.skills.length == 1 ? found.skills : await _pick(found.skills);
    if (chosen == null || chosen.isEmpty || !mounted) return false;
    final (_, err2) = await context.showLoadingDialog(
      fn: () async {
        for (final s in chosen) {
          await Skills.install(s, found.source);
        }
      },
      timeout: _timeout,
    );
    if (err2 != null) return false;
    Toast.success(llmL10n.skillsInstalledFmt(chosen.length));
    Chats.reconfigureSoon();
    return true;
  }

  /// Which of several to install; none ticked to begin with, as the CLI asks.
  Future<List<FoundSkill>?> _pick(List<FoundSkill> skills) {
    final picked = <FoundSkill>{};
    return context.showRoundDialog<List<FoundSkill>>(
      title: llmL10n.skillsPick,
      child: StatefulBuilder(
        builder: (context, setState) => SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                value: picked.length == skills.length ? true : (picked.isEmpty ? false : null),
                tristate: true,
                title: Text(libL10n.all),
                onChanged: (_) => setState(() {
                  picked.length == skills.length ? picked.clear() : picked.addAll(skills);
                }),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final s in skills)
                      CheckboxListTile(
                        value: picked.contains(s),
                        title: Text(s.name),
                        subtitle: Text(s.description, maxLines: 2, overflow: TextOverflow.ellipsis),
                        onChanged: (on) => setState(() => on == true ? picked.add(s) : picked.remove(s)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [Btn.ok(onTap: () => context.popDialog([for (final s in skills) if (picked.contains(s)) s]))],
    );
  }

  Future<void> _update() async {
    final (res, err) = await context.showLoadingDialog(fn: Skills.update, timeout: const Duration(minutes: 5));
    if (res == null || err != null) return;
    final (:updated, :failed) = res;
    if (failed.isNotEmpty) {
      Toast.warn(
        llmL10n.skillsUpdateFailedFmt(failed.length),
        body: [for (final MapEntry(:key, :value) in failed.entries) '$key: $value'].join('\n'),
      );
    }
    if (updated.isNotEmpty) {
      Toast.success(llmL10n.skillsUpdatedFmt(updated.length));
      Chats.reconfigureSoon();
    } else if (failed.isEmpty) {
      Toast.info(llmL10n.skillsUpToDate);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Skills.changes,
      builder: (context, _) {
        final all = Skills.all;
        return SectionList(
          children: [
            SettingsGroup(
              title: libL10n.install,
              header: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Input(
                    controller: _source,
                    hint: 'owner/repo · https://… · npx skills add …',
                    type: TextInputType.url,
                    onSubmitted: (_) => _install(),
                    suffix: Btn.icon(icon: const Icon(Icons.download, size: 19), text: libL10n.install, onTap: _install),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(13, 0, 13, 6),
                    child: Text(llmL10n.skillsTip, style: UIs.text12Grey),
                  ),
                ],
              ),
              rows: [
                SettingsRow(icon: Icons.folder_open_outlined, title: llmL10n.skillsFromFolder, onTap: _fromFolder),
                SettingsRow(icon: Icons.folder_zip_outlined, title: llmL10n.skillsFromZip, onTap: _fromZip),
              ],
            ),
            SettingsGroup(
              title: '${llmL10n.skills} · ${all.length}',
              rows: [
                if (all.isEmpty) SettingsRow(icon: Icons.auto_stories_outlined, title: libL10n.empty, muted: true),
                for (final s in all)
                  SettingsRow(
                    title: s.name,
                    subtitle: s.description,
                    trailing: SwitchX(
                      value: s.enabled,
                      onChanged: (on) {
                        Skills.setEnabled(s.dir, on);
                        Chats.reconfigureSoon();
                      },
                    ),
                    onTap: () => SkillPage.route.go(context, args: s.dir),
                  ),
                if (all.isNotEmpty) SettingsRow(icon: Icons.update, title: libL10n.checkUpdate, onTap: _update),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// One installed skill: where it came from, its files, and its SKILL.md.
class SkillPage extends StatelessWidget {
  const SkillPage({super.key, this.args});

  /// Its directory.
  final String? args;

  static const route = AppRoute<void, String>(page: SkillPage.new, path: '/skills/skill');

  Future<void> _delete(BuildContext context, InstalledSkill s) async {
    final ok = await context.showRoundDialog<bool>(
      title: libL10n.delete,
      child: Text(libL10n.askContinue('${libL10n.delete} ${s.name}')),
      actions: Btnx.cancelRedOk,
    );
    if (ok != true || !context.mounted) return;
    Skills.remove(s.dir);
    Chats.reconfigureSoon();
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = Skills.byDir(args ?? '');
    if (s == null) return Scaffold(appBar: CustomAppBar(), body: Center(child: Text(libL10n.empty)));
    final md = Skills.read(s.dir);
    final body = md == null ? null : SkillDiscovery.parse(md)?.body ?? md;
    final files = Skills.filesOf(s.dir);
    return DetailPage(
      embedded: false,
      header: () => ProviderHeader(title: s.name, subtitle: s.source?.id ?? s.dir),
      children: [
        SettingsGroup(
          title: s.name,
          rows: [
            SettingsRow(icon: Icons.notes, title: s.description),
            SettingsRow(icon: Icons.link, title: libL10n.source, subtitle: [?s.source?.id, s.skillPath].join(' · '), mono: true),
            SettingsRow(
              icon: Icons.folder_outlined,
              title: '${libL10n.file} · ${files.length}',
              subtitle: files.take(20).join('\n') + (files.length > 20 ? '\n…' : ''),
              mono: true,
            ),
          ],
        ),
        if (body != null)
          SettingsGroup(
            title: 'SKILL.md',
            header: Padding(padding: const EdgeInsets.all(13), child: ChatMarkdown(body)),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Btn.text(
              text: libL10n.delete,
              textStyle: TextStyle(color: context.theme.colorScheme.error),
              onTap: () => _delete(context, s),
            ),
          ],
        ),
      ],
    );
  }
}
