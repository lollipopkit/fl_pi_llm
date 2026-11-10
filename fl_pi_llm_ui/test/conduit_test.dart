import 'package:fl_lib/fl_lib.dart';
import 'package:fl_pi_llm_ui/src/core/conduit.dart';
import 'package:fl_pi_llm_ui/src/store/stores.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class _Account implements ConduitAccount {
  _Account([this.tag = 'a']);

  final String tag;
  final users = ValueNotifier<String?>(null);
  final asked = <String>[];
  final dropped = <String>[];
  final before = <Future<void> Function()>[];
  final after = <void Function()>[];
  Object? failKey;
  bool failDrop = false;
  var _n = 0;

  @override
  ValueListenable<String?> get user => users;

  @override
  Uri get url => Uri.parse('https://cpa.example');

  @override
  Future<String> key({required String device, String? deviceName}) async {
    asked.add(device);
    if (failKey case final e?) throw e;
    return 'sk-$tag${++_n}';
  }

  @override
  Future<void> drop(String device) async {
    if (failDrop) throw StateError('offline');
    dropped.add(device);
  }

  @override
  void Function() beforeSignOut(Future<void> Function() f) {
    before.add(f);
    return () => before.remove(f);
  }

  @override
  void Function() onSignedOut(void Function() f) {
    after.add(f);
    return () => after.remove(f);
  }

  /// As [LkcClient.signOut]: the hooks, then the account gone.
  Future<void> signOut() async {
    for (final f in [...before]) {
      await f();
    }
    users.value = null;
    signedOut();
  }

  void signedOut() {
    for (final f in [...after]) {
      f();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Account account;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PrefStore.shared.init();
    await PrefStore.shared.clear();
    SqliteDb.openInMemory();
    account = _Account();
  });

  tearDown(() async {
    ConduitProvider.detach();
    await SqliteDb.close();
  });

  String? key() => (LlmStores.credential.get<Object>(ConduitProvider.id) as Map?)?['key'] as String?;

  Future<void> signedIn(_Account a, [String user = 'u1']) async {
    a.users.value = user;
    ConduitProvider.attachAccount(a);
    await ConduitProvider.settled;
  }

  test('signing in gets this device a key, kept on it alone', () async {
    ConduitProvider.attachAccount(account);
    await ConduitProvider.settled;
    expect(account.asked, isEmpty);
    expect(ConduitProvider.provider, isNull);

    account.users.value = 'u1';
    await ConduitProvider.settled;
    expect(key(), 'sk-a1');
    expect(LlmStores.credential.isDeviceLocalKey(ConduitProvider.id), isTrue);
    final p = ConduitProvider.provider!;
    expect(p.id, ConduitProvider.id);
    expect(p.baseUrl, 'https://cpa.example/v1');

    // The account read again asks for nothing.
    account.users.value = null;
    account.users.value = 'u1';
    await ConduitProvider.settled;
    expect(account.asked, hasLength(1));
  });

  test('off ends the key; on again replaces it for the same device', () async {
    await signedIn(account);
    final device = account.asked.single;

    LlmStores.llm.conduit.set(false);
    await ConduitProvider.settled;
    expect(account.dropped, [device]);
    expect(key(), isNull);
    expect(ConduitProvider.provider, isNull);

    LlmStores.llm.conduit.set(true);
    await ConduitProvider.settled;
    expect(account.asked, [device, device]);
    expect(key(), 'sk-a2');
  });

  test('off before the account is read still ends it at Conduit', () async {
    await signedIn(account);
    ConduitProvider.detach();
    final next = _Account();
    ConduitProvider.attachAccount(next);
    LlmStores.llm.conduit.set(false);
    await ConduitProvider.settled;
    expect(next.dropped, hasLength(1));
    expect(key(), isNull);
  });

  test('signing out ends the key while the session holds, and asks for none meanwhile', () async {
    await signedIn(account);
    final hook = account.before.single;
    final ending = hook();
    // A change arriving as it signs out, the account not gone yet.
    ConduitProvider.retry();
    await ending;
    await ConduitProvider.settled;
    expect(account.dropped, hasLength(1));
    expect(key(), isNull);
    expect(account.asked, hasLength(1));

    account.users.value = null;
    account.signedOut();
    await ConduitProvider.settled;
    // Signed in again, it asks again.
    account.users.value = 'u1';
    await ConduitProvider.settled;
    expect(account.asked, hasLength(2));
  });

  test('a session that ended takes the key here', () async {
    await signedIn(account);
    account.users.value = null;
    account.signedOut();
    await ConduitProvider.settled;
    expect(account.dropped, isEmpty);
    expect(key(), isNull);
  });

  test("another account's key is let go, and one asked for", () async {
    await signedIn(account);
    ConduitProvider.detach();

    final next = _Account('b');
    ConduitProvider.attachAccount(next);
    await ConduitProvider.settled;
    // Not read yet: the key stays.
    expect(key(), 'sk-a1');

    next.users.value = 'u2';
    await ConduitProvider.settled;
    expect(next.dropped, isEmpty);
    expect(key(), 'sk-b1');
  });

  test('a key that does not come is said, and asked for again', () async {
    account.failKey = const LkcException(status: 404, message: 'app keys are not available');
    await signedIn(account);
    expect(ConduitProvider.error.value, 'app keys are not available');
    expect(key(), isNull);

    account.failKey = null;
    ConduitProvider.retry();
    await ConduitProvider.settled;
    expect(key(), 'sk-a1');
    expect(ConduitProvider.error.value, isNull);
  });

  test('a drop Conduit does not take still ends the key here', () async {
    await signedIn(account);
    account.failDrop = true;
    LlmStores.llm.conduit.set(false);
    await ConduitProvider.settled;
    expect(key(), isNull);
  });

  test('attached again, the hooks are not doubled', () async {
    await signedIn(account);
    ConduitProvider.attachAccount(account);
    await ConduitProvider.settled;
    expect(account.before, hasLength(1));
    expect(account.after, hasLength(1));
  });
}
