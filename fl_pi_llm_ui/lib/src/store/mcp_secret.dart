import 'package:fl_lib/fl_lib.dart';

/// The headers and OAuth tokens of the MCP servers, by server.
///
/// In the app's encrypted database, apart from [LlmStores.all]: an app that
/// backs up or syncs the tool settings leaves these on the device.
final class McpSecretStore extends SqliteStore {
  McpSecretStore._() : super('mcpSecret', updateLastUpdateTsOnSet: false, updateLastUpdateTsOnRemove: false);

  static final instance = McpSecretStore._();
}
