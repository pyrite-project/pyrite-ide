import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/features/terminal/terminal_context_menu.dart';

void main() {
  group('terminalContextMenuItems', () {
    test('offers the five actions in the expected order', () {
      final items = terminalContextMenuItems(hasSelection: false);

      expect(items.map((item) => item.action), [
        TerminalContextAction.copy,
        TerminalContextAction.paste,
        TerminalContextAction.selectAll,
        TerminalContextAction.clear,
        TerminalContextAction.search,
      ]);
    });

    test('copy is the only action disabled without a selection', () {
      final items = terminalContextMenuItems(hasSelection: false);

      expect(items.where((item) => !item.enabled).map((item) => item.action), [
        TerminalContextAction.copy,
      ]);
    });

    test('copy is enabled once text is selected', () {
      final copy = terminalContextMenuItems(hasSelection: true).first;

      expect(copy.enabled, isTrue);
    });

    test('the platform modifier is used in the shortcut hints', () {
      final items = terminalContextMenuItems(hasSelection: true, isMacOS: true);
      final copy = items.firstWhere(
        (item) => item.action == TerminalContextAction.copy,
      );

      expect(copy.shortcut, 'Cmd+Shift+C');
      expect(items.last.shortcut, 'Cmd+F');
    });

    test('clear has no shortcut hint', () {
      final clear = terminalContextMenuItems(
        hasSelection: false,
      ).firstWhere((item) => item.action == TerminalContextAction.clear);

      expect(clear.shortcut, isEmpty);
    });

    test('an action set subsets the menu in canonical order', () {
      final items = terminalContextMenuItems(
        hasSelection: false,
        actions: {TerminalContextAction.clear, TerminalContextAction.copy},
      );

      expect(items.map((item) => item.action), [
        TerminalContextAction.copy,
        TerminalContextAction.clear,
      ]);
    });

    test('an empty action set yields an empty menu', () {
      expect(
        terminalContextMenuItems(hasSelection: false, actions: {}),
        isEmpty,
      );
    });
  });
}
