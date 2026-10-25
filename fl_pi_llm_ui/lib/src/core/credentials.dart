import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:fl_lib/fl_lib.dart';
import 'package:fl_pi_llm/fl_pi_llm.dart';

/// Provider credentials in the platform's keychain.
final class KeychainCredentials implements LlmCredentials {
  const KeychainCredentials();

  static const instance = KeychainCredentials();

  static const _prefix = 'llm.credential.';

  @override
  Future<LlmCredential?> read(String providerId) async {
    final raw = await SecureStore.storage.read(key: '$_prefix$providerId');
    if (raw == null) return null;
    try {
      return LlmCredential((json.decode(raw) as Map).cast<String, Object?>());
    } catch (e) {
      Loggers.app.warning('Credential of $providerId is unreadable', e);
      return null;
    }
  }

  /// The providers with a credential. Kept beside them so listing does not
  /// read every secret in the keychain into memory.
  static const _indexKey = 'llm.credentialIds';

  @override
  Future<List<String>> list() async {
    final raw = await SecureStore.storage.read(key: _indexKey);
    if (raw != null) {
      try {
        return [for (final id in json.decode(raw) as List) id as String];
      } catch (e) {
        Loggers.app.warning('Credential index is unreadable', e);
      }
    }
    // TODO: remove once every install has the index (it was added after
    // the first release on fl_pi_llm): built from a full read, once.
    final all = await SecureStore.storage.readAll();
    final ids = [
      for (final k in all.keys)
        if (k.startsWith(_prefix)) k.substring(_prefix.length),
    ];
    await _saveIndex(ids);
    return ids;
  }

  static Future<void> _saveIndex(List<String> ids) =>
      SecureStore.storage.write(key: _indexKey, value: json.encode(ids.toSet().toList()..sort()));

  /// Writes and deletes one after another, each with its index update: two
  /// at once would each save an index without what the other did.
  static Future<void> _changing = Future.value();

  static Future<void> _change(Future<void> Function() fn) {
    final next = _changing.then((_) => fn());
    _changing = next.catchError((_) {});
    return next;
  }

  @override
  Future<void> write(String providerId, LlmCredential credential) => _change(() async {
    await SecureStore.storage.write(key: '$_prefix$providerId', value: json.encode(credential.json));
    await _saveIndex([...await list(), providerId]);
  });

  @override
  Future<void> delete(String providerId) => _change(() async {
    await SecureStore.storage.delete(key: '$_prefix$providerId');
    await _saveIndex([...(await list()).where((e) => e != providerId)]);
  });
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
