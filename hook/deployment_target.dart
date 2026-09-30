import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

/// The oldest OS the app runs on, for everything the crate compiles.
///
/// **Needed for the C in it, not the Rust.** `rquickjs-sys` compiles QuickJS
/// with `cc`, which without `IPHONEOS_DEPLOYMENT_TARGET` targets the SDK's
/// own version (iOS 26.5 on Xcode 26), while rustc links for its default
/// (iOS 10). The objects then call `___chkstk_darwin`, which a link for iOS 10
/// does not have, and the build fails with `Undefined symbols` — or, where a
/// cache had the variable from an earlier build, passes. Both read the same
/// variable, so setting it lines them up on the app's minimum.
Map<String, String> deploymentTargetEnvironment(BuildInput input) {
  if (!input.config.buildCodeAssets) return const {};
  final code = input.config.code;
  return switch (code.targetOS) {
    OS.iOS => {'IPHONEOS_DEPLOYMENT_TARGET': '${code.iOS.targetVersion}'},
    OS.macOS => {'MACOSX_DEPLOYMENT_TARGET': '${code.macOS.targetVersion}'},
    _ => const {},
  };
}
