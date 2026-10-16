import 'dart:convert';

import 'rust/api/mcp.dart' as rs;

/// An MCP tool's own failure (`isError`): its message is what the model is
/// told.
final class McpToolError implements Exception {
  const McpToolError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// An MCP server's tool as the model sees it: [title] as a person reads it,
/// [readOnly] and [destructive] the server's hints.
typedef LlmMcpTool = ({
  String name,
  String description,
  String label,
  Map<String, Object?> parameters,
  String title,
  bool readOnly,
  bool destructive,
});

/// What an MCP server's tools become for the model: their names, what they
/// say, the servers' instructions and a call's answer as pi content. These are
/// fl_pi_llm's own (Rust, shared with every host); connecting and signing in
/// are the app's client. Needs the library loaded ([FlPiLlm.loadLibrary]).
abstract final class LlmMcp {
  /// The id a server's tools are prefixed with, from its [url]: the same
  /// across launches and when another server is removed.
  static String serverId(String url) => rs.mcpServerId(url: url);

  /// What a server calls itself ([info], its `serverInfo` of `initialize`:
  /// the title, else the name), else [url]'s host.
  static String serverName(Map<String, Object?>? info, String url) =>
      rs.mcpServerName(info: jsonEncode({'serverInfo': ?info}), url: url);

  /// [tool], as `tools/list` has it, of server [serverId] called [server];
  /// null without a name.
  static LlmMcpTool? tool(String serverId, String server, Map<String, Object?> tool) {
    final out = rs.mcpTool(serverId: serverId, server: server, tool: jsonEncode(tool));
    if (out == null) return null;
    final t = jsonDecode(out) as Map<String, Object?>;
    return (
      name: t['name'] as String,
      description: t['description'] as String,
      label: t['label'] as String,
      parameters: (t['parameters'] as Map).cast<String, Object?>(),
      title: t['title'] as String,
      readOnly: t['readOnly'] as bool,
      destructive: t['destructive'] as bool,
    );
  }

  /// What [servers] (name, instructions) say about using them, for the system
  /// prompt; null when none says anything.
  static String? instructions(Iterable<(String, String)> servers) =>
      rs.mcpInstructions(servers: jsonEncode([for (final (n, i) in servers) [n, i]]));

  /// [tool]'s `tools/call` answer [result] as pi content, and its structured
  /// content. Throws [McpToolError] for the tool's own error.
  static (List<Map<String, Object?>>, Object?) callResult(String tool, Map<String, Object?> result) {
    final out = jsonDecode(rs.mcpCallResult(tool: tool, result: jsonEncode(result))) as Map<String, Object?>;
    if (out['ok'] != true) throw McpToolError(out['error'] as String);
    return ((out['content'] as List).cast<Map<String, Object?>>(), out['details']);
  }
}
