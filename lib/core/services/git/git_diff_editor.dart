import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/constants/editor_themes.dart';
import 'package:pyrite_ide/core/services/app.dart';
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
    final themeKey = ref.watch(editorThemeKey);
    final entry = findEditorThemeByKey(themeKey) ?? editorThemes.first;
    final brightness = Theme.of(context).brightness;
    final surface = Theme.of(context).scaffoldBackgroundColor;
    final resolvedTheme = applySurfaceBackground(
      resolveEditorTheme(entry, brightness),
      surface,
    );
    final colors = editorSurfaceColors(context, resolvedTheme);
    final fontSize = ref.watch(editorFontSize);
    final fontFamily = editorTextFonts[ref.watch(editorTextFontProvider)];

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
        baseTextStyle: TextStyle(fontSize: fontSize, fontFamily: fontFamily),
        estimatedLineHeight: fontSize * 1.2,
        child: CodeForge(
          key: ValueKey('git-diff_${themeKey}_${brightness.name}'),
          editorTheme: resolvedTheme,
          controller: controller,
          textStyle: TextStyle(fontSize: fontSize, fontFamily: fontFamily),
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
