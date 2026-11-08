import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:fl_lib/fl_lib.dart';
import 'package:fl_pi_llm/fl_pi_llm.dart';
import 'package:fl_pi_llm_ui/src/store/llm_credential.dart';
import 'package:fl_pi_llm_ui/src/store/stores.dart';

/// Provider credentials in [LlmCredentialStore].
final class StoreCredentials implements LlmCredentials {
  const StoreCredentials();

  static const instance = StoreCredentials();

  static LlmCredentialStore get _store => LlmStores.credential;

  static String _signIn(String providerId) => '$providerId${LlmCredentialStore.oauthSuffix}';

  @override
  Future<LlmCredential?> read(String providerId) async {
    final raw = _store.get<Object>(_signIn(providerId)) ?? _store.get<Object>(providerId);
    if (raw is! Map) return null;
    return LlmCredential(raw.cast<String, Object?>());
  }

  @override
  Future<List<String>> list() async => {
    for (final k in _store.keys())
      k.endsWith(LlmCredentialStore.oauthSuffix) ? k.substring(0, k.length - LlmCredentialStore.oauthSuffix.length) : k,
  }.toList();

  /// An API key under the provider's id, anything else as this device's
  /// sign-in; the other one goes.
  @override
  Future<void> write(String providerId, LlmCredential credential) async {
    final (keep, drop) = credential.type == 'api_key' ? (providerId, _signIn(providerId)) : (_signIn(providerId), providerId);
    SqliteStore.transact(() {
      _store.set(keep, credential.json);
      _store.remove(drop);
    });
  }

  @override
  Future<void> delete(String providerId) async {
    SqliteStore.transact(() {
      _store.remove(providerId);
      _store.remove(_signIn(providerId));
    });
  }

  /// Moves what builds before kept in the keychain into the store, and
  /// removes it there; once, or again at the next launch when the keychain
  /// fails.
  /// TODO: remove with [_adopted] once no install can still hold them.
  static Future<void> adoptKeychain() async {
    if (_adopted.get()) return;
    try {
      final raw = await SecureStore.storage.read(key: _legacyIndex);
      final ids = raw == null
          ? [
              for (final k in (await SecureStore.storage.readAll()).keys)
                if (k.startsWith(_legacyPrefix)) k.substring(_legacyPrefix.length),
            ]
          : [for (final id in json.decode(raw) as List) id as String];
      for (final id in ids) {
        final value = await SecureStore.storage.read(key: '$_legacyPrefix$id');
        if (value != null && await instance.read(id) == null) {
          try {
            final credential = LlmCredential((json.decode(value) as Map).cast<String, Object?>());
            final key = credential.type == 'api_key' ? id : _signIn(id);
            adopt(_store, key, credential.json);
          } catch (e) {
            // Not one this reads: left out, and the rest still moved.
            Loggers.app.warning('Credential of $id is unreadable', e);
          }
        }
        await SecureStore.storage.delete(key: '$_legacyPrefix$id');
      }
      await SecureStore.storage.delete(key: _legacyIndex);
      await _adopted.set(true);
    } catch (e, s) {
      Loggers.app.warning('Move provider credentials out of the keychain', e, s);
    }
  }

  /// Makes each write [adoptKeychain] does. A host that syncs the store sets
  /// it, so what is moved in counts as no device's edit and loses to any
  /// made since.
  /// TODO: remove with [adoptKeychain].
  static void Function(SqliteStore store, String key, Object value) adopt = _set;

  static void _set(SqliteStore store, String key, Object value) => store.set(key, value);

  static const _adopted = PrefPropDefault('llm_credentials_adopted', false, updateLastUpdateTsOnSetProp: false);

  static const _legacyPrefix = 'llm.credential.';
  static const _legacyIndex = 'llm.credentialIds';
}

/// What the chats are encrypted with ([FlPiLlm.start]): 32 random bytes in
/// the platform's keychain, made the first time. Never in a backup: a backup
/// carries the chats themselves, under its own password.
abstract final class ChatKey {
  static const _key = 'llm.chatKey';

  /// One read at a time, for every caller: two first reads would each make
  /// a key.
  static Future<Uint8List>? _reading;

  /// [encryptedChats]: chats are encrypted already, with the key the
  /// keychain should hold. Then a missing one is an error: a key made in its
  /// place would open none of them.
  static Future<Uint8List> read({required bool encryptedChats}) => _reading ??= _read(encryptedChats).catchError((Object e) {
    _reading = null;
    throw e;
  });

  static Future<Uint8List> _read(bool encryptedChats) async {
    final existing = await SecureStore.storage.read(key: _key);
    if (existing != null) return _decode(existing);
    if (encryptedChats) throw StateError('The chat key is missing from the keychain, and the chats are encrypted with it');
    final random = Random.secure();
    await SecureStore.storage.write(key: _key, value: base64UrlEncode([for (var i = 0; i < 32; i++) random.nextInt(256)]));
    // Read back: a write that did not land would leave chats nothing can open.
    final confirmed = await SecureStore.storage.read(key: _key);
    if (confirmed == null) throw StateError('Failed to keep the chat key');
    return _decode(confirmed);
  }

  /// Never replaced when unreadable: the chats encrypted with it would be
  /// lost with it.
  static Uint8List _decode(String stored) {
    final key = base64Url.decode(stored);
    if (key.length != 32) throw StateError('The chat key in the keychain is ${key.length} bytes, not 32');
    return key;
  }
}
