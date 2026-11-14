import 'dart:io';

import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/core/services/editor/code_forge_controller.dart';
import 'package:pyrite_ide/core/services/editor/editor_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/file_ops.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/features/edit_core/edit_core.dart';

/// The download preview is a read-only diff view: the buffer carries git
/// decorations and rejects edits until the transfer resolves. When the local
/// write fails there is nothing left to preview, so the editor must return to
/// its editable state instead of stranding the tab in the read-only view.
void main() {
  setUpAll(() async {
    try {
      await RustLib.init();
    } catch (_) {
      // Rust runtime unavailable; the test below reports itself as skipped.
    }
  });

  testWidgets('a failed download write releases the diff preview', (
    tester,
  ) async {
    bool rustReady;
    try {
      final probe = PyriteCodeForgeController();
      probe.dispose();
      rustReady = true;
    } catch (_) {
      rustReady = false;
    }
    if (!rustReady) {
      markTestSkipped(
        'code_forge 原生库未构建（RustLib.init 失败），'
        '跳过下载写失败回归；构建 code_forge 原生库后本测试会自动运行。',
      );
      return;
    }

    final dir = Directory.systemTemp.createTempSync('pyrite_download_release');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}${Platform.pathSeparator}main.py')
      ..writeAsStringSync('print(1)\n');

    final controller = PyriteCodeForgeController()..text = 'print(1)\n';
    addTearDown(controller.dispose);
    // The pending download has already put the editor in its preview state.
    controller.readOnly = true;

    final container = ProviderContainer(
      overrides: [
        useLsp.overrideWith((ref) => false),
        editorControllerMapProvider.overrideWith(
          (ref) => _StubControllerMap(ref, controller),
        ),
      ],
    );
    addTearDown(container.dispose);

    ensurePendingFileProviders(file.path);
    container
        .read(pendingDownloadProviderMap[file.path]!.notifier)
        .state = PendingDownload(
      diff: DiffInfo(
        addedRanges: const [],
        removedRanges: const [],
        unifiedLines: const [],
        addCount: 0,
        removeCount: 0,
      ),
      boardPath: '/main.py',
      // A directory cannot be written as a file, so the local write fails
      // without racing any permission setup.
      localPath: dir.path,
      correspondingPath: '/main.py',
      content: 'print(2)\n',
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => Scaffold(
                  body: EditCore(file: file, editorController: controller),
                ),
              ),
              GoRoute(
                path: '/file',
                builder: (context, state) =>
                    const Scaffold(body: SizedBox.shrink()),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byIcon(Icons.cloud_download),
      findsOneWidget,
      reason: 'the pending download must offer its confirm action',
    );

    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.cloud_download));
      // The file write and its failure live off the fake-async clock.
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(
      controller.readOnly,
      isFalse,
      reason:
          'a failed write leaves nothing to preview; the tab must edit again',
    );
  });
}

/// Hands [_releaseDiffPreview] the controller under test without building the
/// real editor layout tree, which is irrelevant to the transfer flow.
class _StubControllerMap extends EditorControllerMapNotifier {
  _StubControllerMap(super.ref, this._controller);

  final CodeForgeController _controller;

  @override
  CodeForgeController? getSelectedController() => _controller;
}
