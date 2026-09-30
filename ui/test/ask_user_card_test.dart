import 'package:fl_lib/fl_lib.dart';
import 'package:fl_pi_llm_ui/src/core/user_input.dart';
import 'package:fl_pi_llm_ui/src/view/ask_user_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  final request = UserInputRequest.parse({
    'title': 'Set up',
    'questions': [
      {
        'id': 'db',
        'question': 'Which database?',
        'header': 'Database',
        'options': [
          {'label': 'PostgreSQL', 'description': 'Relational.'},
          {'label': 'SQLite'},
        ],
      },
      {
        'id': 'feat',
        'question': 'Which features?',
        'multi_select': true,
        'options': ['Backup', 'Alerts'],
      },
    ],
    'fields': [
      {'id': 'pw', 'label': 'Password', 'type': 'secret', 'required': true},
    ],
  });

  Future<PendingInput> pump(WidgetTester tester) async {
    final pending = PendingInput('chat', request);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: AskUserCard(pending: pending)))));
    return pending;
  }

  testWidgets('each question must be answered, and a secret leaves as a handle', (tester) async {
    final pending = await pump(tester);
    await tester.tap(find.text(libL10n.ok));
    await tester.pump();
    expect(pending.done, isFalse, reason: 'nothing chosen yet');

    await tester.tap(find.text('SQLite'));
    await tester.tap(find.text('Backup'));
    await tester.tap(find.text('Alerts'));
    // An answer of the user's own, beside the options chosen.
    await tester.tap(find.text('Other').last);
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'Tracing');
    await tester.enterText(find.byType(TextField).last, 'hunter2');
    await tester.tap(find.text(libL10n.ok));
    await tester.pump();

    final answer = await pending.answer as UserInputSubmitted;
    expect(answer.answers['db'], 'SQLite');
    expect(answer.answers['feat'], ['Backup', 'Alerts', {'other': 'Tracing'}]);
    final pw = answer.values['pw'] as Map;
    expect(pw['secret'], startsWith('sec_'));
    expect(LlmSecrets.take('chat', pw), 'hunter2');
  });

  testWidgets('a single choice: its own answer replaces the option', (tester) async {
    final pending = await pump(tester);
    await tester.tap(find.text('PostgreSQL'));
    await tester.tap(find.text('Other').first);
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'MySQL');
    await tester.tap(find.text('Backup'));
    await tester.enterText(find.byType(TextField).last, 'pw');
    await tester.tap(find.text(libL10n.ok));
    await tester.pump();
    final answer = await pending.answer as UserInputSubmitted;
    expect(answer.answers['db'], {'other': 'MySQL'});
  });

  testWidgets('cancel', (tester) async {
    final pending = await pump(tester);
    await tester.tap(find.text(libL10n.cancel));
    expect(await pending.answer, isA<UserInputCancelled>());
  });
}
