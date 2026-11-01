import 'dart:io';

import 'package:code_forge/code_forge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'a stdio server that exits early reports its exit code and stderr tail',
    () async {
      final config = await LspStdioConfig.start(
        executable: '/bin/sh',
        args: ['-c', 'echo "expected initialized notification" >&2; exit 7'],
        workspacePath: Directory.current.path,
        languageId: 'test',
      );
      addTearDown(config.dispose);

      // Let the process die and its stderr land before exercising the failure
      // path, so the assertions below are deterministic.
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (config.isUsable && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(config.isUsable, isFalse);

      await expectLater(
        config.initialize(),
        throwsA(
          isA<StateError>()
              .having((error) => error.message, 'message', contains('code 7'))
              .having(
                (error) => error.message,
                'message',
                contains('expected initialized notification'),
              ),
        ),
      );
    },
  );
}
