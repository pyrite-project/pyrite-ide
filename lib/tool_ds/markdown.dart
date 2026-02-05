import 'package:flutter/material.dart';
import 'package:pyrite_ide/tool_ds/scope.dart';

class ToolMarkdown extends StatelessWidget {
  const ToolMarkdown(
    this.markdown, {
    super.key,
    this.maxCodeBlockHeight,
  });

  final String markdown;
  final double? maxCodeBlockHeight;

  @override
  Widget build(BuildContext context) {
    final tool = context.tool;
    final blocks = _parseMarkdownBlocks(markdown);

    final children = <Widget>[];
    for (final block in blocks) {
      switch (block) {
        case _MdCodeBlock():
          children.add(
            _ToolCodeBlock(
              language: block.language,
              code: block.code,
              maxHeight: maxCodeBlockHeight,
            ),
          );
        case _MdTextBlock():
          final built = _buildTextBlock(context, block.text);
          if (built.isNotEmpty) {
            children.addAll(built);
          }
      }
      children.add(SizedBox(height: tool.space.xs));
    }

    if (children.isNotEmpty) {
      children.removeLast();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

sealed class _MdBlock {
  const _MdBlock();
}

class _MdCodeBlock extends _MdBlock {
  const _MdCodeBlock({required this.code, this.language});

  final String code;
  final String? language;
}

class _MdTextBlock extends _MdBlock {
  const _MdTextBlock({required this.text});

  final String text;
}

List<_MdBlock> _parseMarkdownBlocks(String source) {
  final normalized = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = normalized.split('\n');

  final blocks = <_MdBlock>[];
  final textBuffer = <String>[];

  void flushText() {
    if (textBuffer.isEmpty) return;
    final text = textBuffer.join('\n');
    textBuffer.clear();
    if (text.trim().isEmpty) return;
    blocks.add(_MdTextBlock(text: text));
  }

  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    final trimmedLeft = line.trimLeft();
    if (trimmedLeft.startsWith('```')) {
      flushText();

      final language = trimmedLeft.substring(3).trim();
      i++;

      final codeLines = <String>[];
      while (i < lines.length) {
        final candidate = lines[i];
        if (candidate.trimLeft().startsWith('```')) {
          i++;
          break;
        }
        codeLines.add(candidate);
        i++;
      }

      blocks.add(
        _MdCodeBlock(
          code: codeLines.join('\n').trimRight(),
          language: language.isEmpty ? null : language,
        ),
      );
      continue;
    }

    textBuffer.add(line);
    i++;
  }

  flushText();
  return blocks;
}

List<Widget> _buildTextBlock(BuildContext context, String text) {
  final tool = context.tool;
  final lines = text.split('\n');

  final children = <Widget>[];
  final paragraphLines = <String>[];

  void flushParagraph() {
    if (paragraphLines.isEmpty) return;
    final paragraph = paragraphLines.join('\n').trimRight();
    paragraphLines.clear();
    if (paragraph.isEmpty) return;
    children.add(
      SelectableText.rich(
        TextSpan(
          children: _inlineMarkdownSpans(context, paragraph),
        ),
        style: tool.type.uiDense.copyWith(color: tool.colors.text),
      ),
    );
  }

  for (final rawLine in lines) {
    final line = rawLine.trimRight();
    final trimmedLeft = line.trimLeft();

    if (trimmedLeft.isEmpty) {
      flushParagraph();
      children.add(SizedBox(height: tool.space.xs));
      continue;
    }

    final headingLevel = _headingLevel(trimmedLeft);
    if (headingLevel > 0) {
      flushParagraph();
      final headingText = trimmedLeft.substring(headingLevel).trim();
      if (headingText.isNotEmpty) {
        children.add(
          SelectableText(
            headingText,
            style: tool.type.ui.copyWith(
              color: tool.colors.text,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }
      continue;
    }

    final listItem = _parseListItem(trimmedLeft);
    if (listItem != null) {
      flushParagraph();
      children.add(
        _ToolListItem(
          marker: listItem.marker,
          text: listItem.text,
        ),
      );
      continue;
    }

    final quote = _parseQuote(trimmedLeft);
    if (quote != null) {
      flushParagraph();
      children.add(_ToolQuote(text: quote));
      continue;
    }

    paragraphLines.add(line);
  }

  flushParagraph();
  return children;
}

int _headingLevel(String line) {
  var level = 0;
  while (level < line.length &&
      level < 6 &&
      line.codeUnitAt(level) == 35 /* # */) {
    level++;
  }
  if (level == 0) return 0;
  if (line.length > level && line.codeUnitAt(level) == 32 /* space */) {
    return level;
  }
  return 0;
}

({String marker, String text})? _parseListItem(String line) {
  if (line.startsWith('- ')) return (marker: '•', text: line.substring(2));
  if (line.startsWith('* ')) return (marker: '•', text: line.substring(2));
  if (line.startsWith('+ ')) return (marker: '•', text: line.substring(2));

  final match = RegExp(r'^(\d+)\.\s+(.*)$').firstMatch(line);
  if (match == null) return null;
  return (marker: '${match.group(1)}.', text: match.group(2) ?? '');
}

String? _parseQuote(String line) {
  if (!line.startsWith('>')) return null;
  final trimmed = line.substring(1);
  if (trimmed.startsWith(' ')) return trimmed.substring(1);
  return trimmed;
}

List<InlineSpan> _inlineMarkdownSpans(BuildContext context, String text) {
  final tool = context.tool;
  final normalStyle = tool.type.uiDense.copyWith(color: tool.colors.text);
  final codeStyle = tool.type.monoDense.copyWith(
    color: tool.colors.text,
    backgroundColor: tool.colors.hover,
  );
  final linkStyle = normalStyle.copyWith(
    color: tool.colors.accent,
    decoration: TextDecoration.underline,
    decorationColor: tool.colors.accent.withAlpha(180),
  );

  final spans = <InlineSpan>[];
  var inCode = false;
  var segmentStart = 0;

  void pushPlain(String segment) {
    if (segment.isEmpty) return;
    spans.addAll(_inlineLinks(segment, normalStyle, linkStyle));
  }

  for (var i = 0; i < text.length; i++) {
    final codeUnit = text.codeUnitAt(i);
    if (codeUnit != 96 /* ` */) continue;

    final segment = text.substring(segmentStart, i);
    if (inCode) {
      spans.add(TextSpan(text: segment, style: codeStyle));
      inCode = false;
    } else {
      pushPlain(segment);
      inCode = true;
    }
    segmentStart = i + 1;
  }

  final tail = text.substring(segmentStart);
  if (inCode) {
    spans.add(TextSpan(text: tail, style: codeStyle));
  } else {
    pushPlain(tail);
  }

  return spans;
}

List<InlineSpan> _inlineLinks(
  String text,
  TextStyle normalStyle,
  TextStyle linkStyle,
) {
  final spans = <InlineSpan>[];
  final regex = RegExp(r'\[([^\]]+)\]\(([^)]+)\)');

  var cursor = 0;
  for (final match in regex.allMatches(text)) {
    if (match.start > cursor) {
      spans.add(
        TextSpan(text: text.substring(cursor, match.start), style: normalStyle),
      );
    }
    final label = match.group(1) ?? '';
    if (label.isNotEmpty) {
      spans.add(TextSpan(text: label, style: linkStyle));
    }
    cursor = match.end;
  }

  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor), style: normalStyle));
  }

  return spans;
}

class _ToolCodeBlock extends StatelessWidget {
  const _ToolCodeBlock({
    required this.code,
    this.language,
    this.maxHeight,
  });

  final String code;
  final String? language;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    final tool = context.tool;

    final header = language == null || language!.isEmpty
        ? null
        : Padding(
            padding: EdgeInsets.only(bottom: tool.space.xs),
            child: Text(
              language!,
              style: tool.type.uiDense.copyWith(
                color: tool.colors.textFaint,
              ),
            ),
          );

    final codeText = SelectableText(
      code,
      style: tool.type.monoDense.copyWith(color: tool.colors.textMuted),
    );

    final scroll = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: codeText,
    );

    final body = maxHeight == null
        ? scroll
        : ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight!),
            child: SingleChildScrollView(child: scroll),
          );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tool.colors.canvas,
        border: Border.all(color: tool.colors.border, width: 1),
        borderRadius: BorderRadius.circular(tool.radii.sm),
      ),
      child: Padding(
        padding: EdgeInsets.all(tool.space.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (header != null) header,
            body,
          ],
        ),
      ),
    );
  }
}

class _ToolListItem extends StatelessWidget {
  const _ToolListItem({
    required this.marker,
    required this.text,
  });

  final String marker;
  final String text;

  @override
  Widget build(BuildContext context) {
    final tool = context.tool;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 18,
          child: Text(
            marker,
            style: tool.type.uiDense.copyWith(color: tool.colors.textFaint),
          ),
        ),
        Expanded(
          child: SelectableText.rich(
            TextSpan(children: _inlineMarkdownSpans(context, text)),
            style: tool.type.uiDense.copyWith(color: tool.colors.text),
          ),
        ),
      ],
    );
  }
}

class _ToolQuote extends StatelessWidget {
  const _ToolQuote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final tool = context.tool;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: tool.colors.border, width: 2),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(left: tool.space.sm),
        child: SelectableText.rich(
          TextSpan(children: _inlineMarkdownSpans(context, text)),
          style: tool.type.uiDense.copyWith(
            color: tool.colors.textMuted,
          ),
        ),
      ),
    );
  }
}
