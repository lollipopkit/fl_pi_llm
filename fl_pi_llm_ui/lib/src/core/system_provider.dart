import 'dart:io';

import 'package:fl_pi_llm/fl_pi_llm.dart';
import 'package:fl_lib/fl_lib.dart';

/// The provider the environment describes, the way the OpenAI SDKs read it:
/// `OPENAI_BASE_URL` for an OpenAI-compatible endpoint, `OPENAI_API_KEY` for
/// its key, `OPENAI_MODEL` for a model it may not list. Shown as "System",
/// and nothing of it is stored: it is whatever the app was started with.
abstract final class SystemProvider {
  static const id = 'system';

  static const baseUrlVar = 'OPENAI_BASE_URL';
  static const keyVar = 'OPENAI_API_KEY';
  static const modelVar = 'OPENAI_MODEL';

  /// The provider [env] describes, or null without an `OPENAI_BASE_URL`.
  static LlmCustomProvider? of(Map<String, String> env) {
    final base = env[baseUrlVar]?.trim();
    if (base == null || base.isEmpty) return null;
    final u = Uri.tryParse(base);
    if (u == null || u.host.isEmpty || !(u.isScheme('https') || u.isScheme('http'))) return null;
    final model = env[modelVar]?.trim();
    return LlmCustomProvider(
      id: id,
      name: libL10n.system,
      api: LlmApi.openaiCompletions,
      baseUrl: base,
      models: model == null || model.isEmpty ? null : [model],
    );
  }

  /// Whether `OPENAI_API_KEY` is the system provider's rather than OpenAI's:
  /// it goes with an `OPENAI_BASE_URL` that is not OpenAI's own, and sent to
  /// api.openai.com it would be a gateway's key handed to a third party.
  static bool ownsKey(Map<String, String> env) {
    final p = of(env);
    return p != null && Uri.parse(p.baseUrl).host != 'api.openai.com';
  }

  /// [env] as pi-ai's built-in providers may read it: without the key that
  /// belongs to the system provider.
  static Map<String, String> forBuiltins(Map<String, String> env) =>
      ownsKey(env) ? ({...env}..remove(keyVar)) : env;

  static Map<String, String> platform() => Platform.environment;
}

/// [inner], with the system provider's credential: from the environment,
/// never written. An endpoint without a key (a local server) still gets one,
/// empty, as a custom provider set up in the app does.
final class SystemCredentials implements LlmCredentials {
  SystemCredentials(this.inner, this.env);

  final LlmCredentials inner;
  final Map<String, String> Function() env;

  bool get _present => SystemProvider.of(env()) != null;

  @override
  Future<LlmCredential?> read(String providerId) async {
    if (providerId != SystemProvider.id) return inner.read(providerId);
    if (!_present) return null;
    return LlmCredential.apiKey(env()[SystemProvider.keyVar]?.trim() ?? '');
  }

  @override
  Future<List<String>> list() async => [...await inner.list(), if (_present) SystemProvider.id];

  /// Its key is the environment's, which the app does not change.
  @override
  Future<void> write(String providerId, LlmCredential credential) async {
    if (providerId != SystemProvider.id) await inner.write(providerId, credential);
  }

  @override
  Future<void> delete(String providerId) async {
    if (providerId != SystemProvider.id) await inner.delete(providerId);
  }
}
