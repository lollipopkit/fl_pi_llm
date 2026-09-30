import 'dart:async';
import 'dart:math';

/// A field to fill in, of a form the model asks for ([UserInputRequest]).
/// A choice is a [UserQuestion] instead.
enum UserInputType { text, multiline, number, secret, boolean }

final class UserInputField {
  const UserInputField({
    required this.id,
    required this.label,
    required this.type,
    this.required = false,
    this.defaultValue,
    this.placeholder,
    this.pattern,
  });

  final String id;
  final String label;
  final UserInputType type;
  final bool required;
  final Object? defaultValue;
  final String? placeholder;

  /// What a text answer has to match, whole.
  final RegExp? pattern;
}

/// An option of a [UserQuestion]: what it is, and what choosing it means.
final class UserOption {
  const UserOption(this.label, [this.description]);

  final String label;
  final String? description;
}

/// A choice put to the user, the way Claude Code's AskUserQuestion puts one:
/// a few options with what each means, one or several to pick — and always
/// an answer of their own ("Other"), which the model does not offer itself.
final class UserQuestion {
  const UserQuestion({
    required this.id,
    required this.question,
    required this.options,
    this.header,
    this.multiSelect = false,
  });

  static const minOptions = 2;
  static const maxOptions = 4;
  static const maxHeader = 12;

  final String id;
  final String question;

  /// A short tag above it: what it is about, in a word or two.
  final String? header;
  final List<UserOption> options;
  final bool multiSelect;
}

/// A form the model asked for with `ask_user`, read from its arguments:
/// [questions] to choose in, [fields] to fill in, or both.
final class UserInputRequest {
  const UserInputRequest({
    required this.title,
    this.questions = const [],
    this.fields = const [],
    this.description,
    this.submitLabel,
  });

  static const maxQuestions = 4;
  static const maxFields = 10;

  final String title;
  final String? description;
  final String? submitLabel;
  final List<UserQuestion> questions;
  final List<UserInputField> fields;

  /// [args] as a form, or a [FormatException] saying what is wrong with them
  /// — the model's to fix.
  factory UserInputRequest.parse(Map<String, Object?> args) {
    String? str(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;
    final title = str(args['title']) ?? (throw const FormatException('title is required'));
    final rawQ = args['questions'] is List ? args['questions'] as List : const [];
    final rawF = args['fields'] is List ? args['fields'] as List : const [];
    if (rawQ.isEmpty && rawF.isEmpty) throw const FormatException('questions or fields: at least one');
    if (rawQ.length > maxQuestions) throw const FormatException('questions: at most $maxQuestions');
    if (rawF.length > maxFields) throw const FormatException('fields: at most $maxFields');
    final seen = <String>{};
    String idOf(Map m, String kind, int i) {
      final id = str(m['id']) ?? '$kind$i';
      if (!seen.add(id)) throw FormatException('id $id is used twice');
      return id;
    }

    final questions = <UserQuestion>[];
    for (final (i, q) in rawQ.indexed) {
      if (q is! Map) throw const FormatException('each question is an object');
      final id = idOf(q, 'q', i);
      final text = str(q['question']) ?? (throw FormatException('question $id: question is required'));
      final options = <UserOption>[];
      for (final o in (q['options'] as List?) ?? const []) {
        final label = o is Map ? str(o['label']) : str(o);
        if (label == null) continue;
        if (options.any((e) => e.label == label)) throw FormatException('question $id: option $label twice');
        options.add(UserOption(label, o is Map ? str(o['description']) : null));
      }
      if (options.length < UserQuestion.minOptions || options.length > UserQuestion.maxOptions) {
        throw FormatException(
          'question $id: ${UserQuestion.minOptions} to ${UserQuestion.maxOptions} options; the user can always answer their own',
        );
      }
      final header = str(q['header']);
      questions.add(UserQuestion(
        id: id,
        question: text,
        header: header == null || header.length <= UserQuestion.maxHeader
            ? header
            : '${header.substring(0, UserQuestion.maxHeader - 1)}…',
        options: options,
        multiSelect: q['multi_select'] == true || q['multiSelect'] == true,
      ));
    }

    final fields = <UserInputField>[];
    for (final (i, f) in rawF.indexed) {
      if (f is! Map) throw const FormatException('each field is an object');
      final id = idOf(f, 'f', i);
      final type = UserInputType.values.firstWhere(
        (t) => t.name == f['type'],
        orElse: () => throw FormatException(
          'field $id: type is one of ${UserInputType.values.map((t) => t.name).join(', ')}; a choice is a question',
        ),
      );
      RegExp? pattern;
      if (str(f['pattern']) case final p?) {
        try {
          pattern = RegExp('^(?:$p)\$');
        } catch (_) {
          throw FormatException('field $id: pattern is not a regular expression');
        }
      }
      fields.add(UserInputField(
        id: id,
        label: str(f['label']) ?? id,
        type: type,
        required: f['required'] == true,
        // A secret's default would be one the model knows.
        defaultValue: type == UserInputType.secret ? null : f['default'],
        placeholder: str(f['placeholder']),
        pattern: pattern,
      ));
    }
    return UserInputRequest(
      title: title,
      description: str(args['description']),
      submitLabel: str(args['submit_label']),
      questions: questions,
      fields: fields,
    );
  }
}

/// How the user answered a form.
sealed class UserInputAnswer {
  const UserInputAnswer();
}

final class UserInputSubmitted extends UserInputAnswer {
  const UserInputSubmitted({this.answers = const {}, this.values = const {}});

  /// By question id: the option's label, the labels chosen of a multiple
  /// choice, or `{"other": text}` for an answer of the user's own.
  final Map<String, Object?> answers;

  /// By field id. A secret's is its [LlmSecrets] handle, not the value.
  final Map<String, Object?> values;
}

final class UserInputCancelled extends UserInputAnswer {
  const UserInputCancelled({this.message});

  /// What the user sent instead of filling it in.
  final String? message;
}

/// A form on screen, waiting.
final class PendingInput {
  PendingInput(this.chatId, this.request);

  final String chatId;
  final UserInputRequest request;
  final _answer = Completer<UserInputAnswer>();

  Future<UserInputAnswer> get answer => _answer.future;

  bool get done => _answer.isCompleted;

  void complete(UserInputAnswer a) {
    if (!_answer.isCompleted) _answer.complete(a);
  }

  /// Answers it: [answers] by question id, [values] by field id. What a
  /// secret field holds is sealed here ([LlmSecrets]): the model gets a
  /// handle.
  void submit({Map<String, Object?> answers = const {}, Map<String, Object?> values = const {}}) => complete(
    UserInputSubmitted(
      answers: answers,
      values: {
        for (final f in request.fields)
          if (values.containsKey(f.id))
            f.id: f.type == UserInputType.secret && values[f.id] is String && (values[f.id] as String).isNotEmpty
                ? {'secret': LlmSecrets.seal(chatId, values[f.id] as String)}
                : values[f.id],
      },
    ),
  );
}

/// What the user typed into a form's secret fields, kept from the model: it
/// gets a handle (`sec_…`), which a tool trades for the value here — once,
/// and only in the chat it was asked in. In memory alone: never in a
/// session, never on disk, gone with the app.
abstract final class LlmSecrets {
  static final _byChat = <String, Map<String, String>>{};
  static final _random = Random.secure();

  static String seal(String chatId, String value) {
    final handle = 'sec_${List.generate(12, (_) => _random.nextInt(36).toRadixString(36)).join()}';
    (_byChat[chatId] ??= {})[handle] = value;
    return handle;
  }

  /// The value behind [ref] — a handle, or `{"secret": handle}` — in chat
  /// [chatId], forgotten as it is read. Null when there is none.
  static String? take(String chatId, Object? ref) {
    final handle = switch (ref) {
      final String s => s,
      {'secret': final String s} => s,
      _ => null,
    };
    if (handle == null || !handle.startsWith('sec_')) return null;
    final chat = _byChat[chatId];
    final v = chat?.remove(handle);
    if (chat != null && chat.isEmpty) _byChat.remove(chatId);
    return v;
  }

  static void forget(String chatId) => _byChat.remove(chatId);
}
