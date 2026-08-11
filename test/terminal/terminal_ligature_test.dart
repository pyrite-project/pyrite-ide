import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/ui/painter.dart';
import 'package:xterm/xterm.dart';

void main() {
  TerminalPainter painter({bool enabled = true}) => TerminalPainter(
    theme: TerminalThemes.defaultTheme,
    textStyle: TerminalStyle(enableLigatures: enabled),
    textScaler: TextScaler.noScaling,
  );

  test('groups adjacent compatible cells into a shaping run', () {
    final terminal = Terminal();
    terminal.write('=> !=');

    expect(painter().debugLigatureRuns(terminal.buffer.lines[0]), ['=>', '!=']);
  });

  test('breaks shaping runs when terminal style changes', () {
    final terminal = Terminal();
    terminal.write('=\x1b[31m>');

    expect(painter().debugLigatureRuns(terminal.buffer.lines[0]), ['=', '>']);
  });

  test('does not build shaping runs when ligatures are disabled', () {
    final terminal = Terminal();
    terminal.write('=>');

    expect(
      painter(enabled: false).debugLigatureRuns(terminal.buffer.lines[0]),
      isEmpty,
    );
  });

  test('explicitly enables and disables OpenType ligature features', () {
    List<String> features(bool enabled) =>
        TerminalStyle(enableLigatures: enabled).toTextStyle().fontFeatures!.map(
          (feature) {
            return '${feature.feature}:${feature.value}';
          },
        ).toList();

    expect(features(true), ['liga:1', 'calt:1']);
    expect(features(false), ['liga:0', 'calt:0']);
  });

  testWidgets('paints a shaped terminal line without changing the cell grid', (
    tester,
  ) async {
    final terminal = Terminal();
    terminal.write('const ready = value != null => true;');

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 640,
          height: 240,
          child: TerminalView(
            terminal,
            textStyle: const TerminalStyle(enableLigatures: true),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(terminal.buffer.lines[0].getCodePoint(6), 'r'.codeUnitAt(0));
  });
}
