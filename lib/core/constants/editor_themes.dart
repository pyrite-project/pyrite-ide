import 'package:flutter/material.dart';
import 'package:re_highlight/styles/atom-one-light.dart';
import 'package:re_highlight/styles/atom-one-dark-reasonable.dart';
import 'package:re_highlight/styles/vs.dart';
import 'package:re_highlight/styles/vs2015.dart';
import 'package:re_highlight/styles/github.dart';
import 'package:re_highlight/styles/github-dark.dart';
import 'package:re_highlight/styles/intellij-light.dart';
import 'package:re_highlight/styles/androidstudio.dart';
import 'package:re_highlight/styles/panda-syntax-light.dart';
import 'package:re_highlight/styles/monokai-sublime.dart';
import 'package:re_highlight/styles/nord.dart';
import 'package:re_highlight/styles/paraiso-light.dart';
import 'package:re_highlight/styles/paraiso-dark.dart';
import 'package:re_highlight/styles/tokyo-night-light.dart';
import 'package:re_highlight/styles/tokyo-night-dark.dart';
import 'package:re_highlight/styles/night-owl.dart';
import 'package:re_highlight/styles/kimbie-light.dart';
import 'package:re_highlight/styles/kimbie-dark.dart';
import 'package:re_highlight/styles/foundation.dart';
import 'package:re_highlight/styles/xcode.dart';
import 'package:re_highlight/styles/stackoverflow-light.dart';
import 'package:re_highlight/styles/stackoverflow-dark.dart';
import 'package:re_highlight/styles/qtcreator-light.dart';
import 'package:re_highlight/styles/qtcreator-dark.dart';

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
  return brightness == Brightness.light ? entry.light : entry.dark;
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
    final s = entry.value;
    result[entry.key] = TextStyle(
      color: s.color,
      backgroundColor: entry.key == 'root' ? surfaceColor : null,
      fontWeight: s.fontWeight,
      fontStyle: s.fontStyle,
      fontSize: s.fontSize,
      letterSpacing: s.letterSpacing,
      wordSpacing: s.wordSpacing,
      height: s.height,
      decoration: s.decoration,
      decorationColor: s.decorationColor,
      decorationStyle: s.decorationStyle,
      fontFamily: s.fontFamily,
      fontFamilyFallback: s.fontFamilyFallback,

      overflow: s.overflow,
    );
  }
  if (!result.containsKey('root')) {
    result['root'] = TextStyle(backgroundColor: surfaceColor);
  }
  return result;
}
