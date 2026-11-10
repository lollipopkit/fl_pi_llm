import 'package:fl_lib/fl_lib.dart';

/// Provider credentials, by provider: an API key under the provider's id,
/// any other kind (a sign-in pi-ai refreshes) under `<id>.oauth`.
///
/// In the app's encrypted database, apart from [LlmStores.all]: an app syncs
/// it only with its secrets. The keys travel; a sign-in is this device's
/// ([isDeviceLocalKey]): two devices refreshing one sign each other out. So
/// is Conduit's key, which each device gets for itself (`ConduitProvider`).
final class LlmCredentialStore extends SqliteStore {
  LlmCredentialStore._() : super('llmCredential');

  static final instance = LlmCredentialStore._();

  static const oauthSuffix = '.oauth';

  @override
  bool isDeviceLocalKey(String key) => key.endsWith(oauthSuffix) || key == conduit;

  static const conduit = 'conduit';
}
