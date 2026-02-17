import 'package:flutter/material.dart';

class ToolMarkdown extends StatelessWidget {
  const ToolMarkdown(this.markdown, {super.key, this.maxCodeBlockHeight});

  final String markdown;
  final double? maxCodeBlockHeight;

  @override
  Widget build(BuildContext context) {
    final blocks = _parseMarkdownBlocks(markdown);

    final children = <Widget>[];
    for (final block in blocks) {
      switch (block) {
        case _MdCodeBlock():
          children.add(_ToolCodeBlock(code: block.code));
        case _MdTextBlock():
          final built = _buildTextBlock(context, block.text);
          if (built.isNotEmpty) {
            children.addAll(built);
          }
      }
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
  final lines = text.split('\n');

  final children = <Widget>[];
  final paragraphLines = <String>[];

  void flushParagraph() {
    if (paragraphLines.isEmpty) return;
    final paragraph = paragraphLines.join('\n').trimRight();
    paragraphLines.clear();
    if (paragraph.isEmpty) return;
    children.add(
      Text.rich(
        TextSpan(
          children: _inlineMarkdownSpans(context, paragraph),
          style: TextStyle(fontSize: 15, height: 1.1),
        ),
      ),
    );
  }

  for (final rawLine in lines) {
    final line = rawLine.trimRight();
    final trimmedLeft = line.trimLeft();

    if (trimmedLeft.isEmpty) {
      flushParagraph();
      children.add(SizedBox(height: 5));
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
            style: TextStyle(
              fontSize: 15,
              height: 1.1,
              color: Theme.of(context).colorScheme.onSurface,
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
      children.add(_ToolListItem(marker: listItem.marker, text: listItem.text));
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
      line.codeUnitAt(level) == 35 /* # */ ) {
    level++;
  }
  if (level == 0) return 0;
  if (line.length > level && line.codeUnitAt(level) == 32 /* space */ ) {
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
  final normalStyle = TextStyle(
    fontSize: 15,
    height: 1.1,
    color: Theme.of(context).colorScheme.onSurface,
  );
  final codeStyle = TextStyle(
    fontSize: 15.5,
    height: 1.15,
    fontFamily: "JetBrainsMono",
    fontFeatures: const [FontFeature.tabularFigures()],
    color: Theme.of(context).colorScheme.onSurface,
  );
  final linkStyle = normalStyle.copyWith(
    color: Color(0xFF2B5BD7),
    decoration: TextDecoration.underline,
    decorationColor: Color(0xFF2B5BD7).withAlpha(180),
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
    if (codeUnit != 96 /* ` */ ) continue;

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
  const _ToolCodeBlock({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final codeText = Text(
      code,
      style: TextStyle(
        fontSize: 15,
        height: 1.1,
        fontFamily: "JetBrainsMono",
        fontFeatures: const [FontFeature.tabularFigures()],
        color: Theme.of(context).colorScheme.onPrimaryContainer,
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        border: Border.all(
          color: Theme.of(context).colorScheme.outline,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Padding(
        padding: EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [codeText],
        ),
      ),
    );
  }
}

class _ToolListItem extends StatelessWidget {
  const _ToolListItem({required this.marker, required this.text});

  final String marker;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 18,
          child: Text(
            marker,
            style: TextStyle(
              fontSize: 15,
              height: 1.1,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        Expanded(
          child: SelectableText.rich(
            TextSpan(
              children: _inlineMarkdownSpans(context, text),
              style: TextStyle(
                fontSize: 15,
                height: 1.1,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: Theme.of(context).colorScheme.outline,
            width: 2,
          ),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(left: 2),
        child: SelectableText.rich(
          TextSpan(children: _inlineMarkdownSpans(context, text)),
          style: TextStyle(
            fontSize: 15,
            height: 1.1,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
