import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/git/diff_display.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/features/edit_core/editor_language.dart';
import 'package:pyrite_ide/features/edit_core/editor_minimap.dart';
import 'package:pyrite_ide/features/edit_core/themed_code_forge.dart';

const _gitDiffAddedColor = Color(0xFF2E7D32);
const _gitDiffRemovedColor = Color(0xFFC62828);

void setGitDiffPatch(CodeForgeController controller, String patch) {
  final display = buildGitDiffDisplay(patch);
  controller
    ..clearGitDiffDecorations()
    ..text = display.text
    ..readOnly = true;

  // Apply decorations after the text layout is complete to prevent overlap
  WidgetsBinding.instance.addPostFrameCallback((_) {
    controller.setGitDiffDecorations(
      addedRanges: display.addedRanges,
      removedRanges: display.removedRanges,
      addedColor: _gitDiffAddedColor,
      removedColor: _gitDiffRemovedColor,
    );
  });
}

class GitDiffEditor extends ConsumerWidget {
  const GitDiffEditor({
    super.key,
    required this.controller,
    required this.filePath,
  });

  final CodeForgeController controller;
  final String filePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final surface = Theme.of(context).scaffoldBackgroundColor;
    // The diff pane resolves its theme exactly like the main editor, so a
    // plugin theme's token styles and typography apply here too. The cached
    // bundle keeps the style objects identity-stable while the theme is
    // unchanged, which is what lets CodeForge skip its didUpdateWidget work
    // on unrelated rebuilds.
    final bundle = resolveEditorSurfaceBundle(context, ref);
    final resolvedTheme = bundle.theme;
    final colors = editorSurfaceColors(context, resolvedTheme);

    return DecoratedBox(
      decoration: BoxDecoration(color: surface),
      // The diff pane is a text editor like any other, so it wraps its own
      // minimap: the map reads the same read-only buffer the diff shows, and
      // the code area is laid out in the width the column leaves free.
      child: MinimapEditorShell(
        controller: controller,
        enabled: ref.watch(editorMinimap),
        lineWrap: ref.watch(editorWordWrap),
        foreground: colors.foreground,
        background: colors.background,
        editorTheme: resolvedTheme,
        language: resolveEditorLanguage(filePath).mode,
        baseTextStyle: TextStyle(
          fontSize: bundle.fontSize,
          fontFamily: bundle.fontFamily,
          height: bundle.lineHeight,
        ),
        estimatedLineHeight: bundle.fontSize * (bundle.lineHeight ?? 1.2),
        child: CodeForge(
          // The key names the file only: a theme switch updates the editor in
          // place (the diff's scroll position survives) instead of
          // recreating the element.
          key: ValueKey('git-diff_$filePath'),
          editorTheme: resolvedTheme,
          controller: controller,
          textStyle: TextStyle(
            fontSize: bundle.fontSize,
            fontFamily: bundle.fontFamily,
            height: bundle.lineHeight,
          ),
          lineWrap: ref.watch(editorWordWrap),
          useSpaceAsTab: true,
          tabSize: 4,
          gutterBuilder: GutterBuilder(
            builder: (lineNumber, lineText) => '$lineNumber',
            includeReplacedIndex: false,
          ),
        ),
      ),
    );
  }
}
