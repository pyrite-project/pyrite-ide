import 'package:flutter/material.dart';
import 'package:re_highlight/styles/androidstudio.dart';
import 'package:re_highlight/styles/atom-one-dark-reasonable.dart';
import 'package:re_highlight/styles/atom-one-light.dart';
import 'package:re_highlight/styles/foundation.dart';
import 'package:re_highlight/styles/github-dark.dart';
import 'package:re_highlight/styles/github.dart';
import 'package:re_highlight/styles/intellij-light.dart';
import 'package:re_highlight/styles/kimbie-dark.dart';
import 'package:re_highlight/styles/kimbie-light.dart';
import 'package:re_highlight/styles/monokai-sublime.dart';
import 'package:re_highlight/styles/night-owl.dart';
import 'package:re_highlight/styles/nord.dart';
import 'package:re_highlight/styles/panda-syntax-light.dart';
import 'package:re_highlight/styles/paraiso-dark.dart';
import 'package:re_highlight/styles/paraiso-light.dart';
import 'package:re_highlight/styles/qtcreator-dark.dart';
import 'package:re_highlight/styles/qtcreator-light.dart';
import 'package:re_highlight/styles/stackoverflow-dark.dart';
import 'package:re_highlight/styles/stackoverflow-light.dart';
import 'package:re_highlight/styles/tokyo-night-dark.dart';
import 'package:re_highlight/styles/tokyo-night-light.dart';
import 'package:re_highlight/styles/vs.dart';
import 'package:re_highlight/styles/vs2015.dart';
import 'package:re_highlight/styles/xcode.dart';

class EditorThemeEntry {
  final String label;
  final String key;
  final Map<String, TextStyle> light;
  final Map<String, TextStyle> dark;

  const EditorThemeEntry({
    required this.label,
    required this.key,
    required this.light,
    required this.dark,
  });
}

final List<EditorThemeEntry> editorThemes = [
  EditorThemeEntry(
    label: "Atom One",
    key: "atom-one",
    light: atomOneLightTheme,
    dark: atomOneDarkReasonableTheme,
  ),
  EditorThemeEntry(label: "VS", key: "vs", light: vsTheme, dark: vs2015Theme),
  EditorThemeEntry(
    label: "GitHub",
    key: "github",
    light: githubTheme,
    dark: githubDarkTheme,
  ),
  EditorThemeEntry(
    label: "IntelliJ",
    key: "intellij",
    light: intellijLightTheme,
    dark: androidstudioTheme,
  ),
  EditorThemeEntry(
    label: "Monokai",
    key: "monokai",
    light: pandaSyntaxLightTheme,
    dark: monokaiSublimeTheme,
  ),
  EditorThemeEntry(
    label: "Nord",
    key: "nord",
    light: nordTheme,
    dark: nordTheme,
  ),
  EditorThemeEntry(
    label: "Solarized",
    key: "solarized",
    light: paraisoLightTheme,
    dark: paraisoDarkTheme,
  ),
  EditorThemeEntry(
    label: "Tokyo Night",
    key: "tokyo-night",
    light: tokyoNightLightTheme,
    dark: tokyoNightDarkTheme,
  ),
  EditorThemeEntry(
    label: "Night Owl",
    key: "night-owl",
    light: nightOwlTheme,
    dark: nightOwlTheme,
  ),
  EditorThemeEntry(
    label: "Kimbie",
    key: "kimbie",
    light: kimbieLightTheme,
    dark: kimbieDarkTheme,
  ),
  EditorThemeEntry(
    label: "Foundation",
    key: "foundation",
    light: foundationTheme,
    dark: foundationTheme,
  ),
  EditorThemeEntry(
    label: "Xcode",
    key: "xcode",
    light: xcodeTheme,
    dark: xcodeTheme,
  ),
  EditorThemeEntry(
    label: "Stackoverflow",
    key: "stackoverflow",
    light: stackoverflowLightTheme,
    dark: stackoverflowDarkTheme,
  ),
  EditorThemeEntry(
    label: "Qt Creator",
    key: "qtcreator",
    light: qtcreatorLightTheme,
    dark: qtcreatorDarkTheme,
  ),
];

Map<String, TextStyle> resolveEditorTheme(
  EditorThemeEntry entry,
  Brightness brightness,
) {
  final theme = brightness == Brightness.light ? entry.light : entry.dark;
  // re_highlight themes italicize comments in most of their theme files; the
  // IDE keeps each theme's comment color but draws comments upright. Plugin
  // styles merge on top of this base, so a plugin can still ask for an
  // italic comment explicitly.
  final comment = theme['comment'];
  final normalized = comment != null && comment.fontStyle == FontStyle.italic
      ? (Map<String, TextStyle>.from(theme)
          ..['comment'] = comment.copyWith(fontStyle: FontStyle.normal))
      : theme;
  return _normalizeEditorTheme(normalized);
}

/// Runtime scope names that re_highlight languages emit but which theme files
/// key under a highlight.js-style alias (or omit entirely). Each entry lists
/// the theme keys to try, in order, when the scope name itself is missing.
///
/// Without this, tokens like `title.function` or `variable.language` fall
/// through every built-in theme and render unstyled; with it, a theme only
/// needs one key set and a plugin may use either naming.
const Map<String, List<String>> _editorScopeFallbacks = {
  'title.function': [
    'title.function_',
    'function-title',
    'title.hljs-function',
    'function',
    'title',
  ],
  'title.class': ['title.class_', 'class-title', 'class', 'title'],
  'function': ['title.function_', 'function-title', 'title'],
  'class': ['title.class_', 'class-title', 'title'],
  'variable.language': ['variable.language_', 'built_in', 'variable'],
  'variable.constant': ['literal', 'variable'],
  'char.escape': ['char.escape_', 'string'],
  'character': ['char.escape_', 'string'],
  'computation-expression': ['subst', 'meta'],
  'regex': ['regexp'],
  'params': ['function-params'],
};

/// Fills every runtime scope that is missing a style from its first available
/// alias key. Keys that already exist (including plugin-contributed ones)
/// always win; the fallback never overwrites an explicit style.
Map<String, TextStyle> _normalizeEditorTheme(Map<String, TextStyle> theme) {
  final result = Map<String, TextStyle>.from(theme);
  for (final entry in _editorScopeFallbacks.entries) {
    if (result.containsKey(entry.key)) continue;
    for (final alias in entry.value) {
      final style = result[alias];
      if (style != null) {
        result[entry.key] = style;
        break;
      }
    }
  }
  return result;
}

EditorThemeEntry? findEditorThemeByKey(String key) {
  for (final entry in editorThemes) {
    if (entry.key == key) return entry;
  }
  return null;
}

Map<String, TextStyle> applySurfaceBackground(
  Map<String, TextStyle> theme,
  Color surfaceColor,
) {
  final result = <String, TextStyle>{};
  for (final entry in theme.entries) {
    // Keep the theme's own style untouched (including token background
    // colors); only the root surface is repainted with the app background.
    result[entry.key] = entry.key == 'root'
        ? entry.value.copyWith(backgroundColor: surfaceColor)
        : entry.value;
  }
  if (!result.containsKey('root')) {
    result['root'] = TextStyle(backgroundColor: surfaceColor);
  }
  return result;
}

Map<String, TextStyle> mergePluginEditorTheme(
  Map<String, TextStyle> base,
  Map<String, TextStyle>? override,
) {
  if (override == null || override.isEmpty) return base;
  final result = Map<String, TextStyle>.from(base);
  for (final entry in override.entries) {
    // TextStyle.merge lets every field the plugin set win while fields it
    // left unset keep the base theme's value.
    result[entry.key] = (result[entry.key] ?? const TextStyle()).merge(
      entry.value,
    );
  }
  return result;
}

/// Resolves the complete highlighter theme used by the editor.
///
/// Plugin themes contribute token styles rather than complete style maps. When
/// one is active, use the default theme only to fill missing token styles so a
/// user's saved editor-theme choice cannot affect the plugin contribution.
Map<String, TextStyle> resolveActiveEditorTheme(
  EditorThemeEntry selectedEntry,
  Brightness brightness, {
  Map<String, TextStyle>? pluginStyles,
  bool pluginThemeActive = false,
}) {
  final usePluginTheme =
      pluginThemeActive || (pluginStyles != null && pluginStyles.isNotEmpty);
  final base = resolveEditorTheme(
    usePluginTheme ? editorThemes.first : selectedEntry,
    brightness,
  );
  // The post-merge pass expands scope names a plugin wrote as theme-file
  // aliases (e.g. `title.function_`); the base's own scopes were already
  // normalized inside resolveEditorTheme.
  return _normalizeEditorTheme(mergePluginEditorTheme(base, pluginStyles));
}
