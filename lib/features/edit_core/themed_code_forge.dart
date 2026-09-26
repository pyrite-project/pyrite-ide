import 'package:code_forge/code_forge/code_area.dart';
import 'package:code_forge/code_forge/controller.dart';
import 'package:code_forge/code_forge/find_controller.dart';
import 'package:code_forge/code_forge/styling.dart';
import 'package:code_forge/code_forge/undo_redo.dart';
import 'package:code_forge/code_forge/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/constants/editor_themes.dart';
import 'package:pyrite_ide/core/services/data_registry.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:re_highlight/languages/python.dart';

/// Resolves the active editor theme (built-in or plugin-contributed) the same
/// way the main editor does, including the de-italicized comment treatment.
Map<String, TextStyle> resolveActiveThemeForSurface(
  BuildContext context,
  WidgetRef ref,
) {
  final themeKey = ref.watch(editorThemeKey);
  final entry = findEditorThemeByKey(themeKey) ?? editorThemes.first;
  final brightness = Theme.of(context).brightness;
  final surface = Theme.of(context).scaffoldBackgroundColor;
  final activeThemeId = ref.watch(activePluginThemeId);
  final registry = ref.watch(dataRegistryProvider);
  final pluginTheme = activeThemeId == null
      ? null
      : registry.getThemeById(activeThemeId);
  final editorStyles = pluginTheme?.editorStyles(brightness);
  final pluginEditorThemeActive = pluginTheme?.hasEditorStyles ?? false;
  final resolvedTheme = applySurfaceBackground(
    resolveActiveEditorTheme(
      entry,
      brightness,
      pluginStyles: editorStyles,
      pluginThemeActive: pluginEditorThemeActive,
    ),
    surface,
  );
  // re_highlight themes render comments in italics; keep each theme's own
  // comment color but drop the italic face instead of overriding the color.
  final commentStyle = resolvedTheme["comment"];
  if (commentStyle != null &&
      commentStyle.fontStyle == FontStyle.italic &&
      !pluginEditorThemeActive) {
    resolvedTheme["comment"] = commentStyle.copyWith(
      fontStyle: FontStyle.normal,
    );
  }
  return resolvedTheme;
}

({Color foreground, Color background}) editorSurfaceColors(
  BuildContext context,
  Map<String, TextStyle> resolvedTheme,
) {
  final surface = Theme.of(context).scaffoldBackgroundColor;
  return (
    foreground:
        resolvedTheme['root']?.color ?? Theme.of(context).colorScheme.onSurface,
    background: resolvedTheme['root']?.backgroundColor ?? surface,
  );
}

/// Builds the hover popup style shared by every themed [CodeForge] instance.
HoverDetailsStyle buildThemedCodeForgeHoverDetailsStyle({
  required Color foreground,
  required Color background,
  required Color primary,
  required double fontSize,
  String? fontFamily,
  BorderRadius? borderRadius,
}) {
  final hoverBackground = Color.alphaBlend(
    foreground.withAlpha(18),
    background,
  ).withAlpha(255);
  return HoverDetailsStyle(
    shape: RoundedRectangleBorder(
      borderRadius: borderRadius ?? CodeForge.defaultHoverDetailsBorderRadius,
      side: BorderSide(color: foreground.withAlpha(80)),
    ),
    backgroundColor: hoverBackground,
    focusColor: primary.withAlpha(50),
    hoverColor: primary.withAlpha(25),
    splashColor: primary.withAlpha(50),
    textStyle: TextStyle(
      color: foreground,
      fontSize: fontSize,
      fontFamily: fontFamily,
    ),
  );
}

/// Composite key describing every input that requires rebuilding the
/// [CodeForge] element when it changes: built-in theme, active plugin theme,
/// resolved plugin styles identity, brightness, and surface color.
///
/// Pass it as [buildThemedCodeForge]'s `rebuildKey` so theme switches recreate
/// the editor exactly like before the shared builder was extracted.
String activeEditorRebuildKey(BuildContext context, WidgetRef ref) {
  final themeKey = ref.watch(editorThemeKey);
  final brightness = Theme.of(context).brightness;
  final surface = Theme.of(context).scaffoldBackgroundColor;
  final activeThemeId = ref.watch(activePluginThemeId);
  final registry = ref.watch(dataRegistryProvider);
  final pluginTheme = activeThemeId == null
      ? null
      : registry.getThemeById(activeThemeId);
  final editorStyles = pluginTheme?.editorStyles(brightness);
  final pluginEditorThemeActive = pluginTheme?.hasEditorStyles ?? false;
  return '${pluginEditorThemeActive ? '' : themeKey}_${activeThemeId ?? ''}_'
      '${editorStyles}_${brightness.name}_${surface.toARGB32()}';
}

/// Builds a [CodeForge] wired exactly like the main editor: same theme
/// resolution, fonts, and display settings from the settings providers.
///
/// Used both by the main editor and by read-only preview panes so any
/// embedded editor view is visually identical to the real editor. LSP is only
/// active when the controller was created with an LSP config; preview
/// controllers created without one stay fully offline.
Widget buildThemedCodeForge(
  BuildContext context,
  WidgetRef ref, {
  required CodeForgeController controller,
  String? filePath,
  String? rebuildKey,
  UndoRedoController? undoController,
  FindController? findController,
  bool readOnly = false,

  /// Radius for the inner fenced Markdown code blocks shown in LSP popups.
  /// Leave null to use [CodeForge.defaultMarkdownCodeBlockBorderRadius].
  BorderRadius? markdownCodeBlockBorderRadius,

  /// Outer radius for LSP hover and documentation popups.
  ///
  /// Leave null to use [CodeForge.defaultHoverDetailsBorderRadius].
  BorderRadius? hoverDetailsBorderRadius,
  List<CustomContextMenu>? customContextMenuItems,
  ValueChanged<int>? onModifierTap,
  PreferredSizeWidget Function(BuildContext context, FindController)?
  finderBuilder,
  CodeForgeContextMenuBuilder? contextMenuBuilder,
}) {
  final resolvedTheme = resolveActiveThemeForSurface(context, ref);
  final colors = editorSurfaceColors(context, resolvedTheme);
  final fontSize = ref.watch(editorFontSize);
  final fontFamily = editorTextFonts[ref.watch(editorTextFontProvider)];
  final primary = Theme.of(context).colorScheme.primary;
  return CodeForge(
    key: ValueKey(rebuildKey ?? filePath ?? ''),
    filePath: filePath,
    editorTheme: resolvedTheme,
    findController: findController,
    customContextMenuItems: customContextMenuItems,
    onModifierTap: onModifierTap,
    finderBuilder: finderBuilder,
    hoverDetailsStyle: buildThemedCodeForgeHoverDetailsStyle(
      foreground: colors.foreground,
      background: colors.background,
      primary: primary,
      fontSize: fontSize,
      fontFamily: fontFamily,
      borderRadius: hoverDetailsBorderRadius,
    ),
    language: langPython,
    controller: controller,
    undoController: undoController,
    readOnly: readOnly,
    markdownCodeBlockBorderRadius:
        markdownCodeBlockBorderRadius ??
        CodeForge.defaultMarkdownCodeBlockBorderRadius,
    matchHighlightStyle: const MatchHighlightStyle(
      currentMatchStyle: TextStyle(backgroundColor: Color(0xFFFFA726)),
      otherMatchStyle: TextStyle(backgroundColor: Color(0x55FFFF00)),
    ),
    textStyle: TextStyle(fontSize: fontSize, fontFamily: fontFamily),
    lineWrap: ref.watch(editorWordWrap),
    enableFolding: ref.watch(editorCodeFolding),
    enableGuideLines: ref.watch(editorGuideLines),
    enableLocalSuggestions: ref.watch(editorLocalSuggestions),
    enableKeyboardSuggestions: ref.watch(editorKeyboardSuggestions),
    enableGutter: ref.watch(editorLineNumber),
    enableGutterDivider: ref.watch(editorGutterDivider),
    useSpaceAsTab: ref.watch(editorUseSpaceAsTab),
    tabSize: ref.watch(editorTabSize),
    gutterBuilder: GutterBuilder(
      builder: (lineNumber, lineText) => '$lineNumber',
      includeReplacedIndex: false,
    ),
    contextMenuBuilder: contextMenuBuilder,
  );
}
