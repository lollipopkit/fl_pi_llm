import 'package:fl_lib/fl_lib.dart';
import 'package:fl_pi_llm/fl_pi_llm.dart';
import 'package:fl_pi_llm_ui/src/res/l10n.dart';
import 'package:fl_pi_llm_ui/src/view/message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'library.dart';

var _seq = 0;

LlmEntry _entry(Map<String, Object?> m) => LlmEntry({'id': '${_seq++}', 'type': 'message', 'message': m});

List<LlmEntry> _call(String id, String arg, {bool answered = true}) => [
  _entry({
    'role': 'assistant',
    'stopReason': 'toolUse',
    'content': [
      {'type': 'thinking', 'thinking': 'think $arg'},
      {'type': 'toolCall', 'id': id, 'name': 'probe', 'arguments': {'x': arg}},
    ],
  }),
  if (answered) _entry({'role': 'toolResult', 'toolCallId': id, 'toolName': 'probe', 'content': 'ok $arg'}),
];

LlmEntry _text(String text) => _entry({
  'role': 'assistant',
  'stopReason': 'stop',
  'content': [
    {'type': 'text', 'text': text},
  ],
});

void main() {
  setUpAll(loadLlmLibrary);

  Future<void> pump(WidgetTester tester, List<LlmEntry> entries, {bool live = true, bool forCapture = false}) =>
      tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ThreadBlockView(chat: null, block: ReplyBlock(entries), live: live, forCapture: forCapture),
        ),
      ),
    ),
  );

  testWidgets('tool calls in a row are one card, opened to every step', (tester) async {
    await pump(tester, [..._call('a', 'first'), ..._call('b', 'second'), _text('done'), ..._call('c', 'third')]);
    expect(find.text(llmL10n.toolCallsFmt(2)), findsOneWidget);
    expect(find.text('{"x":"second"}'), findsOneWidget);
    expect(find.text('{"x":"first"}'), findsNothing);
    expect(find.text('done'), findsOneWidget);
    // One call after the text stands alone.
    expect(find.text('{"x":"third"}'), findsOneWidget);

    await tester.tap(find.text(llmL10n.toolCallsFmt(2)));
    await tester.pump();
    expect(find.text('{"x":"first"}'), findsOneWidget);
    expect(find.text('{"x":"second"}'), findsNWidgets(2));
  });

  testWidgets('a call opened before the next one arrives stays open in the card', (tester) async {
    final first = _call('a', 'first');
    await pump(tester, first);
    await tester.tap(find.text('{"x":"first"}'));
    await tester.pump();
    expect(find.text('ok first'), findsOneWidget);

    await pump(tester, [...first, ..._call('b', 'second')]);
    expect(find.text(llmL10n.toolCallsFmt(2)), findsOneWidget);
    expect(find.text('ok first'), findsOneWidget);
    expect(find.text('ok second'), findsNothing);
  });

  testWidgets('calls a finished reply never got answers to read as stopped', (tester) async {
    await pump(tester, [..._call('a', 'first', answered: false), ..._call('b', 'second', answered: false)], live: false);
    expect(find.byIcon(Icons.remove_circle_outline), findsOneWidget);
    expect(find.byType(SizedLoading), findsNothing);
  });

  testWidgets('a capture shows every call', (tester) async {
    await pump(tester, [..._call('a', 'first'), ..._call('b', 'second')], live: false, forCapture: true);
    expect(find.text(llmL10n.toolCallsFmt(2)), findsNothing);
    expect(find.text('{"x":"first"}'), findsOneWidget);
    expect(find.text('{"x":"second"}'), findsOneWidget);
  });
}
