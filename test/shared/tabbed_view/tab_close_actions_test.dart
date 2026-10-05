import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/shared/tabbed_view/tab_close_actions.dart';
import 'package:tabbed_view/src/tab_data.dart';

TabData tab(String name) => TabData(text: name);

void main() {
  group('otherTabs', () {
    test('drops the kept tab', () {
      final tabs = [tab('a'), tab('b'), tab('c')];
      expect(otherTabs(tabs, tabs[1]).map((t) => t.text), ['a', 'c']);
    });

    test('keeps order', () {
      final tabs = [tab('a'), tab('b'), tab('c'), tab('d')];
      expect(otherTabs(tabs, tabs[0]).map((t) => t.text), ['b', 'c', 'd']);
    });

    test('is empty when the only tab is the kept one', () {
      final tabs = [tab('a')];
      expect(otherTabs(tabs, tabs.first), isEmpty);
    });

    test('a tab that is merely equal is not treated as the kept one', () {
      // TabData does not override ==, so identity is the only thing that can
      // tell two same-named tabs apart.
      final kept = tab('main.py');
      final other = tab('main.py');
      expect(otherTabs([kept, other], kept), [other]);
    });
  });

  group('tabsToTheRightOf', () {
    final tabs = [tab('a'), tab('b'), tab('c'), tab('d')];

    test('takes everything after the index', () {
      expect(tabsToTheRightOf(tabs, 1).map((t) => t.text), ['c', 'd']);
    });

    test('is empty for the last tab', () {
      expect(tabsToTheRightOf(tabs, 3), isEmpty);
    });

    test('is empty for an index past the end', () {
      expect(tabsToTheRightOf(tabs, 9), isEmpty);
    });

    test('takes everything but the first tab for index zero', () {
      expect(tabsToTheRightOf(tabs, 0).map((t) => t.text), ['b', 'c', 'd']);
    });
  });
}
