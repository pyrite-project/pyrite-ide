import 'dart:io';

import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/message/ide_message.dart';
import 'package:pyrite_ide/features/window.dart';
import 'package:tabbed_view/tabbed_view.dart' hide TabbedView;

class _ReadOnlyController implements CodeForgeController {
  @override
  String get text => 'dirty buffer';

  @override
  set text(String value) {}

  @override
  bool readOnly = true;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not read by the save path: $invocation');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('save all reports a read-only file and keeps the window open', (
    tester,
  ) async {
    final file = File(
      '${Directory.systemTemp.path}/pyrite_read_only_'
      '${DateTime.now().microsecondsSinceEpoch}.py',
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(tabbedViewControllerProvider)
        .addTab(
          TabData(
            text: 'readonly.py',
            value: TabDataValue(
              type: 'file',
              filePath: file.path,
              file: file,
              editorController: _ReadOnlyController(),
              isSaved: false,
            ),
          ),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: appNavigatorKey,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );

    final window = UseWindow()..bind(container);
    window.onWindowClose();

    final saveAll = find.text(I18nKey.appExitUnsavedSaveAll.fallback);
    for (var i = 0; i < 500 && saveAll.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(saveAll, findsOneWidget);

    await tester.tap(saveAll);
    await tester.pumpAndSettle();

    final messages = container.read(ideMessageProvider);
    expect(
      messages.where(
        (entry) =>
            entry.type == IdeMessageType.error &&
            entry.message.contains(file.path) &&
            entry.message.contains(I18nKey.appExitSaveFailedReadOnly.fallback),
      ),
      hasLength(1),
      reason: 'the window has to say which file was not saved and why',
    );

    // Let the warning's dismissal timer run out inside the test zone.
    await tester.pump(const Duration(seconds: 13));
  });
}
