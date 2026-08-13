import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/constants/editor_themes.dart';
import 'package:pyrite_ide/core/sdk/models/plugin_theme.dart';

void main() {
  test('plugin editor theme overrides the selected editor theme', () {
    final pluginTheme = PluginThemeData.fromMap(
      'fixture::theme',
      'theme',
      'fixture',
      {'editor.keyword': '#112233', 'dark.editor.keyword': '#AABBCC'},
    );
    const base = {
      'root': TextStyle(color: Colors.black, backgroundColor: Colors.white),
      'keyword': TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
    };

    final light = mergePluginEditorTheme(
      base,
      pluginTheme.editorStyles(Brightness.light),
    );
    final dark = mergePluginEditorTheme(
      base,
      pluginTheme.editorStyles(Brightness.dark),
    );

    expect(light['keyword']?.color, const Color(0xFF112233));
    expect(dark['keyword']?.color, const Color(0xFFAABBCC));
    expect(light['keyword']?.fontWeight, FontWeight.bold);
    expect(pluginTheme.hasEditorStyles, isTrue);
  });

  test('plugin editor theme ignores the selected fallback theme', () {
    final selected = EditorThemeEntry(
      label: 'Selected',
      key: 'selected',
      light: const {
        'root': TextStyle(color: Color(0xFF010203)),
        'keyword': TextStyle(color: Color(0xFF040506)),
      },
      dark: const {},
    );

    final resolved = resolveActiveEditorTheme(
      selected,
      Brightness.light,
      pluginStyles: const {'keyword': TextStyle(color: Color(0xFFAABBCC))},
    );

    expect(resolved['keyword']?.color, const Color(0xFFAABBCC));
    expect(resolved['root']?.color, isNot(const Color(0xFF010203)));
  });

  test('themes without editor styles do not lock the editor theme', () {
    final pluginTheme = PluginThemeData.fromMap(
      'fixture::theme',
      'theme',
      'fixture',
      {'terminal.foreground': '#112233'},
    );

    expect(pluginTheme.hasEditorStyles, isFalse);
  });

  test('dark-only plugin editor themes still ignore the selected fallback', () {
    final selected = EditorThemeEntry(
      label: 'Selected',
      key: 'selected',
      light: const {'root': TextStyle(color: Color(0xFF010203))},
      dark: const {},
    );

    final resolved = resolveActiveEditorTheme(
      selected,
      Brightness.light,
      pluginThemeActive: true,
    );

    expect(resolved['root']?.color, isNot(const Color(0xFF010203)));
  });
}
