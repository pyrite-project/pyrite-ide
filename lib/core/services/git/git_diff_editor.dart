import 'package:code_forge/code_forge/controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/git/diff_display.dart';
import 'package:pyrite_ide/core/services/settings.dart';

const _gitDiffAddedColor = Color(0xFF2E7D32);
const _gitDiffDeletedColor = Color(0xFFC62828);

void setGitDiffPatch(CodeForgeController controller, String patch) {
  final display = buildGitDiffDisplay(patch);
  controller
    ..clearGitDiffDecorations()
    ..text = display.text
    ..readOnly = true;
}

class GitDiffEditor extends ConsumerStatefulWidget {
  const GitDiffEditor({
    super.key,
    required this.controller,
    required this.filePath,
  });

  final CodeForgeController controller;
  final String filePath;

  @override
  ConsumerState<GitDiffEditor> createState() => _GitDiffEditorState();
}

class _GitDiffEditorState extends ConsumerState<GitDiffEditor> {
  late final ScrollController _verticalController;
  late final ScrollController _horizontalController;

  @override
  void initState() {
    super.initState();
    _verticalController = ScrollController();
    _horizontalController = ScrollController();
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant GitDiffEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_handleControllerChanged);
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.controller.text.split('\n');
    final wrap = ref.watch(editorWordWrap);
    final fontSize = ref.watch(editorFontSize);
    final fontFamily = editorTextFonts[ref.watch(editorTextFontProvider)];
    final scheme = Theme.of(context).colorScheme;
    final textStyle = TextStyle(
      fontSize: fontSize,
      height: 1.45,
      fontFamily: fontFamily,
      color: scheme.onSurface,
    );
    final lineNumberStyle = textStyle.copyWith(
      color: scheme.onSurfaceVariant.withValues(alpha: 0.72),
    );
    final lineNumberWidth =
        16.0 + (lines.length.toString().length.clamp(2, 5) * fontSize * 0.68);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final longestLineLength = lines.fold<int>(
            0,
            (longest, line) => line.length > longest ? line.length : longest,
          );
          final contentWidth = wrap
              ? constraints.maxWidth
              : (lineNumberWidth + 48 + longestLineLength * fontSize * 0.62)
                    .clamp(constraints.maxWidth, double.infinity)
                    .toDouble();
          final content = ListView.builder(
            controller: _verticalController,
            itemCount: lines.length,
            itemBuilder: (context, index) {
              return _DiffLineRow(
                index: index,
                line: lines[index],
                wrap: wrap,
                minWidth: contentWidth,
                lineNumberWidth: lineNumberWidth,
                textStyle: textStyle,
                lineNumberStyle: lineNumberStyle,
              );
            },
          );

          return Scrollbar(
            controller: _verticalController,
            thumbVisibility: true,
            child: wrap
                ? content
                : Scrollbar(
                    controller: _horizontalController,
                    notificationPredicate: (notification) =>
                        notification.metrics.axis == Axis.horizontal,
                    child: SingleChildScrollView(
                      controller: _horizontalController,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(width: contentWidth, child: content),
                    ),
                  ),
          );
        },
      ),
    );
  }
}

class _DiffLineRow extends StatelessWidget {
  const _DiffLineRow({
    required this.index,
    required this.line,
    required this.wrap,
    required this.minWidth,
    required this.lineNumberWidth,
    required this.textStyle,
    required this.lineNumberStyle,
  });

  final int index;
  final String line;
  final bool wrap;
  final double minWidth;
  final double lineNumberWidth;
  final TextStyle textStyle;
  final TextStyle lineNumberStyle;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = _backgroundColor();
    final sideColor = _sideColor();
    final lineText = Text(
      line.isEmpty ? ' ' : line,
      softWrap: wrap,
      overflow: wrap ? TextOverflow.visible : TextOverflow.clip,
      style: textStyle,
    );

    return ColoredBox(
      color: backgroundColor,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: minWidth),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: lineNumberWidth,
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(8, 2, 8, 2),
                  child: Align(
                    alignment: AlignmentDirectional.topEnd,
                    child: Text('${index + 1}', style: lineNumberStyle),
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(color: sideColor),
                child: const SizedBox(width: 3),
              ),
              const SizedBox(width: 10),
              if (wrap)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(0, 2, 16, 2),
                    child: lineText,
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(0, 2, 16, 2),
                  child: lineText,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _backgroundColor() {
    if (line.startsWith('+')) return _gitDiffAddedColor.withValues(alpha: 0.12);
    if (line.startsWith('-')) {
      return _gitDiffDeletedColor.withValues(alpha: 0.12);
    }
    return Colors.transparent;
  }

  Color _sideColor() {
    if (line.startsWith('+')) return _gitDiffAddedColor;
    if (line.startsWith('-')) return _gitDiffDeletedColor;
    return Colors.transparent;
  }
}
