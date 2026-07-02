import 'dart:ui';
import 'package:flutter/painting.dart';

import 'package:xterm/src/ui/palette_builder.dart';
import 'package:xterm/src/ui/paragraph_cache.dart';
import 'package:xterm/xterm.dart';

/// Encapsulates the logic for painting various terminal elements.
class TerminalPainter {
  TerminalPainter({
    required TerminalTheme theme,
    required TerminalStyle textStyle,
    required TextScaler textScaler,
  })  : _textStyle = textStyle,
        _theme = theme,
        _textScaler = textScaler;

  /// A lookup table from terminal colors to Flutter colors.
  late var _colorPalette = PaletteBuilder(_theme).build();

  /// Size of each character in the terminal.
  late var _cellSize = _measureCharSize();

  /// The cached for cells in the terminal. Should be cleared when the same
  /// cell no longer produces the same visual output. For example, when
  /// [_textStyle] is changed, or when the system font changes.
  final _paragraphCache = ParagraphCache(10240);

  TerminalStyle get textStyle => _textStyle;
  TerminalStyle _textStyle;
  set textStyle(TerminalStyle value) {
    if (value == _textStyle) return;
    _textStyle = value;
    _cellSize = _measureCharSize();
    _paragraphCache.clear();
  }

  TextScaler get textScaler => _textScaler;
  TextScaler _textScaler = TextScaler.linear(1.0);
  set textScaler(TextScaler value) {
    if (value == _textScaler) return;
    _textScaler = value;
    _cellSize = _measureCharSize();
    _paragraphCache.clear();
  }

  TerminalTheme get theme => _theme;
  TerminalTheme _theme;
  set theme(TerminalTheme value) {
    if (value == _theme) return;
    _theme = value;
    _colorPalette = PaletteBuilder(value).build();
    _paragraphCache.clear();
  }

  Size _measureCharSize() {
    const test = 'mmmmmmmmmm';

    final textStyle = _textStyle.toTextStyle();
    final builder = ParagraphBuilder(textStyle.getParagraphStyle());
    builder.pushStyle(textStyle.getTextStyle(textScaler: _textScaler));
    builder.addText(test);

    final paragraph = builder.build();
    paragraph.layout(ParagraphConstraints(width: double.infinity));

    final result = Size(
      paragraph.maxIntrinsicWidth / test.length,
      paragraph.height,
    );

    paragraph.dispose();
    return result;
  }

  /// The size of each character in the terminal.
  Size get cellSize => _cellSize;

  /// When the set of font available to the system changes, call this method to
  /// clear cached state related to font rendering.
  void clearFontCache() {
    _cellSize = _measureCharSize();
    _paragraphCache.clear();
  }

  /// Paints the cursor based on the current cursor type.
  void paintCursor(
    Canvas canvas,
    Offset offset, {
    required TerminalCursorType cursorType,
    bool hasFocus = true,
  }) {
    final paint = Paint()
      ..color = _theme.cursor
      ..strokeWidth = 1;

    if (!hasFocus) {
      paint.style = PaintingStyle.stroke;
      canvas.drawRect(offset & _cellSize, paint);
      return;
    }

    switch (cursorType) {
      case TerminalCursorType.block:
        paint.style = PaintingStyle.fill;
        canvas.drawRect(offset & _cellSize, paint);
        return;
      case TerminalCursorType.underline:
        return canvas.drawLine(
          Offset(offset.dx, _cellSize.height - 1),
          Offset(offset.dx + _cellSize.width, _cellSize.height - 1),
          paint,
        );
      case TerminalCursorType.verticalBar:
        return canvas.drawLine(
          Offset(offset.dx, 0),
          Offset(offset.dx, _cellSize.height),
          paint,
        );
    }
  }

  @pragma('vm:prefer-inline')
  void paintHighlight(Canvas canvas, Offset offset, int length, Color color) {
    final endOffset = offset.translate(
      length * _cellSize.width,
      _cellSize.height,
    );

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    canvas.drawRect(Rect.fromPoints(offset, endOffset), paint);
  }

  /// Paints [line] to [canvas] at [offset]. The x offset of [offset] is usually
  /// 0, and the y offset is the top of the line.
  void paintLine(Canvas canvas, Offset offset, BufferLine line) {
    final cellData = CellData.empty();
    final cellWidth = _cellSize.width;

    for (var i = 0; i < line.length; i++) {
      line.getCellData(i, cellData);

      final charWidth = cellData.content >> CellContent.widthShift;
      final cellOffset = offset.translate(i * cellWidth, 0);

      paintCell(canvas, cellOffset, cellData);

      if (charWidth == 2) {
        i++;
      }
    }
  }

  @pragma('vm:prefer-inline')
  void paintCell(Canvas canvas, Offset offset, CellData cellData) {
    paintCellBackground(canvas, offset, cellData);
    paintCellForeground(canvas, offset, cellData);
  }

  /// Paints the character in the cell represented by [cellData] to [canvas] at
  /// [offset].
  @pragma('vm:prefer-inline')
  void paintCellForeground(Canvas canvas, Offset offset, CellData cellData) {
    final charCode = cellData.content & CellContent.codepointMask;
    if (charCode == 0) return;

    final cellFlags = cellData.flags;
    var color = cellFlags & CellFlags.inverse == 0
        ? resolveForegroundColor(cellData.foreground)
        : resolveBackgroundColor(cellData.background);

    if (cellFlags & CellFlags.faint != 0) {
      color = color.withValues(alpha: 0.5);
    }

    if (_paintBoxDrawing(canvas, offset, charCode, color)) return;

    final cacheKey = cellData.getHash() ^ _textScaler.hashCode;
    var paragraph = _paragraphCache.getLayoutFromCache(cacheKey);

    if (paragraph == null) {
      final underline = cellFlags & CellFlags.underline != 0 &&
          !_skipUnderlineDecoration(charCode);

      final style = _textStyle.toTextStyle(
        color: color,
        bold: cellFlags & CellFlags.bold != 0,
        italic: cellFlags & CellFlags.italic != 0,
        underline: underline,
      );

      var char = String.fromCharCode(charCode);

      paragraph = _paragraphCache.performAndCacheLayout(
        char,
        style,
        _textScaler,
        cacheKey,
      );
    }

    canvas.drawParagraph(paragraph, offset);
  }

  bool _paintBoxDrawing(
    Canvas canvas,
    Offset offset,
    int charCode,
    Color color,
  ) {
    if (_paintRoundedBoxDrawing(canvas, offset, charCode, color)) return true;

    final connections = _boxDrawingConnections(charCode);
    if (connections == 0) return false;

    final strokeWidth = (_cellSize.height / 12).clamp(1.0, 1.5).toDouble();
    final halfStroke = strokeWidth / 2;
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt
      ..isAntiAlias = false;

    final left = offset.dx - halfStroke;
    final right = offset.dx + _cellSize.width + halfStroke;
    final top = offset.dy - halfStroke;
    final bottom = offset.dy + _cellSize.height + halfStroke;
    final centerX = offset.dx + _cellSize.width / 2;
    final centerY = offset.dy + _cellSize.height / 2;

    if (connections & _boxLeft != 0) {
      canvas.drawLine(Offset(left, centerY), Offset(centerX, centerY), paint);
    }
    if (connections & _boxRight != 0) {
      canvas.drawLine(Offset(centerX, centerY), Offset(right, centerY), paint);
    }
    if (connections & _boxUp != 0) {
      canvas.drawLine(Offset(centerX, top), Offset(centerX, centerY), paint);
    }
    if (connections & _boxDown != 0) {
      canvas.drawLine(Offset(centerX, centerY), Offset(centerX, bottom), paint);
    }

    return true;
  }

  bool _paintRoundedBoxDrawing(
    Canvas canvas,
    Offset offset,
    int charCode,
    Color color,
  ) {
    if (charCode < 0x256d || charCode > 0x2570) return false;

    final strokeWidth = (_cellSize.height / 12).clamp(1.0, 1.5).toDouble();
    final halfStroke = strokeWidth / 2;
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    final left = offset.dx - halfStroke;
    final right = offset.dx + _cellSize.width + halfStroke;
    final top = offset.dy - halfStroke;
    final bottom = offset.dy + _cellSize.height + halfStroke;
    final centerX = offset.dx + _cellSize.width / 2;
    final centerY = offset.dy + _cellSize.height / 2;
    final path = Path();

    switch (charCode) {
      case 0x256d: // ╭
        path.moveTo(right, centerY);
        path.quadraticBezierTo(centerX, centerY, centerX, bottom);
        break;
      case 0x256e: // ╮
        path.moveTo(left, centerY);
        path.quadraticBezierTo(centerX, centerY, centerX, bottom);
        break;
      case 0x256f: // ╯
        path.moveTo(left, centerY);
        path.quadraticBezierTo(centerX, centerY, centerX, top);
        break;
      case 0x2570: // ╰
        path.moveTo(right, centerY);
        path.quadraticBezierTo(centerX, centerY, centerX, top);
        break;
    }

    canvas.drawPath(path, paint);
    return true;
  }

  static const _boxLeft = 1;
  static const _boxRight = 1 << 1;
  static const _boxUp = 1 << 2;
  static const _boxDown = 1 << 3;

  int _boxDrawingConnections(int charCode) {
    switch (charCode) {
      case 0x2500: // ─
      case 0x2550: // ═
        return _boxLeft | _boxRight;
      case 0x2502: // │
      case 0x2551: // ║
        return _boxUp | _boxDown;
      case 0x250c: // ┌
      case 0x2554: // ╔
        return _boxRight | _boxDown;
      case 0x2510: // ┐
      case 0x2557: // ╗
        return _boxLeft | _boxDown;
      case 0x2514: // └
      case 0x255a: // ╚
        return _boxRight | _boxUp;
      case 0x2518: // ┘
      case 0x255d: // ╝
        return _boxLeft | _boxUp;
      case 0x251c: // ├
      case 0x2560: // ╠
        return _boxUp | _boxDown | _boxRight;
      case 0x2524: // ┤
      case 0x2563: // ╣
        return _boxUp | _boxDown | _boxLeft;
      case 0x252c: // ┬
      case 0x2566: // ╦
        return _boxLeft | _boxRight | _boxDown;
      case 0x2534: // ┴
      case 0x2569: // ╩
        return _boxLeft | _boxRight | _boxUp;
      case 0x253c: // ┼
      case 0x256c: // ╬
        return _boxLeft | _boxRight | _boxUp | _boxDown;
      default:
        return 0;
    }
  }

  bool _skipUnderlineDecoration(int charCode) {
    if (charCode == 0x20 || charCode == 0x3000) return true;

    // Box drawing glyphs already represent UI lines. Applying a text underline
    // creates a second line below Claude-style terminal panels.
    return charCode >= 0x2500 && charCode <= 0x257f;
  }

  /// Paints the background of a cell represented by [cellData] to [canvas] at
  /// [offset].
  @pragma('vm:prefer-inline')
  void paintCellBackground(Canvas canvas, Offset offset, CellData cellData) {
    late Color color;
    final colorType = cellData.background & CellColor.typeMask;

    if (cellData.flags & CellFlags.inverse != 0) {
      color = resolveForegroundColor(cellData.foreground);
    } else if (colorType == CellColor.normal) {
      return;
    } else {
      color = resolveBackgroundColor(cellData.background);
    }

    final paint = Paint()..color = color;
    final doubleWidth = cellData.content >> CellContent.widthShift == 2;
    final widthScale = doubleWidth ? 2 : 1;
    final size = Size(_cellSize.width * widthScale + 1, _cellSize.height);
    canvas.drawRect(offset & size, paint);
  }

  /// Get the effective foreground color for a cell from information encoded in
  /// [cellColor].
  @pragma('vm:prefer-inline')
  Color resolveForegroundColor(int cellColor) {
    final colorType = cellColor & CellColor.typeMask;
    final colorValue = cellColor & CellColor.valueMask;

    switch (colorType) {
      case CellColor.normal:
        return _theme.foreground;
      case CellColor.named:
      case CellColor.palette:
        return _colorPalette[colorValue];
      case CellColor.rgb:
      default:
        return Color(colorValue | 0xFF000000);
    }
  }

  /// Get the effective background color for a cell from information encoded in
  /// [cellColor].
  @pragma('vm:prefer-inline')
  Color resolveBackgroundColor(int cellColor) {
    final colorType = cellColor & CellColor.typeMask;
    final colorValue = cellColor & CellColor.valueMask;

    switch (colorType) {
      case CellColor.normal:
        return _theme.background;
      case CellColor.named:
      case CellColor.palette:
        return _colorPalette[colorValue];
      case CellColor.rgb:
      default:
        return Color(colorValue | 0xFF000000);
    }
  }
}
