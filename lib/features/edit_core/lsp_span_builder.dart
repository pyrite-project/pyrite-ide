import 'package:flutter/material.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/pylsp/data.dart';
import 'package:pyrite_ide/tool_ds/tool_ds.dart';
import 'package:re_editor/re_editor.dart';

typedef LspSpanBuilderDiagnosticsReader =
    Map<String, List<DiagnosticItem>> Function();
typedef LspSpanBuilderHighlightsReader =
    Map<String, List<LspDocumentHighlight>> Function();
typedef LspSpanBuilderSemanticTokensReader =
    Map<String, Map<int, List<LspSemanticToken>>> Function();

CodeLineSpanBuilder buildLspSpanBuilder({
  required String uri,
  LspSpanBuilderDiagnosticsReader? diagnosticsReader,
  LspSpanBuilderHighlightsReader? highlightsReader,
  LspSpanBuilderSemanticTokensReader? semanticTokensReader,
}) {
  final readDiagnostics =
      diagnosticsReader ?? () => container.read(diagnosticsByUri);
  final readHighlights =
      highlightsReader ?? () => container.read(documentHighlightsByUri);
  final readSemanticTokens =
      semanticTokensReader ?? () => container.read(semanticTokensByUri);

  return ({
    required BuildContext context,
    required int index,
    required CodeLine codeLine,
    required TextSpan textSpan,
    required TextStyle style,
  }) {
    final lineText = codeLine.text;
    if (lineText.isEmpty) return textSpan;

    final tool = context.tool;
    final diagnostics = readDiagnostics()[uri] ?? const <DiagnosticItem>[];
    final highlights =
        readHighlights()[uri] ?? const <LspDocumentHighlight>[];
    final semanticByLine = readSemanticTokens()[uri];
    final semanticTokensForLine =
        semanticByLine == null ? const <LspSemanticToken>[] : (semanticByLine[index] ?? const <LspSemanticToken>[]);

    final diagRanges = _collectDiagnosticsRangesForLine(
      diagnostics: diagnostics,
      lineIndex: index,
      lineLength: lineText.length,
      tool: tool,
    );
    final highlightRanges = _collectDocumentHighlightRangesForLine(
      highlights: highlights,
      lineIndex: index,
      lineLength: lineText.length,
      tool: tool,
    );
    final semanticRanges = _collectSemanticRangesForLine(
      tokens: semanticTokensForLine,
      lineLength: lineText.length,
    );

    if (diagRanges.isEmpty && highlightRanges.isEmpty && semanticRanges.isEmpty) {
      return textSpan;
    }

    final baseRuns = _flattenTextSpan(textSpan, style, lineText.length);
    if (baseRuns.isEmpty) return textSpan;

    final cutPoints = <int>{0, lineText.length};
    for (final run in baseRuns) {
      cutPoints.add(run.start);
      cutPoints.add(run.end);
    }
    for (final overlay in diagRanges) {
      cutPoints.add(overlay.start);
      cutPoints.add(overlay.end);
    }
    for (final overlay in highlightRanges) {
      cutPoints.add(overlay.start);
      cutPoints.add(overlay.end);
    }
    for (final overlay in semanticRanges) {
      cutPoints.add(overlay.start);
      cutPoints.add(overlay.end);
    }

    final points = cutPoints.toList()..sort();
    final children = <InlineSpan>[];

    var runIndex = 0;
    for (var i = 0; i < points.length - 1; i++) {
      final start = points[i];
      final end = points[i + 1];
      if (start >= end) continue;

      while (runIndex < baseRuns.length && baseRuns[runIndex].end <= start) {
        runIndex++;
      }
      if (runIndex >= baseRuns.length) break;
      final baseRun = baseRuns[runIndex];
      final baseStyle = baseRun.style;

      final segmentText = lineText.substring(start, end);
      if (segmentText.isEmpty) continue;

      final diagnostic = _pickMostSevereDiagnostic(diagRanges, start, end);
      final documentHighlight = _pickHighlight(highlightRanges, start, end);
      final semantic = _pickSemantic(semanticRanges, start, end);

      var effectiveStyle = baseStyle;
      if (documentHighlight != null) {
        effectiveStyle = effectiveStyle.copyWith(
          backgroundColor: documentHighlight.backgroundColor,
        );
      }
      if (semantic?.fontWeight != null) {
        effectiveStyle = effectiveStyle.copyWith(fontWeight: semantic!.fontWeight);
      }
      if (diagnostic != null) {
        effectiveStyle = effectiveStyle.copyWith(
          decoration: TextDecoration.underline,
          decorationColor: diagnostic.color,
          decorationStyle: diagnostic.style,
          decorationThickness: 1.3,
        );
      }

      children.add(TextSpan(text: segmentText, style: effectiveStyle));
    }

    return TextSpan(style: style, children: children);
  };
}

class _BaseRun {
  const _BaseRun({
    required this.start,
    required this.end,
    required this.style,
  });

  final int start;
  final int end;
  final TextStyle style;
}

List<_BaseRun> _flattenTextSpan(TextSpan span, TextStyle fallbackStyle, int maxLength) {
  final runs = <_BaseRun>[];
  var offset = 0;

  void walk(InlineSpan inline, TextStyle inheritedStyle) {
    if (offset >= maxLength) return;

    if (inline is TextSpan) {
      final mergedStyle = inheritedStyle.merge(inline.style);

      final text = inline.text;
      if (text != null && text.isNotEmpty) {
        final clampedText = offset + text.length <= maxLength
            ? text
            : text.substring(0, maxLength - offset);
        final start = offset;
        offset += clampedText.length;
        runs.add(_BaseRun(start: start, end: offset, style: mergedStyle));
      }

      final children = inline.children;
      if (children != null) {
        for (final child in children) {
          walk(child, mergedStyle);
        }
      }
      return;
    }

    final text = inline.toPlainText(includePlaceholders: false);
    if (text.isEmpty) return;
    final clampedText = offset + text.length <= maxLength
        ? text
        : text.substring(0, maxLength - offset);
    final start = offset;
    offset += clampedText.length;
    runs.add(_BaseRun(start: start, end: offset, style: inheritedStyle));
  }

  walk(span, fallbackStyle.merge(span.style));

  if (runs.isEmpty && maxLength > 0) {
    runs.add(_BaseRun(start: 0, end: maxLength, style: fallbackStyle));
  }

  return runs;
}

class _DiagnosticOverlay {
  const _DiagnosticOverlay({
    required this.start,
    required this.end,
    required this.severity,
    required this.color,
    required this.style,
  });

  final int start;
  final int end;
  final int severity;
  final Color color;
  final TextDecorationStyle style;
}

List<_DiagnosticOverlay> _collectDiagnosticsRangesForLine({
  required List<DiagnosticItem> diagnostics,
  required int lineIndex,
  required int lineLength,
  required ToolTokens tool,
}) {
  final result = <_DiagnosticOverlay>[];

  for (final diagnostic in diagnostics) {
    final startLine = diagnostic.range.start["line"] as int;
    final startChar = diagnostic.range.start["character"] as int;
    final endLine = diagnostic.range.end["line"] as int;
    final endChar = diagnostic.range.end["character"] as int;

    if (lineIndex < startLine || lineIndex > endLine) continue;

    final rangeStart = lineIndex == startLine ? startChar : 0;
    final rangeEnd = lineIndex == endLine ? endChar : lineLength;

    final clampedStart = rangeStart.clamp(0, lineLength);
    final clampedEnd = rangeEnd.clamp(0, lineLength);
    if (clampedStart >= clampedEnd) continue;

    final (color, style) = _diagnosticDecoration(diagnostic.severity, tool);
    result.add(
      _DiagnosticOverlay(
        start: clampedStart,
        end: clampedEnd,
        severity: diagnostic.severity,
        color: color,
        style: style,
      ),
    );
  }

  return result;
}

(Color, TextDecorationStyle) _diagnosticDecoration(int severity, ToolTokens tool) {
  switch (severity) {
    case 1:
      return (tool.colors.diagnosticError, TextDecorationStyle.wavy);
    case 2:
      return (tool.colors.diagnosticWarning, TextDecorationStyle.wavy);
    case 3:
      return (tool.colors.diagnosticInfo, TextDecorationStyle.dotted);
    case 4:
      return (tool.colors.textFaint, TextDecorationStyle.dotted);
    default:
      return (tool.colors.textFaint, TextDecorationStyle.solid);
  }
}

class _HighlightOverlay {
  const _HighlightOverlay({
    required this.start,
    required this.end,
    required this.backgroundColor,
  });

  final int start;
  final int end;
  final Color backgroundColor;
}

List<_HighlightOverlay> _collectDocumentHighlightRangesForLine({
  required List<LspDocumentHighlight> highlights,
  required int lineIndex,
  required int lineLength,
  required ToolTokens tool,
}) {
  final result = <_HighlightOverlay>[];
  for (final highlight in highlights) {
    final range = highlight.range;
    if (lineIndex < range.start.line || lineIndex > range.end.line) continue;

    final start = lineIndex == range.start.line ? range.start.character : 0;
    final end = lineIndex == range.end.line ? range.end.character : lineLength;

    final clampedStart = start.clamp(0, lineLength);
    final clampedEnd = end.clamp(0, lineLength);
    if (clampedStart >= clampedEnd) continue;

    final bg = switch (highlight.kind) {
      3 => tool.colors.focusRing.withOpacity(0.18),
      _ => tool.colors.hover,
    };

    result.add(
      _HighlightOverlay(
        start: clampedStart,
        end: clampedEnd,
        backgroundColor: bg,
      ),
    );
  }

  return result;
}

class _SemanticOverlay {
  const _SemanticOverlay({
    required this.start,
    required this.end,
    required this.fontWeight,
  });

  final int start;
  final int end;
  final FontWeight? fontWeight;
}

List<_SemanticOverlay> _collectSemanticRangesForLine({
  required List<LspSemanticToken> tokens,
  required int lineLength,
}) {
  final result = <_SemanticOverlay>[];
  for (final token in tokens) {
    final start = token.startChar;
    final end = token.startChar + token.length;
    final clampedStart = start.clamp(0, lineLength);
    final clampedEnd = end.clamp(0, lineLength);
    if (clampedStart >= clampedEnd) continue;

    final strong = _semanticTokenIsStrong(token);
    result.add(
      _SemanticOverlay(
        start: clampedStart,
        end: clampedEnd,
        fontWeight: strong ? FontWeight.w600 : null,
      ),
    );
  }
  return result;
}

bool _semanticTokenIsStrong(LspSemanticToken token) {
  final type = token.tokenType;
  if (type == null) return false;
  switch (type) {
    case 'class':
    case 'type':
    case 'function':
    case 'method':
    case 'namespace':
    case 'struct':
    case 'interface':
    case 'enum':
    case 'typeParameter':
      return true;
  }
  // declaration/definition (bitset) is server-specific without legend; keep it conservative.
  return false;
}

_DiagnosticOverlay? _pickMostSevereDiagnostic(
  List<_DiagnosticOverlay> overlays,
  int start,
  int end,
) {
  _DiagnosticOverlay? best;
  for (final overlay in overlays) {
    if (overlay.end <= start || overlay.start >= end) continue;
    if (best == null || overlay.severity < best.severity) {
      best = overlay;
    }
  }
  return best;
}

_HighlightOverlay? _pickHighlight(
  List<_HighlightOverlay> overlays,
  int start,
  int end,
) {
  for (final overlay in overlays) {
    if (overlay.end <= start || overlay.start >= end) continue;
    return overlay;
  }
  return null;
}

_SemanticOverlay? _pickSemantic(
  List<_SemanticOverlay> overlays,
  int start,
  int end,
) {
  for (final overlay in overlays) {
    if (overlay.end <= start || overlay.start >= end) continue;
    return overlay;
  }
  return null;
}
