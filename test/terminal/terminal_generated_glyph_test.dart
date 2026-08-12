import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/ui/painter.dart';
import 'package:xterm/xterm.dart';

void main() {
  final painter = TerminalPainter(
    theme: TerminalThemes.defaultTheme,
    textStyle: const TerminalStyle(fontSize: 20, height: 1.4),
    textScaler: TextScaler.noScaling,
  );

  test(
    'solid block glyph fills the cell height when line height is tall',
    () async {
      final image = await _paintGeneratedGlyph(painter, 0x2588);

      expect(await _hasPaintAt(image, x: image.width ~/ 2, y: 1), isTrue);
      expect(
        await _hasPaintAt(image, x: image.width ~/ 2, y: image.height - 2),
        isTrue,
      );
    },
  );

  test('powerline right separator reaches the next cell edge', () async {
    final image = await _paintGeneratedGlyph(painter, 0xe0b0);

    expect(
      await _hasPaintAt(image, x: image.width - 2, y: image.height ~/ 2),
      isTrue,
    );
  });

  test('box drawing light left stays on the cell center line', () async {
    final image = await _paintGeneratedGlyph(painter, 0x2574);

    expect(await _hasPaintAt(image, x: 2, y: image.height ~/ 2), isTrue);
  });

  for (final corner in [
    (charCode: 0x256d, horizontalX: -2, verticalY: -2), // ╭
    (charCode: 0x256e, horizontalX: 2, verticalY: -2), // ╮
    (charCode: 0x256f, horizontalX: 2, verticalY: 2), // ╯
    (charCode: 0x2570, horizontalX: -2, verticalY: 2), // ╰
  ]) {
    test(
      'rounded box drawing ${corner.charCode} reaches both cell edges',
      () async {
        final image = await _paintGeneratedGlyph(painter, corner.charCode);
        final centerX = image.width ~/ 2;
        final centerY = image.height ~/ 2;
        final horizontalX = corner.horizontalX < 0
            ? image.width + corner.horizontalX
            : corner.horizontalX;
        final verticalY = corner.verticalY < 0
            ? image.height + corner.verticalY
            : corner.verticalY;

        expect(await _hasPaintAt(image, x: horizontalX, y: centerY), isTrue);
        expect(await _hasPaintAt(image, x: centerX, y: verticalY), isTrue);
      },
    );
  }

  test('rounded box drawing overlaps adjacent straight segments', () async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const origin = Offset(1, 1);
    final cellWidth = painter.cellSize.width;
    final cellHeight = painter.cellSize.height;

    void paintGlyph(int charCode, Offset offset) {
      painter.paintCellForeground(
        canvas,
        offset,
        CellData(
          foreground: CellColor.rgb | 0xffffff,
          background: CellColor.normal,
          flags: 0,
          content: charCode | (1 << CellContent.widthShift),
        ),
      );
    }

    paintGlyph(0x2502, origin); // │
    paintGlyph(0x2570, origin + Offset(0, cellHeight)); // ╰
    paintGlyph(0x2500, origin + Offset(cellWidth, cellHeight)); // ─

    final image = await recorder.endRecording().toImage(
      (cellWidth * 2).ceil() + 2,
      (cellHeight * 2).ceil() + 2,
    );
    final centerX = (origin.dx + cellWidth / 2).round();
    final centerY = (origin.dy + cellHeight * 1.5).round();
    final rowBoundary = (origin.dy + cellHeight).round();
    final columnBoundary = (origin.dx + cellWidth).round();

    for (final y in [rowBoundary - 1, rowBoundary, rowBoundary + 1]) {
      expect(await _hasPaintAt(image, x: centerX, y: y), isTrue);
    }
    for (final x in [columnBoundary - 1, columnBoundary, columnBoundary + 1]) {
      expect(await _hasPaintAt(image, x: x, y: centerY), isTrue);
    }
  });

  test('adjacent horizontal box drawing cells stay solid', () async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const origin = Offset(1, 1);
    final cellWidth = painter.cellSize.width;
    final cellHeight = painter.cellSize.height;
    final cellData = CellData(
      foreground: CellColor.rgb | 0xffffff,
      background: CellColor.normal,
      flags: 0,
      content: 0x2500 | (1 << CellContent.widthShift),
    );

    for (var column = 0; column < 3; column++) {
      painter.paintCellForeground(
        canvas,
        origin + Offset(cellWidth * column, 0),
        cellData,
      );
    }

    final image = await recorder.endRecording().toImage(
      (cellWidth * 3).ceil() + 2,
      cellHeight.ceil() + 2,
    );
    final centerY = (origin.dy + cellHeight / 2).round();

    for (var x = origin.dx.ceil(); x < (origin.dx + cellWidth * 3); x++) {
      expect(await _alphaAt(image, x: x, y: centerY), 255);
    }
  });

  test('powerline separator overlaps its left cell boundary', () async {
    final image = await _paintGeneratedGlyph(painter, 0xe0b0);

    expect(await _hasPaintAt(image, x: 0, y: image.height ~/ 2), isTrue);
  });

  test('powerline separator stays inside its row', () async {
    final image = await _paintGeneratedGlyph(painter, 0xe0b0);

    expect(await _hasPaintOnRow(image, 0), isFalse);
    expect(await _hasPaintOnRow(image, image.height - 1), isFalse);
  });

  test('powerline separator fully covers a fractional left edge', () async {
    final image = await _paintGeneratedGlyph(
      painter,
      0xe0b0,
      offset: const Offset(1.25, 1),
    );

    expect(await _alphaAt(image, x: 1, y: image.height ~/ 2), 255);
  });

  for (final charCode in [0xe0b2, 0xe0b3]) {
    test(
      'left powerline separator $charCode overlaps both cell edges',
      () async {
        final image = await _paintGeneratedGlyph(painter, charCode);

        expect(await _hasPaintAt(image, x: 0, y: image.height ~/ 2), isTrue);
        expect(
          await _hasPaintAt(image, x: image.width - 2, y: image.height ~/ 2),
          isTrue,
        );
      },
    );
  }
}

Future<ui.Image> _paintGeneratedGlyph(
  TerminalPainter painter,
  int charCode, {
  Offset offset = const Offset(1, 1),
}) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final cellData = CellData(
    foreground: CellColor.rgb | 0xffffff,
    background: CellColor.normal,
    flags: 0,
    content: charCode | (1 << CellContent.widthShift),
  );
  final imageWidth = painter.cellSize.width.ceil() + 2;
  final imageHeight = painter.cellSize.height.ceil() + 2;

  painter.paintCellForeground(canvas, offset, cellData);

  return recorder.endRecording().toImage(imageWidth, imageHeight);
}

Future<bool> _hasPaintAt(
  ui.Image image, {
  required int x,
  required int y,
}) async {
  return await _alphaAt(image, x: x, y: y) > 0;
}

Future<int> _alphaAt(ui.Image image, {required int x, required int y}) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final byteOffset = (y * image.width + x) * 4;
  return data.getUint8(byteOffset + 3);
}

Future<bool> _hasPaintOnRow(ui.Image image, int y) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  for (var x = 0; x < image.width; x++) {
    final byteOffset = (y * image.width + x) * 4;
    if (data.getUint8(byteOffset + 3) > 0) return true;
  }
  return false;
}
