part of '../tool.dart';

/// Asks the user to fill in a form, in the conversation, and waits for them.
///
/// Not one of the tools on the tools page: it is how the model asks, and the
/// form is the asking, so it needs no approval either. A secret field's value
/// never reaches the model — see [LlmSecrets].
final class TfAskUser extends ToolFunc {
  static const instance = TfAskUser._();

  /// Its group, for [LlmUi.offers].
  static const groupName = 'ask_user';

  const TfAskUser._()
    : super(
        name: 'ask_user',
        parametersSchema: const {
          'type': 'object',
          'properties': {
            'title': {'type': 'string', 'description': 'What is being asked, in a few words.'},
            'description': {'type': 'string', 'description': 'Why, if the title does not say.'},
            'submit_label': {'type': 'string', 'description': 'The submit button\'s text: what submitting does.'},
            'fields': {
              'type': 'array',
              'maxItems': UserInputRequest.maxFields,
              'items': {
                'type': 'object',
                'properties': {
                  'id': {'type': 'string'},
                  'label': {'type': 'string'},
                  'type': {
                    'type': 'string',
                    'enum': ['text', 'multiline', 'number', 'secret', 'boolean', 'select', 'multiselect'],
                  },
                  'required': {'type': 'boolean'},
                  'default': {'description': 'Not for a secret.'},
                  'placeholder': {'type': 'string'},
                  'pattern': {'type': 'string', 'description': 'A regular expression a text answer must match whole.'},
                  'options': {
                    'type': 'array',
                    'description': 'For select and multiselect.',
                    'items': {
                      'type': 'object',
                      'properties': {
                        'value': {'type': 'string'},
                        'label': {'type': 'string'},
                      },
                      'required': ['value'],
                    },
                  },
                },
                'required': ['id', 'label', 'type'],
              },
            },
          },
          'required': ['title', 'fields'],
        },
      );

  @override
  String get description =>
      'Ask the user to fill in a short form, shown in the conversation, and wait for it. For what you cannot '
      'find out yourself, or a choice that is theirs. Use `secret` for a password, key or token: you get '
      '{"secret": "sec_…"} instead of the value, which a tool that takes a credential accepts in its place — '
      'never ask for one in plain text. The result is `submitted` with the values, or `cancelled`, with the '
      "message the user sent instead if they did.";

  @override
  String get l10nName => llmL10n.askUser;

  @override
  String get group => groupName;

  @override
  bool get trusted => true;

  @override
  IconData get icon => Icons.edit_note;

  @override
  String summary(_Map args) => '${args['title'] ?? ''}';

  @override
  Future<LlmToolResult> run(_Map args, ToolCtx ctx) async {
    final UserInputRequest request;
    try {
      request = UserInputRequest.parse(args);
    } on FormatException catch (e) {
      throw ArgumentError(e.message);
    }
    final answer = Chats.ask(ctx.chatId, request);
    // Stopping the reply takes the form away.
    unawaited(ctx.cancel.whenCancelled.then((_) => Chats.cancelInput(ctx.chatId)));
    return switch (await answer) {
      UserInputSubmitted(:final values) => LlmToolResult.text(jsonEncode({'status': 'submitted', 'values': values})),
      UserInputCancelled(:final message) => LlmToolResult.text(jsonEncode({
        'status': 'cancelled',
        if (message != null && message.trim().isNotEmpty) 'user_message': message,
      })),
    };
  }
}
