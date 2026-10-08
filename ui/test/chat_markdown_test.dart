import 'package:fl_pi_llm_ui/src/view/message.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _reply = '''
Run it like this:

```sh
echo selectable
```

Then check the output.
''';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) =>
      tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))));

  /// Whether the `RichText` drawing [text] takes part in a selection area.
  bool selectable(WidgetTester tester, String text) => tester
      .widget<RichText>(find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains(text)))
      .selectionRegistrar != null;

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS, TargetPlatform.macOS]) {
    testWidgets('a reply, its code included, can be selected on ${platform.name}', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await pump(tester, const ChatMarkdown(_reply));
        expect(find.byType(SelectionArea), findsOneWidget);
        expect(selectable(tester, 'Run it like this'), isTrue);
        expect(selectable(tester, 'echo selectable'), isTrue);
        expect(selectable(tester, 'Then check the output'), isTrue);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets('a capture is not selectable', (tester) async {
    await pump(tester, const ChatMarkdown(_reply, forCapture: true));
    expect(find.byType(SelectionArea), findsNothing);
  });

  testWidgets('a language the highlighter does not know is shown plain', (tester) async {
    await pump(tester, const ChatMarkdown('```no-such-language\nplain text\n```'));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('plain text', findRichText: true), findsOneWidget);
  });
}
