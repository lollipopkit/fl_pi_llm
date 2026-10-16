import 'package:fl_pi_llm_ui/src/core/user_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('what the model asks, read', () {
    UserInputRequest parse(Map<String, Object?> a) => UserInputRequest.parse(a);

    test('questions with options, and fields', () {
      final r = parse({
        'title': 'Set up',
        'questions': [
          {
            'id': 'db',
            'question': 'Which database?',
            'header': 'A header far past twelve characters',
            'options': [
              {'label': 'PostgreSQL', 'description': 'Relational.'},
              'SQLite',
            ],
          },
          {
            'id': 'feat',
            'question': 'Which features?',
            'multi_select': true,
            'options': ['Backup', 'Alerts', 'Metrics'],
          },
        ],
        'fields': [
          {'id': 'user', 'label': 'User', 'type': 'text', 'default': 'admin'},
          {'id': 'pw', 'label': 'Password', 'type': 'secret', 'required': true, 'default': 'leaked'},
        ],
      });
      expect(r.questions.map((q) => q.multiSelect), [false, true]);
      expect(r.questions.first.options.first.description, 'Relational.');
      expect(r.questions.first.header!.length, UserQuestion.maxHeader);
      expect(r.fields[1].defaultValue, isNull, reason: 'a secret has no default the model knows');
    });

    test('refused when it cannot be shown', () {
      Map<String, Object?> q(List<Object> options) => {
        'title': 't',
        'questions': [{'id': 'q', 'question': 'Q?', 'options': options}],
      };
      for (final bad in <Map<String, Object?>>[
        {'fields': [{'id': 'a', 'label': 'x', 'type': 'text'}]},
        {'title': 't'},
        q(['only one']),
        q(['a', 'b', 'c', 'd', 'e']),
        q(['same', 'same']),
        {'title': 't', 'questions': [for (var i = 0; i < 5; i++) {'id': '$i', 'question': 'Q?', 'options': ['a', 'b']}]},
        {'title': 't', 'fields': [for (var i = 0; i < 11; i++) {'id': '$i', 'label': 'x', 'type': 'text'}]},
        {'title': 't', 'fields': [{'id': 'a', 'label': 'x', 'type': 'text'}, {'id': 'a', 'label': 'y', 'type': 'text'}]},
        {'title': 't', 'fields': [{'id': 'a', 'label': 'x', 'type': 'select'}]},
        {'title': 't', 'fields': [{'id': 'a', 'label': 'x', 'type': 'text', 'pattern': '('}]},
      ]) {
        expect(() => parse(bad), throwsFormatException, reason: '$bad');
      }
    });

    test('a pattern matches a whole answer', () {
      final f = parse({
        'title': 't',
        'fields': [{'id': 'port', 'label': 'Port', 'type': 'text', 'pattern': r'\d+'}],
      }).fields.single;
      expect(f.pattern!.hasMatch('22'), isTrue);
      expect(f.pattern!.hasMatch('22a'), isFalse);
    });
  });

  test('a secret is traded once, and only in the chat it was given in', () {
    final h = LlmSecrets.seal('chat-a', 'hunter2');
    expect(h, startsWith('sec_'));
    expect(LlmSecrets.take('chat-b', h), isNull);
    expect(LlmSecrets.take('chat-a', {'secret': h}), 'hunter2');
    expect(LlmSecrets.take('chat-a', h), isNull, reason: 'used up');
    expect(LlmSecrets.take('chat-a', 'hunter2'), isNull, reason: 'a plain value is not a handle');

    final h2 = LlmSecrets.seal('chat-a', 'x');
    LlmSecrets.forget('chat-a');
    expect(LlmSecrets.take('chat-a', h2), isNull);
  });
}
