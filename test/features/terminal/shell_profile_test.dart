import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/features/terminal/shell_profile.dart';

void main() {
  group('splitShellArguments', () {
    test('splits on whitespace', () {
      expect(splitShellArguments('-l --login'), ['-l', '--login']);
    });

    test('collapses repeated whitespace and trims the ends', () {
      expect(splitShellArguments('  -a   -b  '), ['-a', '-b']);
    });

    test('keeps a quoted argument with spaces together', () {
      expect(splitShellArguments('-c "echo hello world"'), [
        '-c',
        'echo hello world',
      ]);
    });

    test('single quotes are fully literal', () {
      expect(splitShellArguments(r"""-c 'echo \$HOME'"""), [
        '-c',
        r'echo \$HOME',
      ]);
    });

    test('double quotes understand backslash escapes', () {
      expect(splitShellArguments(r'-c "say \"hi\""'), ['-c', 'say "hi"']);
    });

    test('a backslash outside quotes escapes the next character', () {
      expect(splitShellArguments(r'/tmp/my\ dir/zsh'), ['/tmp/my dir/zsh']);
    });

    test(
      'an unterminated quote keeps what was read instead of dropping it',
      () {
        expect(splitShellArguments('-c "echo hi'), ['-c', 'echo hi']);
      },
    );

    test('an empty string produces no arguments', () {
      expect(splitShellArguments(''), isEmpty);
      expect(splitShellArguments('   '), isEmpty);
    });

    test('an empty quoted argument is preserved', () {
      expect(splitShellArguments('-x ""'), ['-x', '']);
    });
  });

  group('resolveShellCommand', () {
    test('falls back to the platform default when the override is blank', () {
      final command = resolveShellCommand(
        executableOverride: '   ',
        arguments: '-l',
        fallbackExecutable: '/bin/zsh',
        fallbackArguments: const ['-i'],
      );

      expect(command.executable, '/bin/zsh');
      // The override's arguments are dropped too: attaching them to a shell the
      // user did not pick would change the default launch line.
      expect(command.arguments, ['-i']);
    });

    test('uses the override and its split arguments', () {
      final command = resolveShellCommand(
        executableOverride: '/usr/local/bin/fish',
        arguments: '-l -C "echo hi"',
        fallbackExecutable: '/bin/zsh',
        fallbackArguments: const [],
      );

      expect(command.executable, '/usr/local/bin/fish');
      expect(command.arguments, ['-l', '-C', 'echo hi']);
    });

    test('an override without arguments launches with none', () {
      final command = resolveShellCommand(
        executableOverride: '/bin/bash',
        arguments: '',
        fallbackExecutable: '/bin/zsh',
        fallbackArguments: const ['-i'],
      );

      expect(command.arguments, isEmpty);
    });
  });

  group('resolveStartDirectory', () {
    test('uses the configured directory when it exists', () {
      expect(
        resolveStartDirectory(
          configured: '/work/sub',
          workspaceDirectory: '/work',
          currentDirectory: '/tmp',
          exists: (candidate) => candidate == '/work/sub',
        ),
        '/work/sub',
      );
    });

    test('skips a configured directory that disappeared', () {
      expect(
        resolveStartDirectory(
          configured: '/moved/away',
          workspaceDirectory: '/work',
          currentDirectory: '/tmp',
          exists: (candidate) => candidate == '/work',
        ),
        '/work',
      );
    });

    test('falls back to the process directory without a workspace', () {
      expect(
        resolveStartDirectory(
          configured: '',
          workspaceDirectory: null,
          currentDirectory: '/tmp',
          exists: (_) => false,
        ),
        '/tmp',
      );
    });

    test('never returns an empty string', () {
      expect(
        resolveStartDirectory(
          configured: '',
          workspaceDirectory: '',
          currentDirectory: '',
          exists: (_) => false,
        ),
        '.',
      );
    });
  });

  group('platform reality check', () {
    test('the injected existence check matches the real filesystem', () {
      // Guards the contract the tests above rely on: a path that resolves here
      // is one the provider's `Directory(...).existsSync()` would accept too.
      final directory = Directory.systemTemp;

      expect(
        resolveStartDirectory(
          configured: directory.path,
          currentDirectory: Directory.current.path,
          exists: (candidate) => Directory(candidate).existsSync(),
        ),
        directory.path,
      );
    });
  });
}
