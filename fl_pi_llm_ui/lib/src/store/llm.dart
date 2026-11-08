import 'package:fl_lib/fl_lib.dart';
import 'package:fl_pi_llm/fl_pi_llm.dart';
import 'package:fl_pi_llm_ui/src/store/llm_credential.dart';

/// Which models to use, and the providers the user added. Keys are not here:
/// they are in [LlmCredentialStore].
final class LlmStore extends SqliteStore {
  LlmStore._() : super('llm');

  static final instance = LlmStore._();

  static const _providerPrefix = 'provider.';

  /// Whether [key] holds one of [customProviders].
  static bool isProviderKey(String key) => key.startsWith(_providerPrefix) || key == _legacyProvidersKey;

  /// The providers the user added, by name: one record each, so that two
  /// devices adding one each keep both when they sync.
  List<LlmCustomProvider> get customProviders {
    final out = <LlmCustomProvider>[];
    for (final k in keys()) {
      if (!k.startsWith(_providerPrefix)) continue;
      final raw = get<Object>(k);
      if (raw is! Map) continue;
      try {
        out.add(LlmCustomProvider.fromJson(raw.cast<String, Object?>()));
      } catch (e) {
        Loggers.app.warning('Custom provider $k is unreadable', e);
      }
    }
    return out..sort((a, b) {
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return byName != 0 ? byName : a.id.compareTo(b.id);
    });
  }

  LlmCustomProvider? customProvider(String id) {
    final raw = get<Object>('$_providerPrefix$id');
    return raw is Map ? LlmCustomProvider.fromJson(raw.cast<String, Object?>()) : null;
  }

  void putCustomProvider(LlmCustomProvider provider) => set('$_providerPrefix${provider.id}', provider.toStoreJson());

  void removeCustomProvider(String id) => remove('$_providerPrefix$id');

  /// Moves the providers builds before kept as one list, here or as another
  /// device sent it, into a record each, and drops the list (as no edit:
  /// nothing is sent). Each moved as [adopt] writes it: one already here
  /// stays, and any edit made since wins over it.
  /// TODO: remove once no device or log holds the list.
  void splitLegacyProviders(void Function(SqliteStore store, String key, Object value) adopt) {
    final raw = get<Object>(_legacyProvidersKey);
    if (raw == null) return;
    SqliteStore.transact(() {
      for (final p in raw is List ? raw : const []) {
        if (p is! Map || p['id'] is! String) continue;
        final key = '$_providerPrefix${p['id']}';
        if (get<Object>(key) == null) adopt(this, key, p.cast<String, Object?>());
      }
      remove(_legacyProvidersKey, updateLastUpdateTsOnRemove: false);
    });
  }

  /// TODO: remove with [splitLegacyProviders].
  static const _legacyProvidersKey = 'customProviders';

  /// What a new chat talks to.
  late final defaultModel = property<LlmModelRef>(
    'defaultModel',
    fromObj: (o) => o is Map ? LlmModelRef.fromJson(o.cast<String, Object?>()) : null,
    toObj: (r) => r?.toJson(),
  );

  /// What names chats; the chat's own model when null.
  late final titleModel = property<LlmModelRef>(
    'titleModel',
    fromObj: (o) => o is Map ? LlmModelRef.fromJson(o.cast<String, Object?>()) : null,
    toObj: (r) => r?.toJson(),
  );

  /// Models pinned to the top of the picker.
  late final favoriteModels = listProperty<String>('favoriteModels');

  late final systemPrompt = propertyDefault('systemPrompt', '');

  /// A [ThinkingLevel] name.
  late final thinkingLevel = propertyDefault('thinkingLevel', ThinkingLevel.medium.name);

  late final compaction = propertyDefault('compaction', true);
}
