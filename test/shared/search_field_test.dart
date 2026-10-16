import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/models/search_options.dart';
import 'package:pyrite_ide/core/services/shortcut_utils.dart';
import 'package:pyrite_ide/shared/search_field.dart';

/// Presses Alt+[key], or Cmd+Alt+[key] where Option alone types a character.
Future<void> pressFindOption(
  WidgetTester tester,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  if (usesCommandShortcut) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  }
  await tester.sendKeyEvent(key);
  if (usesCommandShortcut) {
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  }
  await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  await tester.pump();
}

void main() {
  late SearchOptions options;
  late String query;
  late TextEditingController controller;

  setUp(() {
    options = const SearchOptions();
    query = '';
    controller = TextEditingController();
  });

  tearDown(() => controller.dispose());

  Future<void> pumpField(WidgetTester tester) {
    return tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => OptionsSearchField(
                controller: controller,
                options: options,
                onOptionsChanged: (next) => setState(() => options = next),
                onChanged: (next) => setState(() => query = next),
              ),
            ),
          ),
        ),
      ),
    );
  }

  SearchOptionToggle toggle(WidgetTester tester, SearchOption option) {
    return tester.widget<SearchOptionToggle>(
      find.byWidgetPredicate(
        (widget) => widget is SearchOptionToggle && widget.option == option,
      ),
    );
  }

  testWidgets('Alt+C / Alt+W / Alt+R toggle the options while focused', (
    tester,
  ) async {
    await pumpField(tester);
    await tester.tap(find.byType(TextField));
    await tester.pump();

    await pressFindOption(tester, LogicalKeyboardKey.keyC);
    expect(options, const SearchOptions(caseSensitive: true));
    await pressFindOption(tester, LogicalKeyboardKey.keyW);
    await pressFindOption(tester, LogicalKeyboardKey.keyR);
    expect(
      options,
      const SearchOptions(caseSensitive: true, wholeWord: true, regex: true),
    );
    expect(toggle(tester, SearchOption.regex).active, isTrue);

    await pressFindOption(tester, LogicalKeyboardKey.keyC);
    expect(options.caseSensitive, isFalse);
  });

  testWidgets('clicking a toggle flips it and its tooltip names the key', (
    tester,
  ) async {
    await pumpField(tester);
    await tester.tap(find.text('ab'));
    await tester.pump();
    expect(options, const SearchOptions(wholeWord: true));
    expect(
      toggle(tester, SearchOption.caseSensitive).tooltip,
      endsWith('(${findCaseSensitiveShortcutLabel()})'),
    );
  });

  testWidgets('Escape clears the query', (tester) async {
    await pumpField(tester);
    await tester.enterText(find.byType(TextField), 'ttyACM');
    expect(query, 'ttyACM');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(controller.text, isEmpty);
    expect(query, isEmpty);
  });
}
