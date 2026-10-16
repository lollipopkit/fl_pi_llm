import 'package:fl_lib/fl_lib.dart';
import 'package:fl_pi_llm_ui/src/core/user_input.dart';
import 'package:fl_pi_llm_ui/src/res/l10n.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// What the model asked the user (`ask_user`), where the approval card would
/// be: its questions, each a list of options with what they mean and an
/// answer of the user's own, then its fields. Submitting or cancelling
/// answers the call the reply waits on; sending a message instead cancels
/// it, from the composer.
class AskUserCard extends StatefulWidget {
  const AskUserCard({super.key, required this.pending});

  final PendingInput pending;

  @override
  State<AskUserCard> createState() => _AskUserCardState();
}

class _AskUserCardState extends State<AskUserCard> {
  UserInputRequest get _req => widget.pending.request;

  /// Chosen options' labels, by question id.
  late final _chosen = {for (final q in _req.questions) q.id: <String>{}};

  /// Whether a question's own answer ("Other") is chosen, and what it says.
  late final _otherOn = {for (final q in _req.questions) q.id: false};
  late final _other = {for (final q in _req.questions) q.id: TextEditingController()};

  late final _text = <String, TextEditingController>{
    for (final f in _req.fields)
      if (f.type != UserInputType.boolean)
        f.id: TextEditingController(text: f.defaultValue == null ? '' : '${f.defaultValue}'),
  };
  late final _bool = <String, bool>{
    for (final f in _req.fields)
      if (f.type == UserInputType.boolean) f.id: f.defaultValue == true,
  };
  final _errors = <String, String>{};

  @override
  void dispose() {
    for (final c in [..._text.values, ..._other.values]) {
      c.dispose();
    }
    super.dispose();
  }

  void _choose(UserQuestion q, String label) => setState(() {
    final set = _chosen[q.id]!;
    if (q.multiSelect) {
      set.contains(label) ? set.remove(label) : set.add(label);
    } else {
      set
        ..clear()
        ..add(label);
      _otherOn[q.id] = false;
    }
    _errors.remove(q.id);
  });

  void _chooseOther(UserQuestion q) => setState(() {
    final on = !_otherOn[q.id]!;
    _otherOn[q.id] = q.multiSelect ? on : true;
    if (!q.multiSelect) _chosen[q.id]!.clear();
    _errors.remove(q.id);
  });

  /// What the model gets back, or null after marking what is missing.
  ({Map<String, Object?> answers, Map<String, Object?> values})? _collect() {
    _errors.clear();
    final answers = <String, Object?>{};
    for (final q in _req.questions) {
      final other = _otherOn[q.id]! ? _other[q.id]!.text.trim() : null;
      if (other != null && other.isEmpty) {
        _errors[q.id] = llmL10n.fieldRequired;
        continue;
      }
      final labels = [for (final o in q.options) if (_chosen[q.id]!.contains(o.label)) o.label];
      if (labels.isEmpty && other == null) {
        _errors[q.id] = llmL10n.fieldRequired;
        continue;
      }
      answers[q.id] = q.multiSelect
          ? [...labels, if (other != null) {'other': other}]
          : other != null
          ? {'other': other}
          : labels.single;
    }
    final values = <String, Object?>{};
    for (final f in _req.fields) {
      if (f.type == UserInputType.boolean) {
        values[f.id] = _bool[f.id];
        continue;
      }
      final raw = _text[f.id]!.text;
      final t = f.type == UserInputType.secret ? raw : raw.trim();
      if (t.isEmpty) {
        if (f.required) _errors[f.id] = llmL10n.fieldRequired;
        continue;
      }
      if (f.type == UserInputType.number) {
        final n = num.tryParse(t);
        n == null ? _errors[f.id] = llmL10n.fieldInvalid : values[f.id] = n;
      } else if (f.pattern != null && !f.pattern!.hasMatch(t)) {
        _errors[f.id] = llmL10n.fieldInvalid;
      } else {
        values[f.id] = t;
      }
    }
    setState(() {});
    return _errors.isEmpty ? (answers: answers, values: values) : null;
  }

  void _submit() {
    final r = _collect();
    if (r != null) widget.pending.submit(answers: r.answers, values: r.values);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.theme.colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: CardX.borderRadius),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter, control: true): _submit,
            const SingleActivator(LogicalKeyboardKey.enter, meta: true): _submit,
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.help_outline, size: 20, color: scheme.primary),
                  const SizedBox(width: 9),
                  Expanded(child: Text(_req.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
                ],
              ),
              if (_req.description case final d?) Text(d, style: UIs.text13Grey),
              for (final q in _req.questions) _question(q),
              for (final f in _req.fields) _field(f),
              Row(
                children: [
                  Expanded(child: Text(llmL10n.replyWaits, style: UIs.text12Grey)),
                  Btn.text(text: libL10n.cancel, onTap: () => widget.pending.complete(const UserInputCancelled())),
                  Btn.text(text: _req.submitLabel ?? libL10n.ok, onTap: _submit),
                ].joinWith(const SizedBox(width: 3)),
              ),
            ].joinWith(const SizedBox(height: 11)),
          ),
        ),
      ),
    );
  }

  Widget _error(String id) => switch (_errors[id]) {
    final e? => Padding(
      padding: const EdgeInsets.only(left: 13, top: 3),
      child: Text(e, style: TextStyle(fontSize: 12, color: context.theme.colorScheme.error)),
    ),
    null => UIs.placeholder,
  };

  Widget _question(UserQuestion q) {
    final scheme = context.theme.colorScheme;
    final chosen = _chosen[q.id]!;
    IconData mark(bool on) => q.multiSelect
        ? (on ? Icons.check_box : Icons.check_box_outline_blank)
        : (on ? Icons.radio_button_checked : Icons.radio_button_unchecked);
    Widget option({required bool on, required String label, String? description, required VoidCallback onTap}) =>
        InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              color: on ? scheme.primaryContainer.withValues(alpha: 0.5) : scheme.surface,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(mark(on), size: 18, color: on ? scheme.primary : scheme.onSurfaceVariant),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                      if (description != null) Text(description, style: UIs.text12Grey),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (q.header case final h?)
              Container(
                margin: const EdgeInsets.only(right: 7, top: 1),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(5)),
                child: Text(h, style: TextStyle(fontSize: 12, color: scheme.onSecondaryContainer)),
              ),
            Expanded(child: Text(q.question, style: const TextStyle(fontSize: 14))),
          ],
        ),
        const SizedBox(height: 7),
        for (final o in q.options) ...[
          option(on: chosen.contains(o.label), label: o.label, description: o.description, onTap: () => _choose(q, o.label)),
          const SizedBox(height: 5),
        ],
        option(on: _otherOn[q.id]!, label: llmL10n.otherAnswer, onTap: () => _chooseOther(q)),
        if (_otherOn[q.id]!)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Input(controller: _other[q.id], autoFocus: true, hint: llmL10n.otherAnswerHint, onSubmitted: (_) => _submit()),
          ),
        _error(q.id),
      ],
    );
  }

  Widget _field(UserInputField f) {
    if (f.type == UserInputType.boolean) {
      return SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 13),
        title: Text(f.label, style: const TextStyle(fontSize: 14)),
        value: _bool[f.id]!,
        onChanged: (v) => setState(() => _bool[f.id] = v),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Input(
          controller: _text[f.id],
          label: f.required ? '${f.label} *' : f.label,
          hint: f.placeholder,
          autoFocus: _req.questions.isEmpty && f == _req.fields.first,
          obscureText: f.type == UserInputType.secret,
          maxLines: f.type == UserInputType.multiline ? 6 : 1,
          minLines: f.type == UserInputType.multiline ? 2 : null,
          type: switch (f.type) {
            UserInputType.number => TextInputType.number,
            UserInputType.multiline => TextInputType.multiline,
            UserInputType.secret => TextInputType.visiblePassword,
            _ => TextInputType.text,
          },
          onSubmitted: f.type == UserInputType.multiline ? null : (_) => _submit(),
        ),
        _error(f.id),
      ],
    );
  }
}
