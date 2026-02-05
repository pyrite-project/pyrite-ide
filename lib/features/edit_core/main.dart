import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/pylsp/data.dart';
import 'package:pyrite_ide/core/services/pylsp/features.dart';
import 'package:pyrite_ide/core/services/pylsp/main.dart';
import 'package:pyrite_ide/core/services/pylsp/hover.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';
import 'package:pyrite_ide/tool_ds/tool_ds.dart';
import 'package:pyrite_ide/features/edit_core/lsp_completion.dart';

class EditCore extends ConsumerStatefulWidget {
  const EditCore({
    super.key,
    required this.file,
    required this.editorController,
  });
  final File file;
  final CodeLineEditingController editorController;

  @override
  ConsumerState<EditCore> createState() => _EditCoreState();
}

class _EditCoreState extends ConsumerState<EditCore> {
  Timer? _semanticTokensTimer;
  Timer? _documentHighlightsTimer;
  Timer? _hoverTimer;

  CodeLineSelection? _lastSelection;
  CodeLines? _lastCodeLines;
  late String _uri;
  int _semanticEpoch = 0;
  int _highlightEpoch = 0;

  final GlobalKey _indicatorKey = GlobalKey();
  ValueNotifier<CodeIndicatorValue?>? _indicatorNotifier;
  OverlayEntry? _hoverOverlay;
  CodeLineRange? _hoverWord;
  String? _hoverText;
  String? _hoverKind;
  Offset _hoverGlobalPos = Offset.zero;
  int _hoverEpoch = 0;

  @override
  void dispose() {
    _semanticTokensTimer?.cancel();
    _documentHighlightsTimer?.cancel();
    _hoverTimer?.cancel();
    _removeHoverOverlay();
    widget.editorController.removeListener(_onEditorChanged);
    super.dispose();
  }

  void _onEditorChanged() {
    final selection = widget.editorController.selection;
    final codeLines = widget.editorController.codeLines;

    if (_lastSelection != selection) {
      _lastSelection = selection;
      _scheduleDocumentHighlightsFetch();
    }
    if (_lastCodeLines != codeLines &&
        !(_lastCodeLines?.equals(codeLines) ?? false)) {
      _lastCodeLines = codeLines;
      _scheduleSemanticTokensFetch();
    }
  }

  void _scheduleSemanticTokensFetch() {
    _semanticTokensTimer?.cancel();
    final epoch = ++_semanticEpoch;
    _semanticTokensTimer = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted || epoch != _semanticEpoch) return;
      final client = await PythonLspService(ref).maybeClient;
      if (!mounted || epoch != _semanticEpoch || client == null) return;
      await fetchSemanticTokens(client: client, uri: _uri);
      if (mounted && epoch == _semanticEpoch) {
        widget.editorController.forceRepaint();
      }
    });
  }

  void _scheduleDocumentHighlightsFetch() {
    _documentHighlightsTimer?.cancel();
    final epoch = ++_highlightEpoch;
    _documentHighlightsTimer = Timer(
      const Duration(milliseconds: 120),
      () async {
        if (!mounted || epoch != _highlightEpoch) return;

        final selection = widget.editorController.selection;
        if (!selection.isCollapsed) {
          setDocumentHighlights(_uri, const []);
          return;
        }

        final client = await PythonLspService(ref).maybeClient;
        if (!mounted || epoch != _highlightEpoch || client == null) return;

        await fetchDocumentHighlights(
          client: client,
          uri: _uri,
          line: selection.extentIndex,
          character: selection.extentOffset,
        );
        if (mounted && epoch == _highlightEpoch) {
          widget.editorController.forceRepaint();
        }
      },
    );
  }

  void _onPointerHover(PointerHoverEvent event) {
    final indicatorWidth = _indicatorKey.currentContext?.size?.width ?? 0;
    if (indicatorWidth <= 0) {
      _clearHoverTarget();
      return;
    }

    final codeDx = event.localPosition.dx - indicatorWidth;
    if (codeDx < 0) {
      _clearHoverTarget();
      return;
    }

    final indicatorValue = _indicatorNotifier?.value;
    final paragraphs = indicatorValue?.paragraphs;
    if (paragraphs == null || paragraphs.isEmpty) {
      _clearHoverTarget();
      return;
    }

    final codeOffset = Offset(codeDx, event.localPosition.dy);
    final paragraph = paragraphs.cast<CodeLineRenderParagraph?>().firstWhere(
      (p) => p != null && codeOffset.dy >= p.top && codeOffset.dy < p.bottom,
      orElse: () => null,
    );

    if (paragraph == null) {
      _clearHoverTarget();
      return;
    }

    final relative = codeOffset - paragraph.offset;
    final word = paragraph.getWord(relative);
    if (word.start < 0 || word.end <= word.start) {
      _clearHoverTarget();
      return;
    }

    _hoverGlobalPos = event.position + const Offset(12, 12);

    if (_hoverWord == word) {
      _hoverOverlay?.markNeedsBuild();
      return;
    }

    _hoverWord = word;
    _hoverText = null;
    _hoverKind = null;
    _removeHoverOverlay();

    final pos = paragraph.getPosition(relative);
    _scheduleHoverFetch(pos);
  }

  void _onPointerExit(PointerExitEvent event) {
    _clearHoverTarget();
  }

  void _clearHoverTarget() {
    _hoverWord = null;
    _hoverText = null;
    _hoverKind = null;
    _hoverTimer?.cancel();
    _removeHoverOverlay();
  }

  void _scheduleHoverFetch(CodeLinePosition position) {
    _hoverTimer?.cancel();
    final epoch = ++_hoverEpoch;
    _hoverTimer = Timer(const Duration(milliseconds: 280), () async {
      if (!mounted || epoch != _hoverEpoch) return;
      final client = await PythonLspService(ref).maybeClient;
      if (!mounted || epoch != _hoverEpoch || client == null) return;

      LspHoverContent? content;
      try {
        content = await fetchHover(
          client: client,
          uri: _uri,
          line: position.index,
          character: position.offset,
        );
      } catch (_) {
        content = null;
      }

      if (!mounted || epoch != _hoverEpoch) return;
      if (_hoverWord == null || content == null) {
        _removeHoverOverlay();
        return;
      }

      _hoverText = content.text.trimRight();
      _hoverKind = content.kind;
      _ensureHoverOverlay();
    });
  }

  void _ensureHoverOverlay() {
    if (_hoverText == null || _hoverText!.trim().isEmpty) {
      _removeHoverOverlay();
      return;
    }

    final overlay = Overlay.of(context, rootOverlay: true);

    if (_hoverOverlay == null) {
      _hoverOverlay = OverlayEntry(
        builder: (context) => _HoverTooltip(
          globalPosition: _hoverGlobalPos,
          text: _hoverText!,
          kind: _hoverKind,
        ),
      );
      overlay.insert(_hoverOverlay!);
    } else {
      _hoverOverlay!.markNeedsBuild();
    }
  }

  void _removeHoverOverlay() {
    _hoverOverlay?.remove();
    _hoverOverlay = null;
  }

  @override
  Widget build(BuildContext context) {
    _uri = Uri.file(widget.file.path).toString();
    _lastSelection = widget.editorController.selection;
    _lastCodeLines = widget.editorController.codeLines;

    widget.editorController.addListener(_onEditorChanged);

    ref.listen(diagnosticsByUri, (previous, next) {
      if (!mounted) return;
      if (previous?[_uri] != next[_uri]) {
        widget.editorController.forceRepaint();
      }
    });
    ref.listen(documentHighlightsByUri, (previous, next) {
      if (!mounted) return;
      if (previous?[_uri] != next[_uri]) {
        widget.editorController.forceRepaint();
      }
    });
    ref.listen(semanticTokensByUri, (previous, next) {
      if (!mounted) return;
      if (previous?[_uri] != next[_uri]) {
        widget.editorController.forceRepaint();
      }
    });

    // Kick an initial semantic token request after first layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduleSemanticTokensFetch();
      _scheduleDocumentHighlightsFetch();
    });
    final tool = context.tool;
    final syntaxTheme = Theme.of(context).brightness == Brightness.dark
        ? atomOneDarkTheme
        : atomOneLightTheme;

    return CodeAutocomplete(
      viewBuilder: (context, notifier, onSelected) {
        return LspAutocompleteListView(
          notifier: notifier,
          onSelected: onSelected,
          uri: _uri,
          editorController: widget.editorController,
        );
      },
      promptsBuilder: const LspCompletionPromptsBuilder(),
      child: MouseRegion(
        onHover: _onPointerHover,
        onExit: _onPointerExit,
        child: CodeEditor(
          indicatorBuilder:
              (context, editingController, chunkController, notifier) {
                _indicatorNotifier = notifier;
                return Row(
                  key: _indicatorKey,
                  children: buildIndicator(
                    context,
                    editingController,
                    chunkController,
                    notifier,
                    ref,
                  ),
                );
              },
          controller: widget.editorController,
          style: CodeEditorStyle(
            codeTheme: CodeHighlightTheme(
              languages: {
                'micropython': CodeHighlightThemeMode(mode: langPython),
              },
              theme: syntaxTheme,
            ),
            fontSize: ref.watch(editorFontSize),
            fontFamily: editorTextFonts[ref.watch(editorTextFontProvider)],
          ),
          wordWrap: ref.watch(editorWordWrap),
        ),
      ),
    );
  }

  List<Widget> buildIndicator(
    BuildContext context,
    CodeLineEditingController editingController,
    CodeChunkController chunkController,
    ValueNotifier<CodeIndicatorValue?> notifier,
    WidgetRef ref,
  ) {
    List<Widget> children = [];
    if (ref.watch(editorLineNumber)) {
      children.add(
        DefaultCodeLineNumber(
          controller: editingController,
          notifier: notifier,
        ),
      );
    }
    children.add(
      DefaultCodeChunkIndicator(
        width: 20,
        controller: chunkController,
        notifier: notifier,
      ),
    );
    return children;
  }
}

class _HoverTooltip extends StatelessWidget {
  const _HoverTooltip({
    required this.globalPosition,
    required this.text,
    this.kind,
  });

  final Offset globalPosition;
  final String text;
  final String? kind;

  static const double _maxWidth = 460;
  static const double _maxHeight = 280;

  @override
  Widget build(BuildContext context) {
    final tool = context.tool;
    final screen = MediaQuery.of(context).size;
    final margin = tool.space.sm;

    final left = globalPosition.dx.clamp(
      margin,
      (screen.width - _maxWidth - margin).clamp(margin, screen.width),
    );
    final top = globalPosition.dy.clamp(
      margin,
      (screen.height - _maxHeight - margin).clamp(margin, screen.height),
    );

    return Positioned(
      left: left,
      top: top,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: _maxWidth,
          maxHeight: _maxHeight,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tool.colors.panel,
            border: Border.all(color: tool.colors.border, width: 1),
            borderRadius: BorderRadius.circular(tool.radii.md),
          ),
          child: Padding(
            padding: EdgeInsets.all(tool.space.sm),
            child: DefaultTextStyle(
              style: tool.type.uiDense.copyWith(color: tool.colors.text),
              child: SingleChildScrollView(child: SelectableText(text)),
            ),
          ),
        ),
      ),
    );
  }
}
