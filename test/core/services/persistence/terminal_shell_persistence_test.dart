import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/persistence/settings_persistence.dart';

/// Builds a settings record with only the required fields filled in.
///
/// The record has a long list of required editor/lsp values that have nothing
/// to do with the shell fields under test; naming them here keeps each case
/// focused on the round-trip it actually checks.
SettingsPersistedData _settings({
  String shellExecutable = '',
  String shellArguments = '',
  String workingDirectory = '',
}) => SettingsPersistedData(
  editorTextFont: 'JetBrains Mono',
  editorFontSize: 15,
  editorWordWrap: false,
  editorLineNumber: true,
  useLsp: true,
  lspWebSocketPath: '127.0.0.1:2026',
  disableWarning: false,
  disableError: false,
  terminalShellExecutable: shellExecutable,
  terminalShellArguments: shellArguments,
  terminalWorkingDirectory: workingDirectory,
);

void main() {
  group('desktop shell settings persistence', () {
    test('defaults to empty, which means "use the platform shell"', () {
      final settings = _settings();

      expect(settings.terminalShellExecutable, '');
      expect(settings.terminalShellArguments, '');
      expect(settings.terminalWorkingDirectory, '');
    });

    test('round-trips a configured shell through JSON', () {
      final settings = _settings(
        shellExecutable: '/usr/bin/zsh',
        shellArguments: '-l -i',
        workingDirectory: '/work/project',
      );

      final restored = SettingsPersistedData.fromJson(settings.toJson());

      expect(restored.terminalShellExecutable, '/usr/bin/zsh');
      expect(restored.terminalShellArguments, '-l -i');
      expect(restored.terminalWorkingDirectory, '/work/project');
    });

    test('reads settings written before these fields existed', () {
      final json = _settings().toJson()
        ..remove('terminalShellExecutable')
        ..remove('terminalShellArguments')
        ..remove('terminalWorkingDirectory');

      final restored = SettingsPersistedData.fromJson(json);

      // An existing profile must not start failing to launch because the
      // fields it never wrote are suddenly required.
      expect(restored.terminalShellExecutable, '');
      expect(restored.terminalShellArguments, '');
      expect(restored.terminalWorkingDirectory, '');
    });
  });
}
