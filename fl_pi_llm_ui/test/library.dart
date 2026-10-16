import 'dart:io';

import 'package:fl_pi_llm/fl_pi_llm.dart';

/// Loads the library `cargo build` leaves in `rust/target/debug`, which the
/// memory, skills and MCP code call.
Future<void> loadLlmLibrary() {
  final name = Platform.isMacOS
      ? 'libfl_pi_llm.dylib'
      : Platform.isWindows
      ? 'fl_pi_llm.dll'
      : 'libfl_pi_llm.so';
  return FlPiLlm.loadLibrary(externalLibrary: ExternalLibrary.open('../fl_pi_llm/rust/target/debug/$name'));
}
