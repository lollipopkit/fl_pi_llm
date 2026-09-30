import 'package:fl_pi_llm_ui/src/core/user_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a form, as the model asks for it', () {
    UserInputRequest parse(Map<String, Object?> a) => UserInputRequest.parse(a);

    test('is read with its fields', () {
      final r = parse({
        'title': 'Connect',
        'fields': [
          {'id': 'user', 'label': 'User', 'type': 'text', 'default': 'admin'},
          {'id': 'pw', 'label': 'Password', 'type': 'secret', 'required': true, 'default': 'leaked'},
          {
            'id': 'q',
            'label': 'Quality',
            'type': 'select',
            'options': [
              {'value': 'low', 'label': 'Low'},
              'high',
            ],
          },
        ],
      });
      expect(r.fields.map((f) => f.type), [UserInputType.text, UserInputType.secret, UserInputType.select]);
      expect(r.fields[1].defaultValue, isNull, reason: 'a secret has no default the model knows');
      expect(r.fields[2].options.map((o) => o.label), ['Low', 'high']);
    });

    test('is refused when it cannot be shown', () {
      for (final bad in <Map<String, Object?>>[
        {'fields': []},
        {'title': 't', 'fields': []},
        {'title': 't', 'fields': [for (var i = 0; i < 11; i++) {'id': '$i', 'label': 'x', 'type': 'text'}]},
        {'title': 't', 'fields': [{'id': 'a', 'label': 'x', 'type': 'text'}, {'id': 'a', 'label': 'y', 'type': 'text'}]},
        {'title': 't', 'fields': [{'id': 'a', 'label': 'x', 'type': 'date'}]},
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
