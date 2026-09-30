import 'package:fl_lib/fl_lib.dart';
import 'package:fl_pi_llm_ui/src/core/chats.dart';
import 'package:fl_pi_llm_ui/src/core/user_input.dart';
import 'package:fl_pi_llm_ui/src/res/l10n.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// The form a model asked the user to fill in (`ask_user`), where the
/// approval card would be. Submitting or cancelling answers the call the
/// reply is waiting on; sending a message instead cancels it, from the
/// composer.
class AskUserCard extends StatefulWidget {
  const AskUserCard({super.key, required this.pending});

  final PendingInput pending;

  @override
  State<AskUserCard> createState() => _AskUserCardState();
}

class _AskUserCardState extends State<AskUserCard> {
  UserInputRequest get _req => widget.pending.request;

  late final _text = <String, TextEditingController>{
    for (final f in _req.fields)
      if (const {UserInputType.text, UserInputType.multiline, UserInputType.number, UserInputType.secret}.contains(f.type))
        f.id: TextEditingController(text: f.defaultValue == null ? '' : '${f.defaultValue}'),
  };
  late final _bool = <String, bool>{
    for (final f in _req.fields)
      if (f.type == UserInputType.boolean) f.id: f.defaultValue == true,
  };
  late final _select = <String, String?>{
    for (final f in _req.fields)
      if (f.type == UserInputType.select)
        f.id: f.options.any((o) => o.value == f.defaultValue) ? f.defaultValue as String : null,
  };
  late final _multi = <String, Set<String>>{
    for (final f in _req.fields)
      if (f.type == UserInputType.multiselect)
        f.id: {
          for (final v in f.defaultValue is List ? f.defaultValue as List : const [])
            if (f.options.any((o) => o.value == v)) v as String,
        },
  };
  final _errors = <String, String>{};

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// The values, or null after marking what is missing or wrong.
  Map<String, Object?>? _collect() {
    _errors.clear();
    final out = <String, Object?>{};
    for (final f in _req.fields) {
      switch (f.type) {
        case UserInputType.boolean:
          out[f.id] = _bool[f.id];
        case UserInputType.select:
          final v = _select[f.id];
          if (v == null && f.required) _errors[f.id] = llmL10n.fieldRequired;
          if (v != null) out[f.id] = v;
        case UserInputType.multiselect:
          final v = _multi[f.id]!;
          if (v.isEmpty && f.required) _errors[f.id] = llmL10n.fieldRequired;
          out[f.id] = [for (final o in f.options) if (v.contains(o.value)) o.value];
        case UserInputType.number:
          final t = _text[f.id]!.text.trim();
          if (t.isEmpty) {
            if (f.required) _errors[f.id] = llmL10n.fieldRequired;
          } else if (num.tryParse(t) case final n?) {
            out[f.id] = n;
          } else {
            _errors[f.id] = llmL10n.fieldInvalid;
          }
        case UserInputType.text || UserInputType.multiline || UserInputType.secret:
          final t = f.type == UserInputType.secret ? _text[f.id]!.text : _text[f.id]!.text.trim();
          if (t.isEmpty) {
            if (f.required) _errors[f.id] = llmL10n.fieldRequired;
          } else if (f.pattern != null && !f.pattern!.hasMatch(t)) {
            _errors[f.id] = llmL10n.fieldInvalid;
          } else {
            out[f.id] = t;
          }
      }
    }
    setState(() {});
    return _errors.isEmpty ? out : null;
  }

  void _submit() {
    final values = _collect();
    if (values != null) Chats.submitInput(widget.pending.chatId, values);
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
                  Icon(Icons.edit_note, size: 20, color: scheme.primary),
                  const SizedBox(width: 9),
                  Expanded(child: Text(_req.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
                ],
              ),
              if (_req.description case final d?) Text(d, style: UIs.text13Grey),
              for (final f in _req.fields) _field(f),
              Row(
                children: [
                  Expanded(child: Text(llmL10n.replyWaits, style: UIs.text12Grey)),
                  Btn.text(text: libL10n.cancel, onTap: () => Chats.cancelInput(widget.pending.chatId)),
                  Btn.text(text: _req.submitLabel ?? libL10n.ok, onTap: _submit),
                ].joinWith(const SizedBox(width: 3)),
              ),
            ].joinWith(const SizedBox(height: 9)),
          ),
        ),
      ),
    );
  }

  Widget _field(UserInputField f) {
    final label = f.required ? '${f.label} *' : f.label;
    final error = _errors[f.id];
    Widget errorLine(Widget child) => error == null
        ? child
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              child,
              Padding(
                padding: const EdgeInsets.only(left: 13, top: 3),
                child: Text(error, style: TextStyle(fontSize: 12, color: context.theme.colorScheme.error)),
              ),
            ],
          );
    switch (f.type) {
      case UserInputType.boolean:
        return SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 13),
          title: Text(f.label, style: const TextStyle(fontSize: 14)),
          value: _bool[f.id]!,
          onChanged: (v) => setState(() => _bool[f.id] = v),
        );
      case UserInputType.select:
        return errorLine(
          DropdownButtonFormField<String>(
            initialValue: _select[f.id],
            decoration: InputDecoration(labelText: label, border: InputBorder.none),
            items: [for (final o in f.options) DropdownMenuItem(value: o.value, child: Text(o.label))],
            onChanged: (v) => setState(() => _select[f.id] = v),
          ).paddingSymmetric(horizontal: 13),
        );
      case UserInputType.multiselect:
        return errorLine(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(padding: const EdgeInsets.only(left: 13), child: Text(label, style: UIs.text12Grey)),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final o in f.options)
                    FilterChip(
                      label: Text(o.label),
                      selected: _multi[f.id]!.contains(o.value),
                      onSelected: (on) => setState(() => on ? _multi[f.id]!.add(o.value) : _multi[f.id]!.remove(o.value)),
                    ),
                ],
              ).paddingSymmetric(horizontal: 13),
            ],
          ),
        );
      case UserInputType.text || UserInputType.multiline || UserInputType.number || UserInputType.secret:
        return errorLine(
          Input(
            controller: _text[f.id],
            label: label,
            hint: f.placeholder,
            autoFocus: f == _req.fields.first,
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
        );
    }
  }
}
