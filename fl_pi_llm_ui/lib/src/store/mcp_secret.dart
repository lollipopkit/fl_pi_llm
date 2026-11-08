import 'package:fl_lib/fl_lib.dart';

/// The headers and OAuth tokens of the MCP servers, by server: a server's
/// headers under its id, its sign-in under `<id>.oauth`.
///
/// In the app's encrypted database, apart from [LlmStores.all]: an app syncs
/// it only with its secrets. The headers travel; a sign-in is this device's
/// ([isDeviceLocalKey]) — its refresh token is spent on use, and two devices
/// sharing one would sign each other out.
final class McpSecretStore extends SqliteStore {
  McpSecretStore._() : super('mcpSecret');

  static final instance = McpSecretStore._();

  static const oauthSuffix = '.oauth';

  @override
  bool isDeviceLocalKey(String key) => key.endsWith(oauthSuffix);
}
