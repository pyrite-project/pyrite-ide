import 'dart:io';

import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/core/models/search_options.dart';
import 'package:pyrite_ide/core/services/editor/code_forge_controller.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/core/services/shortcut_utils.dart';
import 'package:pyrite_ide/features/edit_core/edit_core.dart';
import 'package:pyrite_ide/shared/search_field.dart';

Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool alt = false,
  bool primary = false,
}) async {
  final primaryKey = usesCommandShortcut
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  // Apple platforms bind the find options to Cmd+Alt.
  final withPrimary = primary || (alt && usesCommandShortcut);
  if (withPrimary) await tester.sendKeyDownEvent(primaryKey);
  if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyEvent(key);
  if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  if (withPrimary) await tester.sendKeyUpEvent(primaryKey);
  await tester.pump();
}

/// Alt+C / Alt+W / Alt+R toggle the editor's find options both from the find
/// input and from the code area while the find bar is open.
void main() {
  setUpAll(() async {
    try {
      await RustLib.init();
    } catch (_) {
      // Rust runtime unavailable; the test cannot run.
    }
  });

  testWidgets('find options toggle from the find input and the code area', (
    tester,
  ) async {
    bool rustReady;
    try {
      PyriteCodeForgeController().dispose();
      rustReady = true;
    } catch (_) {
      rustReady = false;
    }
    // The toggles live on the controller's Rust-backed buffer, so a machine
    // without the native library cannot run this test at all. Marking it
    // skipped (same shape as go_to_line_repro_test.dart) keeps CI showing the
    // unavailability, while a bare expect would only report a failure.
    if (!rustReady) {
      markTestSkipped(
        'code_forge 原生库未构建（RustLib.init 失败），'
        '跳过查找选项快捷键回归；构建 code_forge 原生库后本测试会自动运行。',
      );
      return;
    }

    final dir = Directory.systemTemp.createTempSync('pyrite_find_options');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}${Platform.pathSeparator}main.py')
      ..writeAsStringSync('print("hello")\n');

    final controller = PyriteCodeForgeController();
    addTearDown(controller.dispose);
    controller.text = file.readAsStringSync();

    bool isOn(SearchOption option) => tester
        .widget<SearchOptionToggle>(
          find.byWidgetPredicate(
            (widget) => widget is SearchOptionToggle && widget.option == option,
          ),
        )
        .active;

    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [useLsp.overrideWith((ref) => false)],
          child: MaterialApp.router(
            // flutter_test defaults to Android, whose padded 48px tap targets
            // would overflow the find bar's 28px desktop buttons.
            theme: ThemeData(
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            routerConfig: GoRouter(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (context, state) => Scaffold(
                    body: EditCore(file: file, editorController: controller),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      controller.openedFile = file.path;
      // Assigning openedFile kicks off real async IO that a fake-async zone
      // would hang on forever.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await tester.pump();

      controller.focusNode?.requestFocus();
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.keyF, primary: true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(SearchOptionToggle), findsNWidgets(3));

      // The find input has focus after opening the bar.
      await _press(tester, LogicalKeyboardKey.keyC, alt: true);
      expect(isOn(SearchOption.caseSensitive), isTrue);

      controller.focusNode?.requestFocus();
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.keyW, alt: true);
      expect(isOn(SearchOption.wholeWord), isTrue);

      await _press(tester, LogicalKeyboardKey.keyR, alt: true);
      expect(isOn(SearchOption.regex), isTrue);
      await _press(tester, LogicalKeyboardKey.keyC, alt: true);
      expect(isOn(SearchOption.caseSensitive), isFalse);
    });
  });
}
