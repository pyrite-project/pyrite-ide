import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/features/edit_core/line_comment.dart';

void main() {
  group('toggleLineComments | comment', () {
    test('inserts marker after each line indentation', () {
      final result = toggleLineComments(['def f():', '  pass'])!;
      expect(result.lines, ['# def f():', '  # pass']);
      expect(result.deltas, [2, 2]);
    });

    test('skips blank and whitespace-only lines', () {
      final result = toggleLineComments(['a', '', '  ', 'b'])!;
      expect(result.lines, ['# a', '', '  ', '# b']);
      expect(result.deltas, [2, 0, 0, 2]);
    });

    test('keeps inline hashes intact', () {
      final result = toggleLineComments(['x = 1  # note'])!;
      expect(result.lines, ['# x = 1  # note']);
    });

    test('a lone blank line gains a fresh marker', () {
      final result = toggleLineComments([''])!;
      expect(result.lines, ['# ']);
      expect(result.deltas, [2]);
    });

    test('multiple blank lines do nothing', () {
      expect(toggleLineComments(['', '']), isNull);
    });
  });

  group('toggleLineComments | uncomment', () {
    test('removes marker and one space, preserving indentation', () {
      final result = toggleLineComments(['# a', '  # b'])!;
      expect(result.lines, ['a', '  b']);
      expect(result.deltas, [-2, -2]);
    });

    test('removes a bare marker without trailing space', () {
      expect(toggleLineComments(['#c'])!.lines, ['c']);
    });

    test('only removes one level of nesting per toggle', () {
      final once = toggleLineComments(['# # nested'])!.lines;
      expect(once, ['# nested']);
      expect(toggleLineComments(once)!.lines, ['nested']);
    });
  });

  group('toggleLineComments | mixed', () {
    test('partially commented block gets commented instead', () {
      final result = toggleLineComments(['# a', 'b'])!;
      expect(result.lines, ['# # a', '# b']);
    });

    test('empty input does nothing', () {
      expect(toggleLineComments([]), isNull);
    });
  });

  group('toggleLineComments | non-python markers', () {
    test('comments C-style with //', () {
      final result = toggleLineComments(['int x;', '  y();'], marker: '//')!;
      expect(result.lines, ['// int x;', '  // y();']);
      expect(result.deltas, [3, 3]);
    });

    test('uncomments C-style without eating code', () {
      final result = toggleLineComments(['// int x;', '//x'], marker: '//')!;
      expect(result.lines, ['int x;', 'x']);
    });

    test('a lone blank line gains a fresh // marker', () {
      expect(toggleLineComments([''], marker: '//')!.lines, ['// ']);
    });

    test('comments Lua-style with --', () {
      final result = toggleLineComments(['local x = 1'], marker: '--')!;
      expect(result.lines, ['-- local x = 1']);
    });

    test('does not treat a -- marker as a # marker', () {
      final result = toggleLineComments(['-- a'], marker: '#')!;
      expect(result.lines, ['# -- a']);
    });

    test('markers containing regex metacharacters are escaped', () {
      final commented = toggleLineComments(['a'], marker: '//*')!.lines;
      expect(commented, ['//* a']);
      expect(toggleLineComments(commented, marker: '//*')!.lines, ['a']);
    });
  });
}
