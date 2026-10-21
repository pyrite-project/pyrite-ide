import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/ui/painter.dart';
import 'package:xterm/xterm.dart';

/// 这个文件逐像素验证 xterm 自绘字形（powerline、块元素、制表符）的几何。
///
/// 注意：期望值描述的是**当前渲染出的实际几何**，不是“字形设计上应该长
/// 什么样”。xterm 是 git submodule（xterm.dart/**），不在 PyriteIDE 的可改
/// 范围内，因此当自绘实现改变了某种字形的画法时，测试按真实行为更新并注明
/// 理由，而不是反过来要求渲染器迁就旧断言。下面 0xE0B2 / 0xE0B3 的差异
/// 就是这么来的（实心三角形 vs 细描边三角形）。
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
        // 为什么这里的期望值是“实际几何”而不是设计文案：
        //
        // xterm 的 `_paintPowerlineSymbol` 对 powerline 做了两套画法：
        // 0xE0B0/0xE0B2 是实心三角形（fill，path.close()），而
        // 0xE0B1/0xE0B3 这对 “thin” 变体是**描边**三角形
        // （PaintingStyle.stroke，strokeWidth = cellWidth/8 且上限 2.0）。
        // 描边只画三角形的边，不作为实心块覆盖整格：在格子中间那一行，
        // 0xE0B2 的实心填充从左边缘一直铺到右边缘（含 bleed），而 0xE0B3
        // 只有那条斜边的描边宽度碰到格子两端的角落，右边缘的中间行本来就是
        // 透明的。
        //
        // 也就是说，“左向 powerline 在中间行覆盖左右两个格子边缘”只对
        // 实心变体 0xE0B2 成立；0xE0B3 作为细描边变体，它的两端覆盖点在
        // 靠上/靠下的角落，而不是中间行。这是 xterm 自绘字形（第三方
        // submodule，本次不可改）的既有几何，不是 PyriteIDE 的 bug，因此
        // 期望值按实际渲染结果区分两个变体。
        if (charCode == 0xe0b2) {
          expect(
            await _hasPaintAt(image, x: image.width - 2, y: image.height ~/ 2),
            isTrue,
          );
        } else {
          // 细描边变体：中间行右边缘没有实心覆盖，但描边必须落在格子内，
          // 即这条斜边在右端确实被画到了（靠角落的那两行）。
          expect(
            await _hasPaintAt(image, x: image.width - 2, y: 1),
            isTrue,
            reason: '0xE0B3 的描边斜边应到达右端角落（y=1）',
          );
          expect(
            await _hasPaintAt(image, x: image.width - 2, y: image.height ~/ 2),
            isFalse,
            reason: '0xE0B3 是描边三角形，中间行右边缘不填充',
          );
        }
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
