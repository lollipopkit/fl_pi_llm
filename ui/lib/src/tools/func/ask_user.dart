part of '../tool.dart';

/// Asks the user in the conversation, and waits for them: [UserQuestion]s to
/// choose in, the way Claude Code's AskUserQuestion asks, and fields to fill
/// in.
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
            'submit_label': {'type': 'string', 'description': 'The submit button: what submitting does.'},
            'questions': {
              'type': 'array',
              'maxItems': UserInputRequest.maxQuestions,
              'description': 'Choices. Each shows its options with what they mean; the user may also answer in '
                  'their own words, so do not add an "Other" option.',
              'items': {
                'type': 'object',
                'properties': {
                  'id': {'type': 'string'},
                  'question': {'type': 'string', 'description': 'The whole question, ending in a question mark.'},
                  'header': {
                    'type': 'string',
                    'description': 'A tag of at most ${UserQuestion.maxHeader} characters: what it is about.',
                  },
                  'options': {
                    'type': 'array',
                    'minItems': UserQuestion.minOptions,
                    'maxItems': UserQuestion.maxOptions,
                    'items': {
                      'type': 'object',
                      'properties': {
                        'label': {'type': 'string', 'description': 'A few words.'},
                        'description': {'type': 'string', 'description': 'What choosing it means, or its cost.'},
                      },
                      'required': ['label'],
                    },
                  },
                  'multi_select': {'type': 'boolean', 'description': 'Several may be chosen. Default false.'},
                },
                'required': ['id', 'question', 'options'],
              },
            },
            'fields': {
              'type': 'array',
              'maxItems': UserInputRequest.maxFields,
              'description': 'Things to type in.',
              'items': {
                'type': 'object',
                'properties': {
                  'id': {'type': 'string'},
                  'label': {'type': 'string'},
                  'type': {
                    'type': 'string',
                    'enum': ['text', 'multiline', 'number', 'secret', 'boolean'],
                  },
                  'required': {'type': 'boolean'},
                  'default': {'description': 'Not for a secret.'},
                  'placeholder': {'type': 'string'},
                  'pattern': {'type': 'string', 'description': 'A regular expression a text answer must match whole.'},
                },
                'required': ['id', 'label', 'type'],
              },
            },
          },
          'required': ['title'],
        },
      );

  @override
  String get description =>
      'Ask the user, in the conversation, and wait for the answer: `questions` to choose in (one or several '
      'options each, with what each means; they can always answer in their own words) and `fields` to type in. '
      'For a choice that is theirs or what you cannot find out yourself — not to confirm what you were asked to '
      'do. Use a `secret` field for a password, key or token: you get {"secret": "sec_…"} instead of the value, '
      'which a tool that takes a credential accepts in its place — never ask for one in plain text. The result '
      'is `submitted`, with `answers` by question id (an option\'s label, a list of them, or {"other": text}) '
      'and `values` by field id, or `cancelled`, with the message the user sent instead if they did.';

  @override
  String get l10nName => llmL10n.askUser;

  @override
  String get group => groupName;

  @override
  bool get trusted => true;

  @override
  IconData get icon => Icons.help_outline;

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
    // Stopping the reply takes this form away — this one, not a later one the
    // same chat shows by the time the stop arrives.
    return switch (await Chats.ask(ctx.chatId, request, cancelled: ctx.cancel.whenCancelled)) {
      UserInputSubmitted(:final answers, :final values) => LlmToolResult.text(jsonEncode({
        'status': 'submitted',
        if (answers.isNotEmpty) 'answers': answers,
        if (values.isNotEmpty) 'values': values,
      })),
      UserInputCancelled(:final message) => LlmToolResult.text(jsonEncode({
        'status': 'cancelled',
        if (message != null && message.trim().isNotEmpty) 'user_message': message,
      })),
    };
  }
}
