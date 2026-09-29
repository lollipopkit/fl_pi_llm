import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// What the app decides for the LLM layer and its views. Set once, before
/// anything here runs; the defaults suit an app that sets nothing.
abstract final class LlmUi {
  /// The app, as MCP servers and fetched sites are told.
  static String appName = 'fl_pi_llm';
  static String appVersion = '0';

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
}
