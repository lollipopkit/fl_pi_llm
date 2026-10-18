import 'package:fl_lib/fl_lib.dart';
import 'package:fl_pi_llm_ui/fl_pi_llm_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'library.dart';

LlmProviderInfo _provider(String id, String name, Map<String, String> models) => LlmProviderInfo({
  'id': id,
  'name': name,
  'models': [
    for (final MapEntry(key: mid, value: mname) in models.entries)
      {'provider': id, 'id': mid, 'name': mname, 'contextWindow': 1000000},
  ],
});

void main() {
  setUpAll(loadLlmLibrary);

  setUp(() {
    SqliteDb.openInMemory();
    Llm.providers.value = [
      _provider('deepseek', 'DeepSeek', {'deepseek-flash': 'DeepSeek V4.1 Flash'}),
      _provider('relay', 'Relay', {'deepseek-v4.1-flash': 'DeepSeek V4.1 Flash', 'glm-5.3-flash': 'GLM 5.3 Flash'}),
      _provider('unused', 'Unused', {'glm-5.3-flash': 'GLM 5.3 Flash'}),
    ];
    Llm.configured.value = {'deepseek', 'relay'};
  });

  tearDown(() async {
    Llm.providers.value = [];
    Llm.configured.value = {};
    await SqliteDb.close();
  });

  test('a model is led by its provider only when another usable one has its name', () {
    expect(Llm.modelLabel(const LlmModelRef('deepseek', 'deepseek-flash')), 'DeepSeek · DeepSeek V4.1 Flash');
    expect(Llm.modelLabel(const LlmModelRef('relay', 'deepseek-v4.1-flash')), 'Relay · DeepSeek V4.1 Flash');
    // The other GLM 5.3 Flash has no key: it cannot be picked.
    expect(Llm.modelLabel(const LlmModelRef('relay', 'glm-5.3-flash')), 'GLM 5.3 Flash');
  });

  testWidgets('a favorite says its provider; a model under its provider does not', (tester) async {
    LlmStores.llm.favoriteModels.set(['relay/deepseek-v4.1-flash']);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(onPressed: () => pickModel(context), child: const Text('pick')),
        ),
      ),
    );
    await tester.tap(find.text('pick'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Relay · deepseek-v4.1-flash'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^deepseek-flash')), findsOneWidget);
    expect(find.textContaining(RegExp(r'^glm-5\.3-flash')), findsOneWidget);
  });
}
