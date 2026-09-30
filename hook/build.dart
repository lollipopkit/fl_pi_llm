import 'dart:io';

import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';

import 'bindgen_environment.dart';
import 'deployment_target.dart';
import 'rust_build_environment.dart';

/// Builds `rust/` and hands the library to the Dart/Flutter SDK as a code
/// asset. No pod, no Swift package, no Gradle plugin: the same file covers
/// every platform, and an app that depends on this package needs nothing else.
void main(List<String> args) async {
  await build(args, (input, output) async {
    await FlutterRustBridgeNativeAssetsBuilder(
      cratePath: 'rust',
      extraCargoEnvironmentVariables: {
        ...reproducibleCargoEnvironment(
          environment: Platform.environment,
          packageRoot: Directory.fromUri(input.packageRoot).path,
          isWindows: Platform.isWindows,
        ),
        // Only ever non-empty for iOS and Android, the two targets
        // `rquickjs-sys` ships no bindings for. See its own file.
        ...bindgenCrossCompileEnvironment(input),
        ...deploymentTargetEnvironment(input),
      },
    ).run(input: input, output: output);
  });
}
