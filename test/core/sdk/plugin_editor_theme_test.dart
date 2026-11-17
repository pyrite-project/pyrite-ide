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

  test('plugin editor styles may carry the full TextStyle', () {
    final pluginTheme = PluginThemeData.fromMap(
      'fixture::theme',
      'theme',
      'fixture',
      {
        'editor.keyword': {
          'color': '#E65100',
          'fontWeight': 'bold',
          'fontSize': 20,
          'letterSpacing': 0.5,
        },
        'editor.comment': {'color': '#6A9955', 'fontStyle': 'italic'},
        'editor.string': {'backgroundColor': '#112233'},
        // Legacy color strings keep working.
        'editor.number': '#986801',
      },
    );
    final styles = pluginTheme.editorStyles(Brightness.light);
    expect(styles['keyword']?.color, const Color(0xFFE65100));
    expect(styles['keyword']?.fontWeight, FontWeight.bold);
    expect(styles['keyword']?.fontSize, 20);
    expect(styles['keyword']?.letterSpacing, 0.5);
    expect(styles['comment']?.fontStyle, FontStyle.italic);
    expect(styles['string']?.backgroundColor, const Color(0xFF112233));
    expect(styles['number']?.color, const Color(0xFF986801));

    final resolved = resolveActiveEditorTheme(
      editorThemes.first,
      Brightness.light,
      pluginStyles: styles,
      pluginThemeActive: true,
    );
    expect(resolved['keyword']?.fontWeight, FontWeight.bold);
    expect(resolved['keyword']?.color, const Color(0xFFE65100));
    // The plugin explicitly asked for an italic comment; the base theme's
    // upright normalization applies before the merge, so this survives.
    expect(resolved['comment']?.fontStyle, FontStyle.italic);
  });

  test('dark editor styles merge over light per TextStyle field', () {
    final pluginTheme = PluginThemeData.fromMap(
      'fixture::theme',
      'theme',
      'fixture',
      {
        'editor.keyword': {'color': '#E65100', 'fontWeight': 'bold'},
        'dark.editor.keyword': {'color': '#FFB74D'},
      },
    );
    final dark = pluginTheme.editorStyles(Brightness.dark);
    expect(dark['keyword']?.color, const Color(0xFFFFB74D));
    expect(dark['keyword']?.fontWeight, FontWeight.bold);
  });

  test('editor typography keys are parsed as settings, not tokens', () {
    final pluginTheme = PluginThemeData.fromMap(
      'fixture::theme',
      'theme',
      'fixture',
      {
        'editor.fontFamily': 'Cascadia Code',
        'editor.fontSize': 14,
        'editor.lineHeight': 1.5,
      },
    );
    expect(pluginTheme.editorFontFamily, 'Cascadia Code');
    expect(pluginTheme.editorFontSize, 14);
    expect(pluginTheme.editorLineHeight, 1.5);
    expect(pluginTheme.hasEditorStyles, isFalse);
    // The typography keys must not leak into the token style map.
    expect(pluginTheme.editorStyles(Brightness.light).containsKey('fontFamily'),
        isFalse);
  });

  test('validateEditorStyles reports malformed contributions', () {
    expect(
      PluginThemeData.validateEditorStyles({
        'editor.keyword': {'color': '#E65100', 'fontStyle': 'italic'},
      }),
      isNull,
    );
    expect(
      PluginThemeData.validateEditorStyles({
        'editor.keyword': {'colour': '#E65100'},
      }),
      contains('unknown style field'),
    );
    expect(
      PluginThemeData.validateEditorStyles({
        'editor.keyword': {'fontWeight': 'w900'},
      }),
      isNull,
    );
    expect(
      PluginThemeData.validateEditorStyles({
        'editor.keyword': {'fontWeight': 'w950'},
      }),
      contains('fontWeight'),
    );
    expect(
      PluginThemeData.validateEditorStyles({'editor.keyword': 'not-a-color'}),
      contains('must be a color or a style object'),
    );
    expect(
      PluginThemeData.validateEditorStyles({'editor.fontSize': 14}),
      isNull,
    );
    expect(
      PluginThemeData.validateEditorStyles({'editor.fontSize': -1}),
      contains('must be a positive number'),
    );
  });
}
