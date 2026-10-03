import 'dart:io';

import 'package:code_forge/code_forge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/editor/editor_controller_provider.dart';
import 'package:pyrite_ide/core/services/message/ide_message.dart';
import 'package:pyrite_ide/core/services/settings.dart';

/// Files above [maxEditableFileLength] open read-only: a multi-megabyte log
/// or data dump still loads (so a save can never write back a truncated
/// buffer) but is never offered as editable, and the user is told why.
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

  Future<ProviderContainer> container() async {
    final c = ProviderContainer(
      overrides: [useLsp.overrideWith((ref) => false)],
    );
    return c;
  }

  test('an oversized file opens read-only and warns', () async {
    if (!rustReady()) return;
    final dir = await Directory.systemTemp.createTemp('pyrite_oversize');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}${Platform.pathSeparator}dump.py');
    final pad = List.filled(1024, 'x').join();
    final sink = file.openWrite(mode: FileMode.write);
    for (var i = 0; i <= maxEditableFileLength ~/ 1024; i++) {
      sink.write(pad);
    }
    await sink.close();

    final ref = await container();
    addTearDown(ref.dispose);
    final controller = await ref
        .read(editorControllerMapProvider.notifier)
        .createNewEditorController(file);
    expect(controller, isNotNull);
    expect(controller!.readOnly, isTrue);

    final messages = ref.read(ideMessageProvider);
    expect(
      messages.any(
        (entry) =>
            entry.type == IdeMessageType.warning &&
            entry.message.contains('dump.py'),
      ),
      isTrue,
    );
  });

  test('a normal file stays editable and stays quiet', () async {
    if (!rustReady()) return;
    final dir = await Directory.systemTemp.createTemp('pyrite_normal');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}${Platform.pathSeparator}main.py')
      ..writeAsStringSync('print("hello")\n');

    final ref = await container();
    addTearDown(ref.dispose);
    final controller = await ref
        .read(editorControllerMapProvider.notifier)
        .createNewEditorController(file);
    expect(controller, isNotNull);
    expect(controller!.readOnly, isFalse);
    expect(ref.read(ideMessageProvider), isEmpty);
  });
}
