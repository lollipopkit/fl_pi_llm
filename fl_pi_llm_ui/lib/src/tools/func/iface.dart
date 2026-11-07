part of '../tool.dart';

/// A tool built into the app.
abstract class ToolFunc {
  final String name;
  final _Map parametersSchema;

  const ToolFunc({required this.name, required this.parametersSchema});

  String get description;

  String get l10nName;

  /// Off until the user turns it on: kept in [ToolStore.enabledTools], where
  /// the others are kept in [ToolStore.disabledTools].
  bool get defaultEnabled => true;

  /// The switch this tool is under: its own, or its family's.
  String get group => name;

  /// The name of [group], as the settings show it.
  String get groupLabel => l10nName;

  /// Runs without asking: it touches only the app's own data, which the user
  /// can see and undo.
  bool get trusted => false;

  /// What a call does, as the permissions weigh it ([LlmPermissionRules]):
  /// a read runs in every mode; a danger asks unless the chat allows all;
  /// anything else goes by the mode.
  LlmEffect effect(_Map args) => LlmEffect.change;

  /// The shell command a call runs, for the command rules and the shape of
  /// it to be weighed; null for a tool that runs none.
  String? shellCommand(_Map args) => null;

  /// Whether "always allow" is offered for it. Off for a tool that no single
  /// answer covers: it asks every time the permissions leave it to the user.
  bool get allowAlways => true;

  /// Its mark beside a call in the conversation.
  IconData? get icon => null;

  /// Its [group]'s mark on the tools page, where a group is one row; [icon]
  /// when null.
  IconData? get groupIcon => null;

  /// A call in chat [chatId], as the approval card shows it; null for
  /// [summary] on a line. It may answer the call itself — [Chats.decide] —
  /// for a choice the card's buttons do not offer.
  Widget? preview(BuildContext context, _Map args, String chatId) => null;

  String? get l10nTip => null;

  /// Opens its [group]'s own settings, from its row on the tools page; null
  /// when the switch is all there is.
  void Function(BuildContext context)? get openSettings => null;

  /// [args] on one line: what a call does, at a glance.
  String summary(_Map args) => jsonEncode(args);

  /// Runs the tool. Throw to report a failure to the model.
  Future<LlmToolResult> run(_Map args, ToolCtx ctx);

  LlmTool get llmTool => LlmTool(
    name: name,
    description: description,
    parameters: parametersSchema,
    label: l10nName,
    execute: (call, cancel) => Tools.timed(() => run(call.args, ToolCtx(call.sessionId, cancel))),
  );
}

/// What a call knows besides its arguments.
final class ToolCtx {
  const ToolCtx(this.chatId, this.cancel);

  /// The chat the call is made in: a chat's id is its session's.
  final String chatId;

  /// Fires when the user stops the run.
  final LlmCancelToken cancel;
}
