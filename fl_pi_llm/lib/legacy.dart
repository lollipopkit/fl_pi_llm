/// For an app that kept sessions with fl_pi_llm before 0.1.0: moving them
/// into the runtime's directory. Nothing else needs it.
///
/// TODO: remove once no install keeps such a session.
library;

export 'src/runtime.dart' show LlmLegacyMigration, LlmLegacySessions, StoredFile;
