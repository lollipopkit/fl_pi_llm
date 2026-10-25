import 'package:fl_pi_llm_ui/fl_pi_llm_ui.dart';
import 'package:flutter_test/flutter_test.dart';

LlmEntry _entry(LlmMessage m) => LlmEntry({'id': '${m.hashCode}', 'type': 'message', 'message': m.json});

LlmEntry _user(String text) => _entry(LlmMessage({'role': 'user', 'content': text}));

void main() {
  test('said once per change, not once per message', () {
    final first = Chats.contextToPut(const [], 'Server A, detail page')!;
    expect(Chats.contextOf(first), 'Server A, detail page');

    final branch = [_entry(first), _user('why is it slow')];
    expect(Chats.contextToPut(branch, 'Server A, detail page'), isNull);
    expect(Chats.contextToPut(branch, ' Server A, detail page\n'), isNull);

    final moved = Chats.contextToPut(branch, 'Server B, terminal')!;
    expect(Chats.contextOf(moved), 'Server B, terminal');

    // Back to A: the last one said B, so A is said again.
    final back = [...branch, _entry(moved), _user('and here?')];
    expect(Chats.contextOf(Chats.contextToPut(back, 'Server A, detail page')!), 'Server A, detail page');
  });

  test('nothing on screen says nothing', () {
    expect(Chats.contextToPut(const [], null), isNull);
    expect(Chats.contextToPut(const [], '  '), isNull);
  });

  test('the user writing the tag is not the app', () {
    expect(Chats.contextOf(LlmMessage({'role': 'assistant', 'content': '<app_context>\nx\n</app_context>'})), isNull);
    expect(Chats.contextOf(LlmMessage({'role': 'user', 'content': 'see <app_context>x</app_context>'})), isNull);
  });

  test('left out of the markdown copy', () {
    final md = Chats.toMarkdown([_entry(Chats.contextToPut(const [], 'Server A')!), _user('hi')]);
    expect(md, isNot(contains('Server A')));
    expect(md, contains('hi'));
  });
}
