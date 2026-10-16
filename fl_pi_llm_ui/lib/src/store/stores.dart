import 'package:fl_lib/fl_lib.dart';
import 'package:fl_pi_llm_ui/src/store/chat.dart';
import 'package:fl_pi_llm_ui/src/store/llm.dart';
import 'package:fl_pi_llm_ui/src/store/mcp_secret.dart';
import 'package:fl_pi_llm_ui/src/store/memory.dart';
import 'package:fl_pi_llm_ui/src/store/tool.dart';

/// The stores of the LLM layer, in fl_lib's SQLite database: the app opens
/// it ([SqliteStore.openDatabase]) and includes these in its backups.
abstract final class LlmStores {
  static final chat = ChatStore.instance;
  static final llm = LlmStore.instance;
  static final tool = ToolStore.instance;
  static final memory = MemoryStore.instance;

  static final List<SqliteStore> all = [chat, llm, tool, memory];

  /// MCP headers and tokens. Not in [all], which apps back up: see
  /// [McpSecretStore].
  static final mcpSecret = McpSecretStore.instance;
}
