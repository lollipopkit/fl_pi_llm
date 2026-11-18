import 'dart:convert';

import 'package:fl_lib/fl_lib.dart';
import 'package:fl_pi_llm_ui/src/core/llm.dart';
import 'package:fl_pi_llm_ui/src/res/l10n.dart';
import 'package:fl_pi_llm_ui/src/view/section_list.dart';
import 'package:material_ui/material_ui.dart';

/// What a redaction rule list is kept in and read from, and where the page
/// writes it back.
///
/// The settings are the host's: this package runs in more than one app, and
/// an agent a host reaches keeps its own.
abstract interface class RedactSource {
  /// The settings as `fl_pi_llm::redact::Settings` JSON, null for none set.
  Future<String?> load();

  /// Saves what the page produced, as the same JSON. Answers an error to show
  /// — a rule that does not compile is refused by the engine, and the person
  /// is still on the page to fix it.
  Future<String?> save(String? settings);

  /// Whether the switch is on: off sends everything.
  bool get enabled;

  Future<void> setEnabled(bool on);
}

/// The rules: which shapes are replaced before anything leaves for a model,
/// and what is never replaced however it looks.
///
/// Only what a pattern can recognise — see `fl_pi_llm`'s `redact` for why a
/// loose rule here is worse than a missing one.
final class RedactPage extends StatefulWidget {
  final RedactSource args;

  const RedactPage({super.key, required this.args});

  @override
  State<RedactPage> createState() => _RedactPageState();
}

class _RedactPageState extends State<RedactPage> {
  /// The rules the engine runs, by kind, read from it: a page listing a rule
  /// the engine does not have would switch nothing.
  List<Map<String, Object?>> _builtin = const [];
  var _loading = true;

  /// The settings as saved, and the three lists a rule edit touches. Kept
  /// apart so a field that does not compile is not lost by another edit.
  var _enabled = true;
  var _off = <String>{};
  final _custom = <Map<String, Object?>>[];
  final _allow = <String>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // The rules come from the engine, which is not there when the runtime
    // failed to start — and that is exactly when a person opens this page,
    // to see what is set. The list is what is missing then, not the settings.
    List<Map<String, Object?>> rules;
    try {
      rules = await Llm.rt.redactionRules();
    } catch (e, s) {
      Loggers.app.warning('Reading the redaction rules', e, s);
      rules = const [];
    }
    final Map<String, Object?> settings;
    try {
      final raw = await widget.args.load();
      settings = raw == null
          ? const <String, Object?>{}
          : (jsonDecode(raw) as Map).cast<String, Object?>();
    } catch (e, s) {
      Loggers.app.warning('Reading the redaction settings', e, s);
      if (mounted) {
        setState(() {
          _loadError = '$e';
          _loading = false;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _loadError = null;
      _builtin = rules;
      _enabled = widget.args.enabled;
      _off = {...?(settings['off'] as List?)?.cast<String>()};
      _custom
        ..clear()
        ..addAll([
          for (final r in (settings['custom'] as List?) ?? const [])
            if (r is Map) r.cast<String, Object?>(),
        ]);
      _allow
        ..clear()
        ..addAll((settings['allow'] as List?)?.cast<String>() ?? const []);
      _handles = (settings['handles'] as List?)?.cast<String>();
      _loading = false;
    });
  }

  Map<String, Object?> _settings() => {
    'enabled': _enabled,
    // Not edited here, and not this page's to drop: the app issues these and
    // its own tools trade them back.
    'handles': ?_handles,
    if (_off.isNotEmpty) 'off': _off.toList()..sort(),
    if (_allow.isNotEmpty) 'allow': _allow,
    if (_custom.isNotEmpty) 'custom': _custom,
  };

  /// Whatever the host set that this page does not edit, kept as it was.
  List<String>? _handles;

  /// Why the settings could not be read; the page offers to try again.
  String? _loadError;

  /// The save in flight. Edits wait their turn, so a refusal undoes only its
  /// own edit, never one made after it.
  Future<void> _saving = Future.value();

  /// [change] applied and saved, or undone when the save is refused: a rule
  /// left on the page after that would be refused with every later edit.
  Future<void> _commit(VoidCallback change) => _saving = _saving.catchError((Object _) {}).then((_) => _commitNow(change));

  Future<void> _commitNow(VoidCallback change) async {
    if (!mounted) return;
    final off = {..._off};
    final custom = [..._custom];
    final allow = [..._allow];
    setState(change);
    String? err;
    try {
      err = await widget.args.save(jsonEncode(_settings()));
    } catch (e, s) {
      Loggers.app.warning('Saving the redaction rules', e, s);
      err = '$e';
    }
    if (!mounted) return;
    if (err == null) {
      Toast.success(libL10n.success);
      return;
    }
    Toast.error(err);
    setState(() {
      _off = off;
      _custom
        ..clear()
        ..addAll(custom);
      _allow
        ..clear()
        ..addAll(allow);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: CustomAppBar(title: Text(llmL10n.redactRules)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadError case final err?) {
      return Scaffold(
        appBar: CustomAppBar(title: Text(llmL10n.redactRules)),
        body: EmptyPane(
          icon: Icons.error_outline,
          title: libL10n.error,
          label: err,
          action: Btn.text(
            text: libL10n.retry,
            onTap: () {
              setState(() => _loading = true);
              _load();
            },
          ),
        ),
      );
    }
    return Scaffold(
      appBar: CustomAppBar(title: Text(llmL10n.redactRules)),
      body: SectionList(
        children: [
          SettingsGroup(
            rows: [
              SettingsRow(
                icon: Icons.shield_outlined,
                title: llmL10n.redactEnabled,
                trailing: SwitchX(
                  value: _enabled,
                  onChanged: (on) async {
                    await widget.args.setEnabled(on);
                    if (mounted) setState(() => _enabled = on);
                  },
                ),
              ),
            ],
          ),
          _customGroup(),
          _allowGroup(),
          // Last, as the reference; muted while off rather than gone, so the
          // list does not jump with the switch.
          SettingsGroup(
            title: llmL10n.redactBuiltIn,
            rows: [
              for (final rule in _builtin)
                _builtinRow(rule['kind']! as String, rule['pattern']! as String),
            ],
          ),
        ],
      ),
    );
  }

  Widget _builtinRow(String kind, String pattern) {
    return SettingsRow(
      icon: _off.contains(kind) ? Icons.visibility_off_outlined : Icons.visibility_outlined,
      title: kind,
      subtitle: pattern,
      mono: true,
      muted: !_enabled,
      trailing: SwitchX(
        value: !_off.contains(kind),
        onChanged: (on) => _commit(() => on ? _off.remove(kind) : _off.add(kind)),
      ),
    );
  }

  Widget _customRow(int i) {
    final rule = _custom[i];
    final name = rule['name'] as String? ?? rule['pattern'] as String? ?? '';
    return SettingsRow(
      icon: Icons.code,
      title: name,
      subtitle: rule['pattern'] as String? ?? '',
      mono: true,
      muted: !_enabled,
      trailing: Btn.icon(
        icon: const Icon(Icons.delete_outline),
        onTap: () => _commit(() => _custom.removeAt(i)),
      ),
    );
  }

  /// The user's own rules. The row that adds one comes first: a group whose
  /// add row is last is one that grows past it as entries arrive.
  ///
  /// Always here, empty or not: a group that appears only once it has
  /// something is one nobody finds.
  Widget _customGroup() {
    return SettingsGroup(
      title: llmL10n.redactCustom,
      rows: [
        SettingsRow(
          icon: Icons.add,
          title: llmL10n.redactAddRule,
          onTap: _addRule,
        ),
        for (var i = 0; i < _custom.length; i++) _customRow(i),
      ],
    );
  }

  /// Values a rule never replaces, and the row that adds one — first, as in
  /// the group above.
  Widget _allowGroup() {
    return SettingsGroup(
      title: llmL10n.redactAllow,
      rows: [
        SettingsRow(
          icon: Icons.add,
          title: llmL10n.redactAddAllow,
          onTap: _addAllow,
        ),
        for (final v in _allow)
          SettingsRow(
            title: v,
            mono: true,
            trailing: Btn.icon(
              icon: const Icon(Icons.delete_outline),
              onTap: () => _commit(() => _allow.remove(v)),
            ),
          ),
      ],
    );
  }

  Future<void> _addRule() async {
    // The form holds the fields, so the page reads it through a key: an
    // empty pattern is refused where it is typed, and the sheet answers the
    // rule itself rather than a yes.
    final form = GlobalKey<_RuleFormState>();
    final rule = await context.showSheet<Map<String, Object?>>(
      title: llmL10n.redactCustom,
      child: _RuleForm(key: form),
      actions: [
        Btn.cancel(),
        Btn.ok(
          onTap: () {
            if (form.currentState?.read() case final rule?) context.popSheet(rule);
          },
        ),
      ],
    );
    if (rule == null || !mounted) return;
    await _commit(() => _custom.add(rule));
  }

  Future<void> _addAllow() async {
    final v = await context.showInputSheet(title: llmL10n.redactAllow);
    if (v == null || v.trim().isEmpty || !mounted) return;
    await _commit(() => _allow.add(v.trim()));
  }
}

/// A custom rule, typed into a sheet. The whole form answers, so nothing is
/// added until it is done.
class _RuleForm extends StatefulWidget {
  const _RuleForm({super.key});

  @override
  State<_RuleForm> createState() => _RuleFormState();
}

class _RuleFormState extends State<_RuleForm> {
  final _pattern = TextEditingController();
  final _group = TextEditingController();
  final _name = TextEditingController();

  @override
  void dispose() {
    _pattern.dispose();
    _group.dispose();
    _name.dispose();
    super.dispose();
  }

  /// The rule as typed, or null while the pattern is empty.
  Map<String, Object?>? read() {
    final pattern = _pattern.text.trim();
    if (pattern.isEmpty) return null;
    final name = _name.text.trim();
    return {
      'pattern': pattern,
      'group': ?int.tryParse(_group.text.trim()),
      'name': ?(name.isEmpty ? null : name),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Input(
          controller: _pattern,
          label: llmL10n.redactPattern,
          hint: llmL10n.redactPatternHint,
        ),
        Input(
          controller: _group,
          label: llmL10n.redactGroup,
          hint: llmL10n.redactGroupHint,
          type: TextInputType.number,
        ),
        Input(
          controller: _name,
          label: llmL10n.redactName,
          hint: llmL10n.redactNameHint,
        ),
      ],
    );
  }
}
