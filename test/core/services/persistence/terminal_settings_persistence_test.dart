import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/models/terminal_appearance.dart';
import 'package:pyrite_ide/core/services/persistence/settings_persistence.dart';

void main() {
  test('terminal appearance settings use backward-compatible defaults', () {
    final data = SettingsPersistedData.fromJson(const {});

    expect(data.terminalAppearance, TerminalAppearance.dark.name);
    expect(data.terminalLigatures, isTrue);
    expect(data.terminalMinimumContrast, isFalse);
    expect(data.terminalCustomForeground, kDefaultTerminalCustomForeground);
    expect(data.terminalCustomForeground, 0xFFFFFFFF);
    expect(data.terminalCustomBackground, kDefaultTerminalCustomBackground);
  });

  test('terminal colors and ANSI palette round-trip', () {
    final data = SettingsPersistedData.fromJson({
      'terminalAppearance': TerminalAppearance.custom.name,
      'terminalLigatures': false,
      'terminalMinimumContrast': true,
      'terminalCustomForeground': 0xFF112233,
      'terminalCustomBackground': 0xFF445566,
      'terminalCustomPalette': List<int>.generate(16, (index) => index),
    });
    final json = data.toJson();

    expect(json['terminalAppearance'], TerminalAppearance.custom.name);
    expect(json['terminalLigatures'], isFalse);
    expect(json['terminalMinimumContrast'], isTrue);
    expect(json['terminalCustomForeground'], 0xFF112233);
    expect(json['terminalCustomBackground'], 0xFF445566);
    expect(
      json['terminalCustomPalette'],
      List<int>.generate(16, (index) => index),
    );
  });

  test('LSP virtual environment round-trips with a compatible default', () {
    expect(SettingsPersistedData.fromJson(const {}).lspVirtualEnvironment, '');

    final data = SettingsPersistedData.fromJson({
      'lspVirtualEnvironment': '/workspace/.venv',
    });

    expect(data.lspVirtualEnvironment, '/workspace/.venv');
    expect(data.toJson()['lspVirtualEnvironment'], '/workspace/.venv');
    expect(data.toJson().containsKey('lspPythonInterpreter'), isFalse);
  });

  test('LSP language ID and stdio arguments use generic defaults', () {
    final defaults = SettingsPersistedData.fromJson(const {});
    expect(defaults.lspLanguageId, 'python');
    expect(defaults.lspStdioArgs, isEmpty);

    final data = SettingsPersistedData.fromJson({
      'lspLanguageId': 'custom-language',
      'lspStdioArgs': 'serve --stdio',
    });

    expect(data.toJson()['lspLanguageId'], 'custom-language');
    expect(data.toJson()['lspStdioArgs'], 'serve --stdio');
  });

  test('migrates an old LSP Python interpreter path to its environment', () {
    final data = SettingsPersistedData.fromJson({
      'lspPythonInterpreter': '/workspace/.venv/bin/python',
    });

    expect(data.lspVirtualEnvironment, '/workspace/.venv');
  });

  test(
    'BasedPyright type checking mode round-trips with a compatible default',
    () {
      expect(
        SettingsPersistedData.fromJson(
          const {},
        ).lspBasedPyrightTypeCheckingMode,
        'standard',
      );

      final data = SettingsPersistedData.fromJson({
        'lspBasedPyrightTypeCheckingMode': 'strict',
      });

      expect(data.lspBasedPyrightTypeCheckingMode, 'strict');
      expect(data.toJson()['lspBasedPyrightTypeCheckingMode'], 'strict');
    },
  );

  test('inlay hint display setting round-trips with a compatible default', () {
    expect(SettingsPersistedData.fromJson(const {}).lspShowInlayHints, isFalse);

    final data = SettingsPersistedData.fromJson({'lspShowInlayHints': true});

    expect(data.lspShowInlayHints, isTrue);
    expect(data.toJson()['lspShowInlayHints'], isTrue);
  });
}
