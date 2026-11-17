import 'package:code_forge/code_forge/code_area.dart';
import 'package:code_forge/code_forge/controller.dart';
import 'package:code_forge/code_forge/find_controller.dart';
import 'package:code_forge/code_forge/styling.dart';
import 'package:code_forge/code_forge/undo_redo.dart';
import 'package:code_forge/code_forge/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/constants/corner_radius.dart';
import 'package:pyrite_ide/core/constants/editor_themes.dart';
import 'package:pyrite_ide/core/constants/selection.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/data_registry.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/features/edit_core/editor_language.dart';
import 'package:pyrite_ide/features/edit_core/editor_minimap.dart';

/// Resolves the active editor theme (built-in or plugin-contributed) the same
/// way every editor surface does, together with the plugin theme's typography
/// overrides. A null typography field keeps the user's editor font settings.
({Map<String, TextStyle> theme, double? fontSize, String? fontFamily, double? lineHeight})
resolveActiveThemeForSurface(BuildContext context, WidgetRef ref) {
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
  return (
    theme: resolvedTheme,
    fontSize: pluginTheme?.editorFontSize,
    fontFamily: pluginTheme?.editorFontFamily,
    lineHeight: pluginTheme?.editorLineHeight,
  );
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

/// Composite key describing every input that feeds the resolved editor
/// surface styles: built-in theme, active plugin theme, resolved plugin
/// styles identity, brightness, surface color, and the color-scheme roles the
/// derived styles pick from.
///
/// It is the cache key for [resolveEditorSurfaceBundle]. A change resolves a
/// fresh bundle which the editors then apply **in place** through
/// `CodeForge.didUpdateWidget` — the editor element is not recreated on a
/// theme switch any more, so the scroll position, undo stack and find state
/// survive.
String activeEditorRebuildKey(BuildContext context, WidgetRef ref) {
  final themeKey = ref.watch(editorThemeKey);
  final brightness = Theme.of(context).brightness;
  final surface = Theme.of(context).scaffoldBackgroundColor;
  final scheme = Theme.of(context).colorScheme;
  final activeThemeId = ref.watch(activePluginThemeId);
  final registry = ref.watch(dataRegistryProvider);
  final pluginTheme = activeThemeId == null
      ? null
      : registry.getThemeById(activeThemeId);
  final editorStyles = pluginTheme?.editorStyles(brightness);
  final pluginEditorThemeActive = pluginTheme?.hasEditorStyles ?? false;
  return '${pluginEditorThemeActive ? '' : themeKey}_${activeThemeId ?? ''}_'
      '${editorStyles}_${brightness.name}_${surface.toARGB32()}_'
      '${pluginTheme?.editorFontSize}_${pluginTheme?.editorFontFamily}_'
      '${pluginTheme?.editorLineHeight}_'
      '${scheme.primary.toARGB32()}_${scheme.error.toARGB32()}_'
      '${scheme.onSurfaceVariant.toARGB32()}';
}

/// Everything [buildThemedCodeForge] derives from the active theme, resolved
/// once and reused while the inputs stay unchanged.
typedef EditorSurfaceBundle =
    ({
      Map<String, TextStyle> theme,
      double fontSize,
      String? fontFamily,
      double? lineHeight,
      HoverDetailsStyle hoverDetailsStyle,
      CodeSelectionStyle selectionStyle,
      MatchHighlightStyle matchHighlightStyle,
      DiagnosticColorsStyle diagnosticColors,
    });

({String key, EditorSurfaceBundle bundle})? _editorSurfaceBundleCache;

/// Resolves the active editor surface theme with identity-stable objects.
///
/// While nothing changed, a rebuild hands the very same style objects to
/// [CodeForge] again, so its `identical` checks in `didUpdateWidget` skip the
/// work; when the theme switches, the fresh bundle flows through the editor's
/// in-place update path instead of a widget recreation.
EditorSurfaceBundle resolveEditorSurfaceBundle(
  BuildContext context,
  WidgetRef ref,
) {
  final scheme = Theme.of(context).colorScheme;
  final fontSizeFallback = ref.watch(editorFontSize);
  final fontFamilySetting = ref.watch(editorTextFontProvider);
  final outerCorners = context.outerCorners;
  final key = '${activeEditorRebuildKey(context, ref)}'
      '_${scheme.primary.toARGB32()}'
      '_${scheme.error.toARGB32()}'
      '_${scheme.onSurfaceVariant.toARGB32()}'
      '_$fontSizeFallback'
      '_$fontFamilySetting'
      '_${outerCorners.topLeft.x}';

  final cached = _editorSurfaceBundleCache;
  if (cached != null && cached.key == key) return cached.bundle;

  final resolved = resolveActiveThemeForSurface(context, ref);
  final resolvedTheme = resolved.theme;
  final colors = editorSurfaceColors(context, resolvedTheme);
  final fontFamily =
      resolved.fontFamily ?? editorTextFonts[fontFamilySetting];
  final bundle = (
    theme: resolvedTheme,
    fontSize: resolved.fontSize ?? fontSizeFallback,
    fontFamily: fontFamily,
    lineHeight: resolved.lineHeight,
    hoverDetailsStyle: buildThemedCodeForgeHoverDetailsStyle(
      foreground: colors.foreground,
      background: colors.background,
      primary: scheme.primary,
      fontSize: resolved.fontSize ?? fontSizeFallback,
      fontFamily: fontFamily,
      borderRadius: outerCorners,
    ),
    selectionStyle: CodeSelectionStyle(
      selectionColor: AppSelection.text(scheme),
    ),
    matchHighlightStyle: MatchHighlightStyle(
      currentMatchStyle: TextStyle(
        backgroundColor: scheme.primary.withAlpha(90),
      ),
      otherMatchStyle: TextStyle(
        backgroundColor: colors.foreground.withAlpha(45),
      ),
    ),
    diagnosticColors: buildDiagnosticColors(context),
  );
  _editorSurfaceBundleCache = (key: key, bundle: bundle);
  return bundle;
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

  /// Outer radius shared by every floating overlay this editor shows:
  /// hover, documentation, signature help, completion and code-action popups.
  ///
  /// Leave null to use the app's unified outer radius. Anything nested inside
  /// one of these overlays is derived by code_forge as
  /// outer - kOverlayPadding, so a nested corner can never grow larger than
  /// the popup that contains it.
  BorderRadius? overlayBorderRadius,

  List<CustomContextMenu>? customContextMenuItems,
  ValueChanged<int>? onModifierTap,
  PreferredSizeWidget Function(BuildContext context, FindController)?
  finderBuilder,
  CodeForgeContextMenuBuilder? contextMenuBuilder,

  /// Host implementations for the engine keys that need grammar or a language
  /// server to act on. The engine declares the shortcut and returns a handled
  /// event, but it has no grammar and no LSP, so without these the key is a
  /// silent no-op.
  VoidCallback? onToggleBlockComment,
  VoidCallback? onFormatDocument,
  VoidCallback? onFindReferences,
  VoidCallback? onGoToImplementation,
}) {
  final bundle = resolveEditorSurfaceBundle(context, ref);
  final resolvedTheme = bundle.theme;
  final colors = editorSurfaceColors(context, resolvedTheme);
  final double fontSize = bundle.fontSize;
  final fontFamily = bundle.fontFamily;
  final lineHeight = bundle.lineHeight;
  // Grammar follows the file's extension. `languageId` is deliberately *not*
  // sourced from here: semantic tokens come from the LSP server, whose language
  // id is configured in LSP settings and already reaches the widget through the
  // controller's `lspConfig`.
  final language = resolveEditorLanguage(filePath);
  // Typing-behavior hints the engine needs per language: Python gets
  // block-end dedent on Enter, and the line comment marker keeps bracket and
  // quote auto-pairing out of comments.
  controller.autoDedentAfterBlockEnd = language.id == 'python';
  final commentMarker = language.lineCommentMarker;
  controller.lineCommentMarkers = commentMarker == null
      ? const <String>[]
      : <String>[commentMarker];
  return MinimapEditorShell(
    controller: controller,
    enabled: ref.watch(editorMinimap),
    lineWrap: ref.watch(editorWordWrap),
    foreground: colors.foreground,
    background: colors.background,
    // The minimap colors its bars from the very theme and grammar the editor
    // runs with, so a bar shows the colors of the code it stands for.
    editorTheme: resolvedTheme,
    language: language.mode,
    baseTextStyle: TextStyle(
      fontSize: fontSize,
      fontFamily: fontFamily,
      height: lineHeight,
    ),
    // Matches the engine default multiplier (fontSize * 1.2) until the
    // renderer publishes the real line height onto the controller.
    estimatedLineHeight: fontSize * (lineHeight ?? 1.2),
    child: CodeForge(
      key: ValueKey(rebuildKey ?? filePath ?? ''),
      filePath: filePath,
      editorTheme: resolvedTheme,
      findController: findController,
      customContextMenuItems: customContextMenuItems,
      onModifierTap: onModifierTap,
      finderBuilder: finderBuilder,
      // The style objects come from the cached bundle, so they are
      // identity-stable while the theme is unchanged: CodeForge compares
      // them with `identical` in didUpdateWidget and updates in place on a
      // real theme switch.
      diagnosticColors: bundle.diagnosticColors,
      hoverDetailsStyle: bundle.hoverDetailsStyle,
      language: language.mode,
      controller: controller,
      undoController: undoController,
      readOnly: readOnly,
      overlayBorderRadius: overlayBorderRadius ?? context.outerCorners,
      matchHighlightStyle: bundle.matchHighlightStyle,
      // The editor paints its own selection, so it cannot inherit the theme's
      // `textSelectionTheme`; it is handed the same app-wide tint explicitly.
      selectionStyle: bundle.selectionStyle,
      textStyle: TextStyle(
        fontSize: fontSize,
        fontFamily: fontFamily,
        height: lineHeight,
      ),
      lineWrap: ref.watch(editorWordWrap),
      enableFolding: ref.watch(editorCodeFolding),
      enableGuideLines: ref.watch(editorGuideLines),
      enableLocalSuggestions: ref.watch(editorLocalSuggestions),
      enableKeyboardSuggestions: ref.watch(editorKeyboardSuggestions),
      enableGutter: ref.watch(editorLineNumber),
      enableGutterDivider: ref.watch(editorGutterDivider),
      smoothCursor: ref.watch(editorSmoothCursor),
      useSpaceAsTab: ref.watch(editorUseSpaceAsTab),
      tabSize: ref.watch(editorTabSize),
      gutterBuilder: GutterBuilder(
        builder: (lineNumber, lineText) => '$lineNumber',
        includeReplacedIndex: false,
      ),
      contextMenuBuilder: contextMenuBuilder,
      onToggleBlockComment: onToggleBlockComment,
      onFormatDocument: onFormatDocument,
      onFindReferences: onFindReferences,
      onGoToImplementation: onGoToImplementation,
    ),
  );
}

/// Squiggle colors derived from the active Material color scheme, so the
/// diagnostic underlines follow the app theme instead of a fixed palette.
///
/// Material's scheme has no dedicated warning role, so the warning color is
/// picked from the amber ramp by brightness; error, information and hint use
/// their nearest scheme roles.
DiagnosticColorsStyle buildDiagnosticColors(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return DiagnosticColorsStyle(
    error: scheme.error,
    warning: isDark ? Colors.amber.shade300 : Colors.amber.shade800,
    information: scheme.primary,
    hint: scheme.onSurfaceVariant,
  );
}
