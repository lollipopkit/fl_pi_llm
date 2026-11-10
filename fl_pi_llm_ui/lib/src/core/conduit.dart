import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:fl_lib/fl_lib.dart';
import 'package:fl_pi_llm/fl_pi_llm.dart';
import 'package:fl_pi_llm_ui/src/core/credentials.dart';
import 'package:fl_pi_llm_ui/src/core/llm.dart';
import 'package:fl_pi_llm_ui/src/store/llm_credential.dart';
import 'package:fl_pi_llm_ui/src/store/stores.dart';
import 'package:flutter/foundation.dart';

/// What [ConduitProvider] needs of the LK Cloud sign-in: [LkcClient].
abstract interface class ConduitAccount {
  /// The signed-in user's id; null when signed out or not read yet.
  ValueListenable<String?> get user;

  Uri get url;

  Future<String> key({required String device, String? deviceName});

  Future<void> drop(String device);

  /// Runs [f] before signing out, while the session still holds. Returns
  /// what takes it back.
  void Function() beforeSignOut(Future<void> Function() f);

  /// Calls [f] whenever the user is known to be signed out. Returns what
  /// takes it back.
  void Function() onSignedOut(void Function() f);
}

final class _LkcAccount implements ConduitAccount {
  _LkcAccount(this.client) {
    void follow() => _user.value = client.user.value?.id;
    client.user.addListener(follow);
    follow();
  }

  final LkcClient client;
  final _user = ValueNotifier<String?>(null);

  @override
  ValueListenable<String?> get user => _user;

  @override
  Uri get url => client.conduitUrl;

  @override
  Future<String> key({required String device, String? deviceName}) =>
      client.conduitKey(device: device, deviceName: deviceName);

  @override
  Future<void> drop(String device) => client.dropConduitKey(device);

  @override
  void Function() beforeSignOut(Future<void> Function() f) {
    client.beforeSignOut.add(f);
    return () => client.beforeSignOut.remove(f);
  }

  @override
  void Function() onSignedOut(void Function() f) {
    client.onSignedOut.add(f);
    return () => client.onSignedOut.remove(f);
  }
}

/// Conduit, LK Cloud's model gateway, as a provider: signed in to LK Cloud,
/// this device gets a key of its own ([LkcClient.conduitKey]) and the models
/// it may use are listed. [LlmStore.conduit] turns it off. The key is this
/// device's ([LlmCredentialStore.isDeviceLocalKey]), never synced, and gone
/// once the user is signed out.
abstract final class ConduitProvider {
  static const id = LlmCredentialStore.conduit;

  /// Stays across keys, so one asked for again replaces the last.
  static const _device = PrefProp<String>('conduit_device');

  /// Whose key the held one is.
  static const _owner = PrefProp<String>('conduit_owner');

  static ConduitAccount? _account;
  static ValueListenable<bool>? _on;
  static final _detach = <void Function()>[];

  /// Why the last key asked for did not come; tried again in a while.
  static final error = ValueNotifier<String?>(null);
  static Timer? _retry;

  /// Signing out: no key is asked for until it is over.
  static bool _ending = false;

  /// The LK Cloud user signed in; null without [attach].
  static ValueListenable<String?>? get user => _account?.user;

  static bool get _held => LlmStores.credential.get<Object>(id) != null;

  /// The provider while this device holds a key.
  static LlmCustomProvider? get provider {
    final account = _account;
    if (account == null || !_held) return null;
    return LlmCustomProvider(
      id: id,
      name: 'Conduit',
      api: LlmApi.openaiCompletions,
      baseUrl: account.url.resolve('/v1').toString(),
    );
  }

  /// Follows [client]'s sign-in from now on; after [Llm.init].
  static void attach(LkcClient client) => attachAccount(_LkcAccount(client));

  @visibleForTesting
  static void attachAccount(ConduitAccount account) {
    detach();
    _account = account;
    account.user.addListener(_follow);
    _on = LlmStores.llm.conduit.listenable()..addListener(_follow);
    _detach
      ..add(account.beforeSignOut(_signingOut))
      ..add(account.onSignedOut(_signedOut));
    // A key held from before is the runtime's only once handed over.
    _run(() async => await _apply() || _held);
  }

  @visibleForTesting
  static void detach() {
    _account?.user.removeListener(_follow);
    _on?.removeListener(_follow);
    for (final f in _detach) {
      f();
    }
    _detach.clear();
    _retry?.cancel();
    _account = null;
    _on = null;
    _ending = false;
    error.value = null;
    _queue = Future.value();
  }

  /// Asks for the key again now, after [error].
  static void retry() => _follow();

  static Future<void> _queue = Future.value();

  /// One change at a time, in order: each asks Conduit at most once.
  static Future<void> _run(Future<bool> Function() f) {
    final next = _queue.then((_) async {
      if (await f() && Llm.started) {
        await Llm.applyCustomProviders();
        // Every custom provider is registered again with only its fixed
        // models: their listings come back on a refresh, as for any edit.
        await Llm.refresh();
      }
    }).catchError((Object e, StackTrace s) => Loggers.app.warning('Conduit', e, s));
    return _queue = next;
  }

  /// Settled once the changes asked for so far are.
  @visibleForTesting
  static Future<void> get settled => _queue;

  static void _follow() => _run(_apply);

  /// A key for the user signed in while it is on; none while it is off or
  /// held for another account.
  static Future<bool> _apply() async {
    final account = _account;
    if (account == null) return false;
    final user = account.user.value;
    final on = LlmStores.llm.conduit.get();
    final owner = _owner.get();
    var changed = false;
    if (_held && (!on || (user != null && owner != user))) {
      // Another account's key is not this one's to end.
      if (user == null || user == owner) await _drop(account);
      await _forget();
      changed = true;
    }
    if (on && user != null && !_held && !_ending) {
      _retry?.cancel();
      final String key;
      try {
        key = await account.key(device: await _deviceId(), deviceName: _deviceName());
      } catch (e, s) {
        Loggers.app.warning('Conduit key', e, s);
        error.value = e is LkcException ? e.message ?? '$e' : '$e';
        _retry = Timer(const Duration(minutes: 5), _follow);
        return changed;
      }
      await StoreCredentials.instance.write(id, LlmCredential.apiKey(key));
      await _owner.set(user);
      error.value = null;
      changed = true;
    }
    if (!on || user == null) error.value = null;
    return changed;
  }

  static Future<void> _signingOut() {
    _ending = true;
    return _run(() async {
      final account = _account;
      if (account == null || !_held) return false;
      await _drop(account);
      await _forget();
      return true;
    });
  }

  /// Signed out without [_signingOut] (the session ended, or was gone at
  /// launch): the key stays at Conduit, listed in its portal, and is
  /// replaced when this device asks for one again.
  static void _signedOut() {
    _ending = false;
    _retry?.cancel();
    error.value = null;
    _run(() async {
      if (!_held) return false;
      await _forget();
      return true;
    });
  }

  /// Gone here even when Conduit is not reached: see [_signedOut].
  static Future<void> _drop(ConduitAccount account) async {
    try {
      await account.drop(await _deviceId());
    } catch (e, s) {
      Loggers.app.warning('Drop the Conduit key', e, s);
    }
  }

  static Future<void> _forget() async {
    await StoreCredentials.instance.delete(id);
    await _owner.remove();
  }

  static Future<String> _deviceId() async {
    if (_device.get() case final id?) return id;
    final rng = Random.secure();
    final id = List.generate(16, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    await _device.set(id);
    return id;
  }

  static String _deviceName() {
    try {
      final host = Platform.localHostname.trim();
      if (host.isNotEmpty && host != 'localhost') return host;
    } catch (_) {}
    return Platform.operatingSystem;
  }
}
