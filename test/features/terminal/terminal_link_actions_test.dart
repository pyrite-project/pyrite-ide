import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/features/terminal/terminal_link_actions.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';

void main() {
  group('isSafeTerminalUrl', () {
    test('accepts http and https URLs with a host', () {
      expect(isSafeTerminalUrl('http://example.com'), isTrue);
      expect(isSafeTerminalUrl('https://example.com/a?b=1#c'), isTrue);
    });

    test('rejects every other scheme', () {
      // Terminal output is attacker-influenced, so a printed `file://` or a
      // custom protocol must never reach the OS opener.
      expect(isSafeTerminalUrl('file:///etc/passwd'), isFalse);
      expect(isSafeTerminalUrl('javascript:alert(1)'), isFalse);
      expect(isSafeTerminalUrl('ssh://host/x'), isFalse);
      expect(isSafeTerminalUrl('example.com'), isFalse);
    });

    test('rejects a URL with no host', () {
      expect(isSafeTerminalUrl('https://'), isFalse);
      expect(isSafeTerminalUrl('http:///path'), isFalse);
    });

    test('rejects embedded control characters', () {
      expect(isSafeTerminalUrl('https://example.com/\nrm -rf'), isFalse);
    });

    test('rejects garbage', () {
      expect(isSafeTerminalUrl(''), isFalse);
      expect(isSafeTerminalUrl('not a url'), isFalse);
    });
  });

  group('urlOpenCommand', () {
    test('uses open on macOS', () {
      final command = urlOpenCommand(
        'https://example.com',
        isMacOS: true,
        isWindows: false,
        isLinux: false,
      )!;

      expect(command.executable, 'open');
      expect(command.arguments, ['https://example.com']);
    });

    test('uses cmd /c start on Windows without a title argument', () {
      final command = urlOpenCommand(
        'https://example.com',
        isMacOS: false,
        isWindows: true,
        isLinux: false,
      )!;

      expect(command.executable, 'cmd');
      // The empty argument is the window title slot; without it `start` treats
      // the URL as a title and opens nothing.
      expect(command.arguments, ['/c', 'start', '', 'https://example.com']);
    });

    test('uses xdg-open on Linux', () {
      final command = urlOpenCommand(
        'https://example.com',
        isMacOS: false,
        isWindows: false,
        isLinux: true,
      )!;

      expect(command.executable, 'xdg-open');
      expect(command.arguments, ['https://example.com']);
    });

    test('returns null for an unsafe URL even on a supported platform', () {
      expect(
        urlOpenCommand(
          'file:///etc/passwd',
          isMacOS: true,
          isWindows: false,
          isLinux: false,
        ),
        isNull,
      );
    });

    test('returns null on an unsupported platform', () {
      expect(
        urlOpenCommand(
          'https://example.com',
          isMacOS: false,
          isWindows: false,
          isLinux: false,
        ),
        isNull,
      );
    });
  });

  group('terminalLinkOpenMessage', () {
    test('stays quiet when the link opened', () {
      expect(terminalLinkOpenMessage(TerminalUrlOpenResult.opened), isNull);
    });

    test('explains every fallback', () {
      expect(
        terminalLinkOpenMessage(TerminalUrlOpenResult.copied),
        I18nKey.terminalUrlCopied.fallback,
      );
      expect(
        terminalLinkOpenMessage(TerminalUrlOpenResult.rejected),
        I18nKey.terminalUrlRejected.fallback,
      );
      expect(
        terminalLinkOpenMessage(TerminalUrlOpenResult.failed),
        I18nKey.terminalUrlOpenFailed.fallback,
      );
    });
  });
}
