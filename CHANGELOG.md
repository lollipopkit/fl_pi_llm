## 0.1.0

- First release: pi-durable and pi-ai on QuickJS, for Flutter apps and Rust programs.
- Sessions are kept in a SQLite file each, under the directory `FlPiLlm.start` is given, and are queried rather than loaded: a session may grow past the engine's heap. A view reads a branch a page at a time (`LlmSession.page`), with each message's versions.
- `package:fl_pi_llm/legacy.dart` moves sessions an app kept with fl_pi_llm before 0.1.0 into that directory.
- `flutter_rust_bridge` is pinned to the version the bindings were generated with: a different one fails `RustLib.init`.
