import 'dart:async';
import 'dart:math';

/// A field of a form the model asks the user to fill in ([UserInputRequest]).
enum UserInputType { text, multiline, number, secret, boolean, select, multiselect }

final class UserInputOption {
  const UserInputOption(this.value, this.label);

  final String value;
  final String label;
}

final class UserInputField {
  const UserInputField({
    required this.id,
    required this.label,
    required this.type,
    this.required = false,
    this.defaultValue,
    this.placeholder,
    this.pattern,
    this.options = const [],
  });

  final String id;
  final String label;
  final UserInputType type;
  final bool required;
  final Object? defaultValue;
  final String? placeholder;

  /// What a text answer has to match, whole.
  final RegExp? pattern;
  final List<UserInputOption> options;
}

/// A form the model asked for with `ask_user`, read from its arguments.
final class UserInputRequest {
  const UserInputRequest({required this.title, required this.fields, this.description, this.submitLabel});

  static const maxFields = 10;

  final String title;
  final String? description;
  final String? submitLabel;
  final List<UserInputField> fields;

  /// [args] as a form, or a [FormatException] saying what is wrong with them
  /// — the model's to fix.
  factory UserInputRequest.parse(Map<String, Object?> args) {
    String? str(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;
    final title = str(args['title']) ?? (throw const FormatException('title is required'));
    final raw = args['fields'];
    if (raw is! List || raw.isEmpty) throw const FormatException('fields: at least one');
    if (raw.length > maxFields) throw const FormatException('fields: at most $maxFields');
    final seen = <String>{};
    final fields = <UserInputField>[];
    for (final f in raw) {
      if (f is! Map) throw const FormatException('each field is an object');
      final id = str(f['id']) ?? (throw const FormatException('each field needs an id'));
      if (!seen.add(id)) throw FormatException('field id $id is used twice');
      final type = UserInputType.values.firstWhere(
        (t) => t.name == f['type'],
        orElse: () => throw FormatException('field $id: type is one of ${UserInputType.values.map((t) => t.name).join(', ')}'),
      );
      final options = [
        for (final o in (f['options'] as List?) ?? const [])
          if (o is Map && str(o['value']) != null) UserInputOption(str(o['value'])!, str(o['label']) ?? str(o['value'])!)
          else if (o is String && o.isNotEmpty) UserInputOption(o, o),
      ];
      if ((type == UserInputType.select || type == UserInputType.multiselect) && options.isEmpty) {
        throw FormatException('field $id: options are required for $type');
      }
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
        options: options,
      ));
    }
    return UserInputRequest(
      title: title,
      description: str(args['description']),
      submitLabel: str(args['submit_label']),
      fields: fields,
    );
  }
}

/// How the user answered a form.
sealed class UserInputAnswer {
  const UserInputAnswer();
}

final class UserInputSubmitted extends UserInputAnswer {
  const UserInputSubmitted(this.values);

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
