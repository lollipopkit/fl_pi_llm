// An app that offers a locale this package has no strings for got a null from
// `LlmLocalizations.of` where it sets them, and its first frame threw: Server
// Box in Italian opened on a blank page (lollipopkit/flutter_server_box#1643).
import 'package:fl_pi_llm_ui/generated/l10n/llm_l10n.dart';
import 'package:fl_pi_llm_ui/generated/l10n/llm_l10n_en.dart';
import 'package:fl_pi_llm_ui/src/res/l10n.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _setIn(WidgetTester tester, Locale locale) => tester.pumpWidget(
  Localizations(
    locale: locale,
    delegates: const [
      LlmLocalizations.delegate,
      DefaultWidgetsLocalizations.delegate,
    ],
    child: Builder(
      builder: (context) {
        context.setLlmL10n();
        return const SizedBox();
      },
    ),
  ),
);

void main() {
  testWidgets('a locale without strings falls back to English', (tester) async {
    await _setIn(tester, const Locale('fi'));
    expect(tester.takeException(), isNull);
    expect(llmL10n, isA<LlmLocalizationsEn>());
  });

  testWidgets('a supported locale gets its own strings', (tester) async {
    await _setIn(tester, const Locale('it'));
    expect(llmL10n.localeName, 'it');
  });
}
