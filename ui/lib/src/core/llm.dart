import 'dart:async';

import 'package:fl_lib/fl_lib.dart';
import 'package:fl_pi_llm/fl_pi_llm.dart';
import 'package:fl_pi_llm_ui/src/core/credentials.dart';
import 'package:fl_pi_llm_ui/src/skills/skills.dart';
import 'package:fl_pi_llm_ui/src/core/session_store.dart';
import 'package:fl_pi_llm_ui/src/core/system_provider.dart';
import 'package:fl_pi_llm_ui/src/store/stores.dart';

/// The app's one fl_pi_llm runtime, and what it knows about providers.
abstract final class Llm {
  static FlPiLlm? _rt;

  static FlPiLlm get rt {
    final rt = _rt;
    if (rt == null) throw StateError('Llm.init() has not completed');
    return rt;
  }

  /// Every provider and its models, as last read.
  static final providers = <LlmProviderInfo>[].vn;

  /// Providers with a key: one in the keychain, or one in the environment.
  static final configured = <String>{}.vn;

  /// Providers whose key comes from the environment, and the variable it is
  /// in (`OPENAI_API_KEY`): a desktop app started from a shell has what that
  /// shell exported, with nothing entered in the app.
  static final envAuth = <String, String>{}.vn;

  static LlmCredentials _credentials = KeychainCredentials.instance;

  static Map<String, String> Function() _environment = SystemProvider.platform;

  /// What the runtime asks: the stored ones, and the system provider's.
  static late LlmCredentials _all;

  /// The provider the environment describes (`OPENAI_BASE_URL`), if it does.
  static LlmCustomProvider? get system => SystemProvider.of(_environment());

  /// After the stores: sessions live in the same encrypted database.
  ///
  /// [credentials] and [externalLibrary] are for tests, which have neither a
  /// keychain nor an app bundle.
  ///
  /// [environment] replaces the process's, where [FlPiLlm] reads a provider's
  /// key when none is stored.
  static Future<void> init({
    LlmCredentials? credentials,
    ExternalLibrary? externalLibrary,
    Map<String, String> Function()? environment,
  }) async {
    if (credentials != null) _credentials = credentials;
    if (environment != null) _environment = environment;
    _all = SystemCredentials(_credentials, () => _environment());
    _rt ??= await FlPiLlm.start(
      store: SqlitePiSessionStore.instance,
      credentials: _all,
      externalLibrary: externalLibrary,
      environment: () => SystemProvider.forBuiltins(_environment()),
      logger: (level, msg) => switch (level) {
        'error' => Loggers.app.warning('[llm] $msg'),
        'warn' => Loggers.app.info('[llm] $msg'),
        _ => Loggers.app.fine('[llm] $msg'),
      },
    );
    await applyCustomProviders();
    // Once a day at most, in the background: marks the skills whose source
    // changed, and installs nothing.
    unawaited(Skills.check().then<void>((_) {}, onError: (Object e, StackTrace s) => Loggers.app.warning('Check skills', e, s)));
    // The network part runs behind: the cached lists are already usable.
    unawaited(refresh().catchError((Object e, StackTrace s) {
      Loggers.app.warning('Refresh models', e, s);
      return const <String, String>{};
    }));
  }

  /// Hands the stored custom providers to the runtime.
  static Future<void> applyCustomProviders() async {
    if (_rt == null) return;
    try {
      await rt.setCustomProviders([...?LlmStores.llm.customProviders.get(), ?system]);
    } catch (e, s) {
      Loggers.app.warning('Apply custom providers', e, s);
    }
    await reload();
  }

  /// Rereads the catalog and which providers have a key.
  static Future<void> reload() async {
    providers.value = await rt.providers();
    await _reloadAuth();
  }

  static Future<void> _reloadAuth() async {
    final stored = (await _all.list()).toSet();
    var sources = const <String, String>{};
    try {
      sources = await rt.authSources();
    } catch (e, s) {
      Loggers.app.warning('Provider auth', e, s);
    }
    envAuth.value = {
      for (final MapEntry(:key, :value) in sources.entries)
        if (!stored.contains(key) && RegExp(r'^[A-Z][A-Z0-9_]*$').hasMatch(value)) key: value,
    };
    configured.value = {...stored, ...envAuth.value.keys};
  }

  /// Why the last listing of a provider's models failed, by provider id.
  static final modelErrors = <String, String>{}.vn;

  /// Lists the models of dynamic providers again. Returns the errors.
  static Future<Map<String, String>> refresh({List<String>? only, bool force = false}) async {
    final errors = await rt.refreshModels(providers: only, force: force);
    for (final MapEntry(:key, :value) in errors.entries) {
      Loggers.app.info('Models of $key: $value');
    }
    modelErrors.value = {
      for (final e in modelErrors.value.entries)
        if (only != null && !only.contains(e.key)) e.key: e.value,
      ...errors,
    };
    await reload();
    return errors;
  }

  /// Ids of chats whose session mentions [needle].
  static Future<Set<String>> sessionsContaining(String needle) async {
    final chats = [for (final m in LlmStores.chat.all(anyScope: true)) m.id];
    return {
      for (final path in await SqlitePiSessionStore.instance.search(needle))
        ?SqlitePiSessionStore.chatIdOf(path, chats),
    };
  }

  static LlmModelInfo? info(LlmModelRef? ref) {
    if (ref == null) return null;
    for (final p in providers.value) {
      if (p.id != ref.provider) continue;
      for (final m in p.models) {
        if (m.id == ref.id) return m;
      }
    }
    return null;
  }

  static LlmProviderInfo? provider(String id) => providers.value.firstWhereOrNull((p) => p.id == id);

  /// Models whose provider has a credential, favorites first.
  static List<LlmModelInfo> get usableModels {
    final fav = LlmStores.llm.favoriteModels.get().toSet();
    final out = [
      for (final p in providers.value)
        if (configured.value.contains(p.id)) ...p.models,
    ];
    out.sort((a, b) {
      final fa = fav.contains(a.ref.toString()), fb = fav.contains(b.ref.toString());
      if (fa != fb) return fa ? -1 : 1;
      return 0;
    });
    return out;
  }

  /// What a new chat talks to: the chosen default, or the first usable model.
  static LlmModelRef? get defaultModel => LlmStores.llm.defaultModel.get() ?? usableModels.firstOrNull?.ref;

  static Future<LlmCredential?> readCredential(String providerId) =>
      _credentials.read(providerId);

  static Future<void> setCredential(String providerId, LlmCredential? credential) async {
    if (credential == null) {
      await _credentials.delete(providerId);
    } else {
      await _credentials.write(providerId, credential);
    }
    await _reloadAuth();
  }
}
