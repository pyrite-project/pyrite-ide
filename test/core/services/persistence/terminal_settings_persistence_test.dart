import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/models/terminal_appearance.dart';
import 'package:pyrite_ide/core/services/persistence/settings_persistence.dart';

void main() {
  test('terminal appearance settings use backward-compatible defaults', () {
    final data = SettingsPersistedData.fromJson(const {});

    expect(data.terminalAppearance, TerminalAppearance.dark.name);
    expect(data.terminalLigatures, isTrue);
    expect(data.terminalMinimumContrast, isFalse);
    expect(data.terminalOverrideBackground, isFalse);
    expect(data.terminalCustomForeground, kDefaultTerminalCustomForeground);
    expect(data.terminalCustomForeground, 0xFFFFFFFF);
    expect(data.terminalCustomBackground, kDefaultTerminalCustomBackground);
  });

  test(
    'background and foreground settings round-trip without ANSI palette',
    () {
      final data = SettingsPersistedData.fromJson({
        'terminalAppearance': TerminalAppearance.custom.name,
        'terminalLigatures': false,
        'terminalMinimumContrast': true,
        'terminalOverrideBackground': true,
        'terminalCustomForeground': 0xFF112233,
        'terminalCustomBackground': 0xFF445566,
        'terminalCustomPalette': List<int>.generate(16, (index) => index),
      });
      final json = data.toJson();

      expect(json['terminalAppearance'], TerminalAppearance.custom.name);
      expect(json['terminalLigatures'], isFalse);
      expect(json['terminalMinimumContrast'], isTrue);
      expect(json['terminalOverrideBackground'], isTrue);
      expect(json['terminalCustomForeground'], 0xFF112233);
      expect(json['terminalCustomBackground'], 0xFF445566);
      expect(json, isNot(contains('terminalCustomPalette')));
    },
  );
}
