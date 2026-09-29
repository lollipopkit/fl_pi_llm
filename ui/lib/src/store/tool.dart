import 'package:fl_lib/fl_lib.dart';

/// The tool settings: the switch, the built-in tools on and off, what runs
/// without asking, and the MCP servers.
final class ToolStore extends SqliteStore {
  ToolStore._() : super('tool');

  static final instance = ToolStore._();

  /// Whether the model is offered tools at all. On until turned off.
  late final enabled = propertyDefault('enabled', true);

  /// Built-in tools turned off, by group.
  late final disabledTools = listProperty<String>('disabledTools');

  /// Built-in tools that are off by default and turned on, by group.
  late final enabledTools = listProperty<String>('enabledTools');

  /// Tools the user allowed to run without asking every time.
  late final permittedTools = listProperty<String>('permittedTools');

  /// MCP server URLs.
  late final mcpServers = listProperty<String>('mcpServers');
}
