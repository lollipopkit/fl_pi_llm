import 'package:fl_pi_llm/fl_pi_llm.dart';
import 'package:fl_pi_llm_ui/src/core/system_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const gateway = {
    'OPENAI_BASE_URL': 'https://gateway.example/v1',
    'OPENAI_API_KEY': 'sk-gateway',
    'OPENAI_MODEL': 'qwen',
    'ANTHROPIC_API_KEY': 'sk-ant',
  };

  test('OPENAI_BASE_URL makes a provider, with the model named beside it', () {
    final p = SystemProvider.of(gateway)!;
    expect(p.id, SystemProvider.id);
    expect(p.api, LlmApi.openaiCompletions);
    expect(p.baseUrl, 'https://gateway.example/v1');
    expect(p.models, ['qwen']);
    expect(SystemProvider.of(const {'OPENAI_API_KEY': 'sk'}), isNull);
    expect(SystemProvider.of(const {'OPENAI_BASE_URL': 'not a url'}), isNull);
  });

  test("a gateway's key is not handed to OpenAI", () {
    expect(SystemProvider.forBuiltins(gateway), isNot(contains('OPENAI_API_KEY')));
    expect(SystemProvider.forBuiltins(gateway)['ANTHROPIC_API_KEY'], 'sk-ant');
    // Pointing at OpenAI itself, the key is OpenAI's as well.
    const openai = {'OPENAI_BASE_URL': 'https://api.openai.com/v1', 'OPENAI_API_KEY': 'sk'};
    expect(SystemProvider.forBuiltins(openai)['OPENAI_API_KEY'], 'sk');
    expect(SystemProvider.forBuiltins(const {'OPENAI_API_KEY': 'sk'})['OPENAI_API_KEY'], 'sk');
  });

  test('its credential is the environment, never stored', () async {
    final inner = MemoryCredentials({'anthropic': LlmCredential.apiKey('stored')});
    var env = Map<String, String>.of(gateway);
    final creds = SystemCredentials(inner, () => env);

    expect(await creds.list(), unorderedEquals(['anthropic', SystemProvider.id]));
    expect((await creds.read(SystemProvider.id))!.key, 'sk-gateway');
    await creds.write(SystemProvider.id, LlmCredential.apiKey('other'));
    expect(await inner.list(), ['anthropic']);

    // A local server with no key is still usable.
    env = {'OPENAI_BASE_URL': 'http://127.0.0.1:11434/v1'};
    expect((await creds.read(SystemProvider.id))!.key, '');
    env = {};
    expect(await creds.list(), ['anthropic']);
    expect(await creds.read(SystemProvider.id), isNull);
  });
}
