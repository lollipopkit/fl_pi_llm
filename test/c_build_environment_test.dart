import 'package:code_assets/code_assets.dart';
import 'package:test/test.dart';

import '../hook/c_build_environment.dart';

void main() {
  group('reproducibleCEnvironment', () {
    test('remaps the hook output directory', () {
      final result = reproducibleCEnvironment(
        environment: const {},
        outputDirectory: '/work/app/.dart_tool/hooks_runner/shared/x/build/1/',
        targetOS: OS.android,
      );

      expect(result, {
        'CFLAGS':
            '-ffile-prefix-map=/work/app/.dart_tool/hooks_runner/shared/x/'
            'build/1=/build',
      });
    });

    test('keeps inherited CFLAGS', () {
      final result = reproducibleCEnvironment(
        environment: const {'CFLAGS': '  -O2 -g  '},
        outputDirectory: '/out',
        targetOS: OS.linux,
      );

      expect(result['CFLAGS'], '-O2 -g -ffile-prefix-map=/out=/build');
    });

    test('is empty for Windows', () {
      final result = reproducibleCEnvironment(
        environment: const {'CFLAGS': '/O2'},
        outputDirectory: r'C:\out',
        targetOS: OS.windows,
      );

      expect(result, isEmpty);
    });
  });
}
