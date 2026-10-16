/// A provider's credential, as pi-ai takes it.
final class LlmCredential {
  const LlmCredential(this.json);

  /// An API key, with the provider settings pi-ai reads from the environment
  /// elsewhere — an Azure resource, a Cloudflare account.
  factory LlmCredential.apiKey(String key, {Map<String, String>? env}) =>
      LlmCredential({'type': 'api_key', 'key': key, 'env': ?env});

  final Map<String, Object?> json;

  String get type => json['type'] as String? ?? 'api_key';
  String? get key => json['key'] as String?;
  Map<String, String>? get env => (json['env'] as Map?)?.cast<String, String>();
}

/// Where credentials are kept. An app keeps them in the platform's keychain;
/// they reach the runtime only when a request needs them.
abstract interface class LlmCredentials {
  Future<LlmCredential?> read(String providerId);

  /// Providers that have a credential.
  Future<List<String>> list();

  /// pi-ai writes back what it refreshes, such as an OAuth token.
  Future<void> write(String providerId, LlmCredential credential);

  Future<void> delete(String providerId);
}

/// Credentials in memory. For tests.
final class MemoryCredentials implements LlmCredentials {
  MemoryCredentials([Map<String, LlmCredential>? initial]) : _m = {...?initial};

  final Map<String, LlmCredential> _m;

  @override
  Future<LlmCredential?> read(String providerId) async => _m[providerId];

  @override
  Future<List<String>> list() async => [..._m.keys];

  @override
  Future<void> write(String providerId, LlmCredential credential) async => _m[providerId] = credential;

  @override
  Future<void> delete(String providerId) async => _m.remove(providerId);
}
