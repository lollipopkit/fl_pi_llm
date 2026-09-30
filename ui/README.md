# fl_pi_llm_ui

Chats, tools and the provider settings on [fl_pi_llm](..), for Flutter apps built on [fl_lib](https://github.com/lollipopkit/fl_lib). Shared by GPT Box and Server Box.

- **Core**: `Llm` (runtime, provider catalog, keys in the keychain), `Chats`/`OpenChat` (open, send, edit, regenerate, retry, versions, search, trash, titles), `SqlitePiSessionStore` (pi's sessions in fl_lib's SQLite), `PiSessionLog.union` (joining diverged logs, for sync).
- **Stores** (`LlmStores`): `chats`, `llm`, `tool`, `memory` in fl_lib's SQLite; the app backs them up.
- **Tools**: web fetch, chat search/read, file memory (`memory_*`), MCP servers.
- **Views**: `LlmConversation` (a chat's thread), `Composer`, `ThreadBlockView`/`ChatMarkdown`, `pickModel`, `ProvidersPage`/`ProviderPage`/`CustomProviderPage`, `ToolsPage`, `MemoryPage`, and the `SectionList`/`SettingsGroup`/`SettingsRow` they are laid out with.

## Using it

The app has fl_lib as a submodule, so it overrides this package's git one:

```yaml
dependencies:
  fl_pi_llm_ui:
    path: packages/fl_pi_llm/ui
dependency_overrides:
  fl_lib:
    path: packages/fl_lib
```

Then, at startup:

1. Open fl_lib's database (`SqliteStore.openDatabase`) and `init` `LlmStores.all`.
2. Set `LlmUi`: the app's name and version, and its settings and navigation (title generation, trash days, soft wrap, scrolling, where a provider page is shown, how to open the provider settings).
3. `await Llm.init()`.
4. Add `LlmLocalizations.delegate` and call `context.setLlmL10n()` where the app sets its own l10n.
5. Views are on [material_ui](https://pub.dev/packages/material_ui), like fl_lib. flutter_markdown_plus and flutter_highlight still look the theme up by `package:flutter/material.dart`'s types, so the app wraps `MaterialApp.builder`'s child in material_ui's `MaterialUiCompatibilityBridge` until they move.

### An app's own tools and places

An app with more to offer than a chat list plugs into the same `Chats`:

- **Its tools**: `LlmUi.appTools` returns `ToolFunc`s, listed in the tool settings beside the built-in ones. A `ToolFunc` can decide a call before the user is asked (`preApprove`: allow, deny, or `null` to ask), keep "always allow" off for calls no single answer covers (`allowAlways`), and draw a call in the approval card (`preview`) and in the conversation (`icon`).
- **Its places**: a chat made with `Chats.create(scope: ...)` — or a `Composer(scope: ...)` — belongs to that scope, and `LlmStores.chat.all(scope: ...)` lists it apart from the app's own list. `LlmUi.offers(meta, group)` decides which tool groups (`Tools.mcpGroup` for MCP) a chat gets, and `LlmUi.appPrompt(meta)` adds to its system prompt; call `Chats.reconfigureSoon()` when either would answer differently.

A custom provider's plain `http` address off the device is refused unless the provider is saved with `allowInsecure` — the page offers the switch when the address needs it.

## Development

In the app's checkout, `pubspec_overrides.yaml` (not committed) points fl_lib at the app's submodule:

```yaml
dependency_overrides:
  fl_lib:
    path: ../../fl_lib
```

Strings are in `lib/l10n/llm_*.arb`; `flutter gen-l10n` writes `lib/generated/l10n` (committed, as apps do not generate it).
