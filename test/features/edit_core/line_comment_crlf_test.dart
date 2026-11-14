import 'dart:io';

import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/editor/code_forge_controller.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/features/edit_core/edit_core.dart';

/// Drives the real Ctrl+/ shortcut over files whose line endings are not the
/// one-character '\n' the comment toggle used to assume.
///
/// `getLineText` strips the whole break ("\r\n" as well as "\n"), so computing
/// the replaced range as `line.length + 1` leaves one character per line
/// behind on CRLF files: the tail of the buffer is duplicated and later lines
/// are commented over the wrong offsets. These tests pin the text and the
/// selection mapping down on CRLF and mixed-ending buffers.
void main() {
  setUpAll(() async {
    try {
      await RustLib.init();
    } catch (_) {
      // Rust runtime unavailable; the tests below cannot run.
    }
  });

  bool rustReady() {
    try {
      final probe = PyriteCodeForgeController();
      probe.dispose();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<PyriteCodeForgeController> pumpEditor(
    WidgetTester tester,
    String content,
  ) async {
    final dir = Directory.systemTemp.createTempSync('pyrite_crlf_comment');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}${Platform.pathSeparator}main.py')
      ..writeAsStringSync(content);

    final controller = PyriteCodeForgeController();
    addTearDown(controller.dispose);
    controller.text = content;

    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [useLsp.overrideWith((ref) => false)],
          child: MaterialApp(
            home: Scaffold(
              body: EditCore(file: file, editorController: controller),
            ),
          ),
        ),
      );
      // Assigning openedFile kicks off real async IO (git/file reads) that a
      // fake-async zone would hang on forever.
      controller.openedFile = file.path;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();
    });
    return controller;
  }

  Future<void> toggleComment(
    WidgetTester tester,
    CodeForgeController controller,
  ) async {
    controller.focusNode?.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  testWidgets('Ctrl+/ comments CRLF lines without corrupting the buffer', (
    tester,
  ) async {
    if (!rustReady()) {
      markTestSkipped('code_forge 原生库未构建，跳过 CRLF 注释回归。');
      return;
    }

    const original = 'a\r\nb\r\nc';
    final controller = await pumpEditor(tester, original);
    controller.setSelectionSilently(
      const TextSelection(baseOffset: 0, extentOffset: 4),
    );
    await tester.pump();

    await toggleComment(tester, controller);

    expect(controller.text, '# a\r\n# b\r\nc');
    // The extent sat at the end of "b"; it must stay at the end of "# b"
    // instead of drifting into the duplicated tail.
    expect(controller.selection.extentOffset, 8);

    await toggleComment(tester, controller);
    expect(
      controller.text,
      original,
      reason: 'a second toggle must restore it',
    );
  });

  testWidgets('a caret inside a CRLF line keeps its column', (tester) async {
    if (!rustReady()) {
      markTestSkipped('code_forge 原生库未构建，跳过 CRLF 注释回归。');
      return;
    }

    final controller = await pumpEditor(tester, 'a\r\nb\r\nc');
    // End of "b", right before the CRLF break.
    controller.setSelectionSilently(const TextSelection.collapsed(offset: 4));
    await tester.pump();

    await toggleComment(tester, controller);

    expect(controller.text, 'a\r\n# b\r\nc');
    expect(controller.selection.extentOffset, 6);
  });

  testWidgets('selection at the next CRLF line start maps past the block', (
    tester,
  ) async {
    if (!rustReady()) {
      markTestSkipped('code_forge 原生库未构建，跳过 CRLF 注释回归。');
      return;
    }

    final controller = await pumpEditor(tester, 'a\r\nb\r\nc');
    // Ends at the start of line 3, which the toggle trims back to line 2.
    controller.setSelectionSilently(
      const TextSelection(baseOffset: 0, extentOffset: 6),
    );
    await tester.pump();

    await toggleComment(tester, controller);

    expect(controller.text, '# a\r\n# b\r\nc');
    // Line 3 still starts after the two original CRLF breaks.
    expect(controller.selection.extentOffset, 10);
  });

  testWidgets('mixed LF/CRLF endings survive a toggle round-trip', (
    tester,
  ) async {
    if (!rustReady()) {
      markTestSkipped('code_forge 原生库未构建，跳过 CRLF 注释回归。');
      return;
    }

    const original = 'a\nb\r\nc\nd';
    final controller = await pumpEditor(tester, original);
    controller.setSelectionSilently(
      TextSelection(baseOffset: 0, extentOffset: controller.length),
    );
    await tester.pump();

    await toggleComment(tester, controller);

    expect(controller.text, '# a\n# b\r\n# c\n# d');

    await toggleComment(tester, controller);
    expect(controller.text, original, reason: 'each line keeps its own break');
  });
}
