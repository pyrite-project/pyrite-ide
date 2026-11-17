import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/constants/editor_themes.dart';

void main() {
  group('editor theme comment styling', () {
    test('built-in themes render comments upright', () {
      for (final entry in editorThemes) {
        for (final brightness in Brightness.values) {
          final theme = resolveEditorTheme(entry, brightness);
          final comment = theme['comment'];
          if (comment == null) continue;
          expect(
            comment.fontStyle,
            isNot(FontStyle.italic),
            reason: '${entry.key} (${brightness.name}) must not italicize comments',
          );
        }
      }
    });

    test('plugin themes do not inherit the base theme slant', () {
      // A plugin contributes colors only, so the base theme's italic comment
      // would otherwise survive the merge and reach the editor.
      final base = resolveEditorTheme(editorThemes.first, Brightness.light);
      final merged = mergePluginEditorTheme(base, {
        'comment': const TextStyle(color: Color(0xFF6A9955)),
      });
      expect(merged['comment']?.color, const Color(0xFF6A9955));
      expect(
        merged['comment']?.fontStyle,
        isNot(FontStyle.italic),
        reason: 'the plugin comment color must not drag the italic face along',
      );
    });

    test('resolving a plugin theme keeps comments upright', () {
      final resolved = resolveActiveEditorTheme(
        editorThemes.first,
        Brightness.light,
        pluginStyles: {
          'comment': const TextStyle(color: Color(0xFF6A9955)),
        },
        pluginThemeActive: true,
      );
      expect(resolved['comment']?.color, const Color(0xFF6A9955));
      expect(resolved['comment']?.fontStyle, isNot(FontStyle.italic));
    });

    test('the surface background does not restore italics', () {
      final applied = applySurfaceBackground(
        resolveEditorTheme(editorThemes.first, Brightness.light),
        const Color(0xFFFAFAFA),
      );
      expect(applied['comment']?.fontStyle, isNot(FontStyle.italic));
    });
  });

  group('editor theme scope normalization', () {
    test('runtime scope names the theme files omit get filled', () {
      // re_highlight languages emit scopes like `title.function` while theme
      // files key them as `title.function_` (or omit them); the resolution
      // must fill the runtime names or those tokens render unstyled.
      for (final entry in editorThemes) {
        for (final brightness in Brightness.values) {
          final theme = resolveEditorTheme(entry, brightness);
          expect(
            theme.containsKey('title.function'),
            isTrue,
            reason: '${entry.key} (${brightness.name}) must style functions',
          );
          expect(
            theme.containsKey('title.class'),
            isTrue,
            reason: '${entry.key} (${brightness.name}) must style classes',
          );
        }
      }
    });

    test('an explicit scope style is never overwritten by a fallback', () {
      final theme = resolveEditorTheme(editorThemes.first, Brightness.light);
      final title = theme['title'];
      expect(theme['title.function']?.color, title?.color);
    });
  });

  group('editor theme full style merge', () {
    test('plugin styles carry every field they set', () {
      final base = resolveEditorTheme(editorThemes.first, Brightness.light);
      final merged = mergePluginEditorTheme(base, {
        'keyword': const TextStyle(
          color: Color(0xFFE65100),
          fontWeight: FontWeight.bold,
        ),
      });
      expect(merged['keyword']?.color, const Color(0xFFE65100));
      expect(merged['keyword']?.fontWeight, FontWeight.bold);
    });

    test('fields the plugin leaves unset keep the base value', () {
      final base = resolveEditorTheme(editorThemes.first, Brightness.light);
      final merged = mergePluginEditorTheme(base, {
        'comment': const TextStyle(color: Color(0xFF6A9955)),
      });
      expect(merged['comment']?.color, const Color(0xFF6A9955));
      expect(merged['comment']?.fontWeight, base['comment']?.fontWeight);
    });

    test('a plugin can explicitly italicize a token', () {
      final base = resolveEditorTheme(editorThemes.first, Brightness.light);
      final merged = mergePluginEditorTheme(base, {
        'doctag': const TextStyle(color: Color(0xFFA626A4), fontStyle: FontStyle.italic),
      });
      expect(merged['doctag']?.fontStyle, FontStyle.italic);
    });

    test('token background colors survive the surface application', () {
      final applied = applySurfaceBackground({
        'string': const TextStyle(
          color: Color(0xFF50A14F),
          backgroundColor: Color(0xFF112233),
        ),
      }, const Color(0xFFFAFAFA));
      expect(applied['string']?.backgroundColor, const Color(0xFF112233));
      expect(applied['root']?.backgroundColor, const Color(0xFFFAFAFA));
    });
  });
}
