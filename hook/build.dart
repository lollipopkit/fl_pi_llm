import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';

import 'bindgen_environment.dart';
import 'c_build_environment.dart';
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
        if (input.config.buildCodeAssets)
          ...reproducibleCEnvironment(
            environment: Platform.environment,
            outputDirectory: Directory.fromUri(input.outputDirectory).path,
            targetOS: input.config.code.targetOS,
          ),
        // Only ever non-empty for iOS and Android, the two targets
        // `rquickjs-sys` ships no bindings for. See its own file.
        ...bindgenCrossCompileEnvironment(input),
        ...deploymentTargetEnvironment(input),
      },
    ).run(input: input, output: output);
  });
}
