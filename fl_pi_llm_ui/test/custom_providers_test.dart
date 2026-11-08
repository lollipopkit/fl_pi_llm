import 'package:fl_lib/fl_lib.dart';
import 'package:fl_pi_llm/fl_pi_llm.dart';
import 'package:fl_pi_llm_ui/src/store/llm.dart';
import 'package:fl_pi_llm_ui/src/store/stores.dart';
import 'package:flutter_test/flutter_test.dart';

LlmCustomProvider _provider(String id, String name) =>
    LlmCustomProvider(id: id, name: name, api: LlmApi.openaiCompletions, baseUrl: 'https://$id.example/v1');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(SqliteDb.openInMemory);
  tearDown(SqliteDb.close);

  final store = LlmStores.llm;

  test('each provider is its own record, so another device adding one keeps both', () {
    store.putCustomProvider(_provider('b', 'Beta'));
    // As a sync writes another device's: a record of its own.
    store.set('provider.a', _provider('a', 'alpha').toStoreJson());

    expect([for (final p in store.customProviders) p.id], ['a', 'b']);
    expect(store.customProvider('b')?.name, 'Beta');

    store.removeCustomProvider('b');
    expect([for (final p in store.customProviders) p.id], ['a']);
    expect(LlmStore.isProviderKey('provider.a'), isTrue);
    expect(LlmStore.isProviderKey('defaultModel'), isFalse);
  });

  test('the list builds before kept is split once, keeping what is here', () {
    store.putCustomProvider(_provider('a', 'Here'));
    store.set('customProviders', [
      _provider('a', 'From the list').toStoreJson(),
      _provider('b', 'Only in the list').toStoreJson(),
    ]);
    final adopted = <String>[];

    store.splitLegacyProviders((s, key, value) {
      adopted.add(key);
      s.set(key, value, updateLastUpdateTsOnSet: false);
    });

    expect(adopted, ['provider.b']);
    expect(store.customProvider('a')?.name, 'Here');
    expect(store.customProvider('b')?.name, 'Only in the list');
    expect(store.get<Object>('customProviders'), isNull);
    expect(LlmStore.isProviderKey('customProviders'), isTrue, reason: 'one another device sends is split too');
  });
}
