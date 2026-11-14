import 'dart:io';

import 'package:code_forge/code_forge.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/editor/editor_controller_provider.dart';
import 'package:pyrite_ide/core/services/settings.dart';

/// Files whose bytes are not strict UTF-8 still have to reach an editor.
///
/// The buffer may come from a caller that already decoded the file with the
/// encoding the user picked, or from the headless path that decodes
/// malformed tolerantly. Neither may be thrown away by a second strict read
/// of the same path.
void main() {
  setUpAll(() async {
    try {
      await RustLib.init();
    } catch (_) {
      // The Rust-backed rope needs code_forge.dll; without it every test
      // below would fail on controller construction, so they bail instead.
    }
  });

  /// A controller can only exist once the Rust runtime is loaded.
  bool rustReady() {
    try {
      final probe = CodeForgeController();
      probe.dispose();
      return true;
    } catch (_) {
      return false;
    }
  }

  ProviderContainer container() {
    return ProviderContainer(overrides: [useLsp.overrideWith((ref) => false)]);
  }

  group('opening non-UTF-8 bytes headlessly', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('pyrite_non_utf8_');
    });

    tearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    final cases = <String, List<int>>{
      'GBK': gbk.encode('print("你好")\n').toList(),
      'UTF-16 LE with BOM': [0xFF, 0xFE, 0x70, 0x00, 0x0A, 0x00],
      'invalid UTF-8': [0x70, 0x72, 0x69, 0x80, 0xFF, 0x0A],
    };

    cases.forEach((name, bytes) {
      test('a $name file opens read-only instead of failing', () async {
        if (!rustReady()) return;
        final file = File('${dir.path}${Platform.pathSeparator}sample.py')
          ..writeAsBytesSync(bytes);
        final ref = container();
        addTearDown(ref.dispose);

        final controller = await ref
            .read(editorControllerMapProvider.notifier)
            .createNewEditorController(file);

        expect(controller, isNotNull);
        expect(controller!.openedFile, file.path);
        expect(controller.readOnly, isTrue);
        // The tolerant decode is what the user sees; an empty buffer would
        // mean the strict read aborted the open after all.
        expect(controller.text, isNotEmpty);
      });
    });
  });

  test('a buffer decoded by the open dialog is installed verbatim', () async {
    if (!rustReady()) return;
    final dir = await Directory.systemTemp.createTemp('pyrite_decoded_');
    addTearDown(() => dir.delete(recursive: true));
    const decoded = 'print("你好")\n';
    final file = File('${dir.path}${Platform.pathSeparator}sample.py')
      ..writeAsBytesSync(gbk.encode(decoded));
    final ref = container();
    addTearDown(ref.dispose);

    final controller = await ref
        .read(editorControllerMapProvider.notifier)
        .createNewEditorController(file, initialText: decoded);

    expect(controller, isNotNull);
    expect(controller!.openedFile, file.path);
    expect(controller.text, decoded);
    // The caller decoded the bytes and recorded the encoding, so the tab is
    // editable; saving re-encodes instead of writing UTF-8.
    expect(controller.readOnly, isFalse);
  });
}
