# fl_pi_llm

The LLM layer shared by [GPT Box](https://github.com/lollipopkit/flutter_gpt_box)
and [Server Box](https://github.com/lollipopkit/flutter_server_box).

It runs [pi](https://github.com/earendil-works/pi)'s `pi-agent-core` and
`pi-ai` in QuickJS, and keeps everything that touches the outside world in
Dart: the network, the tools, and the user's approval of a tool call. What that
buys an app:

- One API over OpenAI Chat Completions and Responses, Anthropic Messages and
  Gemini — and anything that copies one of them.
- An agent loop with tool calling, streamed token by token.
- Tool calls that wait for the user: the run is suspended until the app answers.
- Sessions as pi keeps them: a tree of entries, so an edited message is a new
  branch rather than a rewrite, stored wherever the app says.
- Compaction: once a conversation no longer fits the context window, the older
  part is summarised for the model; the originals stay in the session.
- An upstream that is actively developed, rather than a protocol layer written
  and maintained twice.

Background: [flutter_server_box#1468](https://github.com/lollipopkit/flutter_server_box/issues/1468).

## Use

```dart
import 'package:fl_pi_llm/fl_pi_llm.dart';

// Where sessions live. Implement PiSessionStore over the app's own
// (encrypted) storage, or use DirectorySessionStore / MemorySessionStore.
final llm = await FlPiLlm.start(store: myStore);

final session = await llm.openSession(
  id: 'chat-1', // created when it does not exist, reopened when it does
  model: const LlmModel(
    api: LlmApi.openaiCompletions,
    id: 'gpt-4o-mini',
    baseUrl: 'https://api.openai.com/v1',
    apiKey: '...',
  ),
  systemPrompt: 'You are helpful.',
  tools: [
    LlmTool(
      name: 'get_time',
      description: 'The current time',
      execute: (call, cancel) async => LlmToolResult.text('${DateTime.now()}'),
    ),
  ],
  // Asked before every tool call; the run waits for the answer.
  approve: (call) async => const LlmApproval.allow(),
);

session.events.listen((e) {
  if (e.textDelta case final d?) stdout.write(d);
});

await session.prompt('What time is it?');
final branch = await session.entries(); // root first
```

A session is pi's: an append-only tree of entries. `navigate` moves the tip
back — to edit a message or regenerate an answer — and the next prompt grows a
new branch while the old one stays in `tree()`. Compaction adds a `compaction`
entry the model sees instead of what came before it; the originals stay in the
tree, reachable by `entry(id)`. A run a crash interrupted is reported by
`interrupted` and picked up by `resume()`.

`FlPiLlm.complete` does a single completion outside any session, for things
like a chat title.

## Layout

| Path | What |
|---|---|
| `js/` | The Web platform layer QuickJS lacks (`src/web.js`), pi's filesystem over the host's store (`src/fs.js`) and the host API (`src/main.js`). Built into `rust/js/fl_pi_llm.js`, which `rust/build.rs` compiles to QuickJS bytecode. |
| `rust/` | The runtime: a QuickJS context on its own thread, its timers and job queue, and the bridge to Dart. |
| `lib/` | The Dart API. HTTP is done here, with `HttpClient`; sessions are stored through `PiSessionStore`. |
| `hook/` | The build hook that compiles `rust/`. No CocoaPods, no Gradle plugin, works with SwiftPM. |

Apps need a Rust toolchain (`rust/rust-toolchain.toml` names the version) and
nothing else. The JS bundle is checked in, so building an app needs no JS
toolchain; CI rebuilds it and fails if it differs.

## Develop

```bash
# After changing js/src, or bumping pi
cd js && npm ci && npm run build

# After changing rust/src/api
flutter_rust_bridge_codegen generate

cd rust && cargo test          # the runtime, against a mock server
dart test                      # the whole package, through the build hook
```

## License

[AGPL-3.0](LICENSE). Contributions need the [CLA](CLA.md) — see
[CONTRIBUTING.md](CONTRIBUTING.md). The bundled JavaScript packages keep their
own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
