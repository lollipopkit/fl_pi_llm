import 'package:fl_pi_llm/fl_pi_llm.dart';
import 'package:test/test.dart';

void main() {
  bool allowed(String url, [Set<String> insecure = const {}]) =>
      FlPiLlm.fetchAllowed(Uri.parse(url), insecure);

  test('https goes anywhere', () {
    expect(allowed('https://api.openai.com/v1/chat/completions'), isTrue);
    expect(allowed('https://10.0.0.2:8443/v1'), isTrue);
  });

  test('plain http goes only to this device', () {
    expect(allowed('http://localhost:11434/v1'), isTrue);
    expect(allowed('http://127.0.0.1:8080/v1'), isTrue);
    expect(allowed('http://127.1.2.3/v1'), isTrue);
    expect(allowed('http://[::1]:8080/v1'), isTrue);
    // The key would cross the network readable.
    expect(allowed('http://192.168.1.5:11434/v1'), isFalse);
    expect(allowed('http://api.example.com/v1'), isFalse);
  });

  test('or to an origin a provider was allowed', () {
    const lan = {'http://192.168.1.5:11434'};
    expect(allowed('http://192.168.1.5:11434/v1/models', lan), isTrue);
    // The origin, not the host: another port is another service.
    expect(allowed('http://192.168.1.5:8080/v1', lan), isFalse);
    expect(allowed('http://192.168.1.6:11434/v1', lan), isFalse);
  });

  test('and nothing else is fetched', () {
    expect(allowed('ftp://example.com/x'), isFalse);
    expect(allowed('file:///etc/passwd'), isFalse);
  });

  test('a provider keeps the allowance through storage', () {
    const p = LlmCustomProvider(
      id: 'lan',
      name: 'lan',
      api: LlmApi.openaiCompletions,
      baseUrl: 'http://192.168.1.5:11434/v1',
      allowInsecure: true,
    );
    expect(LlmCustomProvider.fromJson(p.toStoreJson()).allowInsecure, isTrue);
    // Off by default, and not written when off.
    const off = LlmCustomProvider(id: 'x', name: 'x', api: LlmApi.openaiCompletions, baseUrl: 'https://x/v1');
    expect(off.toStoreJson().containsKey('allowInsecure'), isFalse);
    expect(LlmCustomProvider.fromJson(off.toStoreJson()).allowInsecure, isFalse);
  });
}
