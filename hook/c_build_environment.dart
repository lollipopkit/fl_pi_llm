import 'package:code_assets/code_assets.dart';

/// `CFLAGS` that keep the build directory out of the C the crate compiles.
///
/// `rquickjs-sys` writes QuickJS's sources into its `OUT_DIR`, under
/// [outputDirectory]'s `target/`, and `cc` compiles them by absolute path.
/// QuickJS's `assert`s then embed that path through `__FILE__`, so two builds
/// of the same commit in different directories ship different libraries.
/// `--remap-path-prefix` in `rust_build_environment.dart` is rustc's and never
/// reaches the C compiler.
///
/// Empty for Windows: MSVC has no `-ffile-prefix-map`.
Map<String, String> reproducibleCEnvironment({
  required Map<String, String> environment,
  required String outputDirectory,
  required OS targetOS,
}) {
  if (targetOS == OS.windows) return const {};
  final flags = [
    ?_nonEmpty(environment['CFLAGS']),
    '-ffile-prefix-map=${_trimTrailingSlashes(outputDirectory)}=/build',
  ];
  return {'CFLAGS': flags.join(' ')};
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String _trimTrailingSlashes(String path) {
  var end = path.length;
  while (end > 1 && path.codeUnitAt(end - 1) == 0x2f) {
    end--;
  }
  return path.substring(0, end);
}
