/// Chats, tools and the provider settings on fl_pi_llm, for Flutter apps on
/// fl_lib.
///
/// The app opens fl_lib's SQLite database, sets [LlmUi], adds
/// [LlmLocalizations.delegates] and calls [LlmL10nX.setLlmL10n] with its own
/// l10n, then [Llm.init].
library;

export 'package:fl_pi_llm/fl_pi_llm.dart';

export 'generated/l10n/llm_l10n.dart';
export 'src/config.dart';
export 'src/core/chats.dart';
export 'src/core/credentials.dart';
export 'src/core/llm.dart';
export 'src/core/session_store.dart';
export 'src/res/l10n.dart';
export 'src/skills/discover.dart';
export 'src/skills/skills.dart';
export 'src/skills/source.dart';
export 'src/store/chat.dart';
export 'src/store/chat_meta.dart';
export 'src/store/llm.dart';
export 'src/store/mcp_secret.dart';
export 'src/store/memory.dart';
export 'src/store/stores.dart';
export 'src/store/tool.dart';
export 'src/tools/tool.dart';
export 'src/view/code.dart';
export 'src/view/composer.dart';
export 'src/view/conversation.dart';
export 'src/view/menu.dart';
export 'src/view/message.dart';
export 'src/view/model_picker.dart';
export 'src/view/pull_actions.dart';
export 'src/view/section_list.dart';
export 'src/view/settings/custom_provider.dart';
export 'src/view/settings/mcp_server.dart';
export 'src/view/settings/memory.dart';
export 'src/view/settings/provider.dart';
export 'src/view/settings/providers.dart';
export 'src/view/settings/skills.dart';
export 'src/view/settings/tools.dart';
