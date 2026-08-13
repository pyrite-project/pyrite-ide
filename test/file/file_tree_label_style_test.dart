import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/pages/file/main.dart';

void main() {
  group('fileTreeLabelStyle', () {
    for (final brightness in Brightness.values) {
      test('uses selected foreground for hidden item in $brightness theme', () {
        final colorScheme = ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: brightness,
        );

        final style = fileTreeLabelStyle(
          colorScheme: colorScheme,
          baseStyle: const TextStyle(fontSize: 12),
          isHidden: true,
          isSelected: true,
        );

        expect(style?.color, colorScheme.onSecondaryContainer);
        expect(style?.fontSize, 12);
      });
    }

    test('uses muted foreground for unselected hidden item', () {
      final colorScheme = ColorScheme.fromSeed(seedColor: Colors.blue);

      final style = fileTreeLabelStyle(
        colorScheme: colorScheme,
        baseStyle: null,
        isHidden: true,
        isSelected: false,
      );

      expect(style?.color, colorScheme.outline);
    });

    test('keeps the base style for a visible item', () {
      final colorScheme = ColorScheme.fromSeed(seedColor: Colors.blue);
      const baseStyle = TextStyle(color: Colors.pink);

      final style = fileTreeLabelStyle(
        colorScheme: colorScheme,
        baseStyle: baseStyle,
        isHidden: false,
        isSelected: true,
      );

      expect(style, same(baseStyle));
    });
  });
}
