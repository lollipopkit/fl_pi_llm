import 'dart:convert';

import 'package:fl_lib/fl_lib.dart';
import 'package:fl_pi_llm/fl_pi_llm.dart';
import 'package:fl_pi_llm_ui/src/core/credentials.dart';
import 'package:fl_pi_llm_ui/src/store/stores.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(SqliteDb.openInMemory);
  tearDown(SqliteDb.close);

  const creds = StoreCredentials.instance;

  test('a key is kept apart from a sign-in, which stays on the device', () async {
    await creds.write('openai', LlmCredential.apiKey('sk-1'));
    await creds.write('github-copilot', const LlmCredential({'type': 'oauth', 'refresh': 'r'}));

    expect((await creds.read('openai'))?.key, 'sk-1');
    expect((await creds.read('github-copilot'))?.type, 'oauth');
    expect(await creds.list(), unorderedEquals(['openai', 'github-copilot']));
    final store = LlmStores.credential;
    expect(store.isDeviceLocalKey('github-copilot.oauth'), isTrue);
    expect(store.isDeviceLocalKey('openai'), isFalse);

    // A key replacing the sign-in takes its place.
    await creds.write('github-copilot', LlmCredential.apiKey('k'));
    expect(store.keys(), {'openai', 'github-copilot'});

    await creds.delete('github-copilot');
    expect(await creds.list(), ['openai']);
  });

  test('what the keychain held is moved into the store', () async {
    FlutterSecureStorage.setMockInitialValues({
      'llm.credentialIds': json.encode(['openai']),
      'llm.credential.openai': json.encode(LlmCredential.apiKey('sk-old').json),
    });

    await StoreCredentials.adoptKeychain();

    expect((await creds.read('openai'))?.key, 'sk-old');
    expect(await SecureStore.storage.readAll(), isEmpty);
  });
}
