import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  test('contrast adjustment reaches the configured minimum', () {
    const foreground = Color(0xFFDDDDDD);
    const background = Color(0xFFFFFFFF);

    final adjusted = ensureTerminalContrast(foreground, background, 4.5);

    expect(
      terminalContrastRatio(adjusted, background),
      greaterThanOrEqualTo(4.5),
    );
    expect(adjusted, isNot(foreground));
  });

  test('contrast adjustment is disabled at ratio one', () {
    const foreground = Color(0xFFDDDDDD);
    const background = Color(0xFFFFFFFF);

    expect(ensureTerminalContrast(foreground, background, 1), foreground);
  });
}
