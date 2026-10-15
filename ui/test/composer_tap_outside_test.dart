import 'package:fl_pi_llm_ui/fl_pi_llm_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a touch outside the composer puts the keyboard away', (tester) async {
    final ctrl = TextEditingController();
    final focus = FocusNode();
    addTearDown(ctrl.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(child: SizedBox.expand(key: Key('chat'))),
              ComposerBox(
                controller: ctrl,
                focusNode: focus,
                hint: 'Message',
                onSubmit: () {},
                button: IconButton(key: const Key('send'), icon: const Icon(Icons.send), onPressed: () {}),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focus.hasFocus, isTrue);

    // Its own buttons are inside: sending keeps the keyboard up.
    await tester.tap(find.byKey(const Key('send')));
    await tester.pump();
    expect(focus.hasFocus, isTrue);

    await tester.tap(find.byKey(const Key('chat')));
    await tester.pump();
    expect(focus.hasFocus, isFalse);
  });
}
