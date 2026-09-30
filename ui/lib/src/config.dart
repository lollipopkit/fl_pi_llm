import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:fl_pi_llm_ui/src/store/chat_meta.dart';
import 'package:fl_pi_llm_ui/src/tools/tool.dart';

/// What the app decides for the LLM layer and its views. Set once, before
/// anything here runs; the defaults suit an app that sets nothing.
abstract final class LlmUi {
  /// The app, as MCP servers and fetched sites are told.
  static String appName = 'fl_pi_llm';
  static String appVersion = '0';

  /// The app's web page. Shown with [appName] where the app has to introduce
  /// itself, such as an MCP server's sign-in.
  static Uri? appUri;

  /// Whether a new chat is named by the model.
  static bool Function() genTitle = () => true;

  /// How long a chat stays in the trash.
  static int Function() trashDays = () => 7;

  /// Whether code blocks wrap their lines; they follow it as it changes.
  static ValueListenable<bool> softWrap = ValueNotifier(true);

  /// Whether the conversation follows a reply as it is written.
  static bool Function() scrollBottom = () => true;

  /// Whether a chat opens scrolled to its end.
  static bool Function() scrollAfterSwitch = () => true;

  /// Shows provider [id] ('' for a new custom one) where the app lays it
  /// out — beside the list, say. False to have it pushed as a page.
  static bool Function(BuildContext context, String id) showProvider = (_, _) => false;

  /// Opens the app's provider settings: asked when a model is wanted and no
  /// provider has a key. Null: nothing to open.
  static void Function(BuildContext context)? openProviders;

  /// The app's own tools, beside the built-in ones: listed in the tool
  /// settings with a switch per group, and offered to chats that [offers]
  /// lets have them.
  static List<ToolFunc> Function() appTools = () => const [];

  /// Whether a chat is offered the tools of [group] — a [ToolFunc.group], or
  /// [Tools.mcpGroup] for every MCP server's. A chat in a [ChatMeta.scope]
  /// that has a narrower job than the app's own list, say.
  static bool Function(ChatMeta? meta, String group) offers = (_, _) => true;

  /// What the app adds to a chat's system prompt, after the user's own.
  /// Applied when a chat opens and on [Chats.reconfigure].
  static String? Function(ChatMeta? meta) appPrompt = (_) => null;
}
