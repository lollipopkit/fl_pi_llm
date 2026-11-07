import 'package:fl_lib/fl_lib.dart';
import 'package:fl_pi_llm/fl_pi_llm.dart';
import 'package:fl_pi_llm_ui/src/config.dart';
import 'package:fl_pi_llm_ui/src/core/chats.dart';
import 'package:fl_pi_llm_ui/src/core/llm.dart';
import 'package:fl_pi_llm_ui/src/store/stores.dart';
import 'package:fl_pi_llm_ui/src/tools/tool.dart';

/// How this app's tool calls are approved: the stored [LlmPermissions],
/// decided by [LlmPermissionRules] — the logic a monitor's Agent mode decides
/// by too.
abstract final class LlmApprovals {
  /// What the settings hold.
  static LlmPermissions get stored => LlmPermissions.fromJson(LlmStores.tool.permissions.get());

  /// Stores [p]; throws what is wrong with it.
  static void store(LlmPermissions p) {
    if (LlmPermissionRules.check(p) case final reason?) throw Exception(reason);
    LlmStores.tool.permissions.set(p.toJson());
  }

  /// The mode chats run in, picked under the message box.
  static void pickMode(LlmPermissionMode mode) => store(stored.copyWith(defaultMode: mode));

  /// The built-in auto mode lists for this app.
  static Map<LlmAutoRuleKind, List<String>> get defaults => LlmPermissionRules.defaults(LlmUi.permissionEnvironment());

  /// Whether [call] of [tool] runs, is refused, or is asked about — and then
  /// whether an earlier "always allow" may answer instead ([remembered]),
  /// which it may not for a call that loses something for good. An MCP tool
  /// is what its server says of it.
  static Future<({LlmApproval? decided, bool remembered})> decide(LlmToolCall call, ToolFunc? tool) async {
    final p = stored;
    final mcp = tool == null ? McpTools.defOf(call.name) : null;
    final claimed =
        tool?.effect(call.args) ??
        (mcp?.readOnly ?? false
            ? LlmEffect.read
            : mcp?.destructive ?? false
            ? LlmEffect.danger
            : LlmEffect.change);
    final command = tool?.shellCommand(call.args);
    final subject = command ?? '${call.name} ${tool?.summary(call.args) ?? call.args}';
    return switch (LlmPermissionRules.decide(p, p.mode, command: command, claimed: claimed)) {
      LlmRun() => (decided: const LlmApproval.allow(), remembered: false),
      LlmDeny(:final message) => (decided: LlmApproval.deny(message), remembered: false),
      LlmAsk(:final danger) => (decided: null, remembered: !danger),
      LlmJudge() => (decided: await _judge(call.sessionId, p, subject, claimed), remembered: true),
    };
  }

  /// The auto mode judge, on the chat's model. No verdict asks.
  static Future<LlmApproval?> _judge(String chatId, LlmPermissions p, String subject, LlmEffect claimed) async {
    final model = LlmStores.chat.fetch(chatId)?.model ?? Llm.defaultModel;
    final chat = Chats.openOf(chatId);
    if (model == null || chat == null) return null;
    try {
      final input = LlmPermissionRules.judgeInput([for (final e in chat.entries.value) e.json], subject, claimed: claimed);
      final reply = await Llm.rt
          .complete(
            model: model,
            messages: [
              LlmMessage({
                'role': 'user',
                'content': [
                  {'type': 'text', 'text': input},
                ],
                'timestamp': DateTime.now().millisecondsSinceEpoch,
              }),
            ],
            systemPrompt: LlmPermissionRules.judgePrompt(p, LlmUi.permissionEnvironment()),
          )
          .timeout(const Duration(seconds: 90));
      return switch (LlmPermissionRules.judgment(reply.text)) {
        (allowed: true, message: _) => const LlmApproval.allow(),
        (allowed: false, :final message) => LlmApproval.deny(message),
        null => null,
      };
    } catch (e, s) {
      Loggers.app.warning('Auto mode judge', e, s);
      return null;
    }
  }
}
