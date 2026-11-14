import 'dart:io';

import 'package:code_forge/code_forge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/services/editor/code_forge_controller.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:tabbed_view/src/tab_data.dart';

/// A read-only tab holds a display-only buffer -- oversized content, binary
/// bytes, or a decode the editor could not reproduce -- so saving it would
/// overwrite the file with something other than what it holds.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    try {
      await RustLib.init();
    } catch (_) {
      // The Rust-backed rope needs code_forge.dll; without it controller
      // construction fails and the tests below bail instead.
    }
  });

  bool rustReady() {
    try {
      final probe = CodeForgeController();
      probe.dispose();
      return true;
    } catch (_) {
      return false;
    }
  }

  TabData tabFor(File file, CodeForgeController controller) => TabData(
    text: file.uri.pathSegments.last,
    value: TabDataValue(
      type: 'file',
      filePath: file.path,
      file: file,
      editorController: controller,
    ),
  );

  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pyrite_read_only_save_');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('saving a read-only tab leaves the file byte-identical', () async {
    if (!rustReady()) return;
    final file = File('${dir.path}${Platform.pathSeparator}sample.bin');
    final original = <int>[0x00, 0x01, 0x80, 0xFF, 0x0A];
    file.writeAsBytesSync(original);
    final controller = PyriteCodeForgeController()
      ..readOnly = true
      ..text = 'replacement text';
    addTearDown(controller.dispose);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container
        .read(fileProvider.notifier)
        .saveTab(tabFor(file, controller));

    expect(file.readAsBytesSync(), original);
  });

  test('an editable tab still writes normally', () async {
    if (!rustReady()) return;
    final file = File('${dir.path}${Platform.pathSeparator}main.py')
      ..writeAsStringSync('old\n');
    final controller = PyriteCodeForgeController()..text = 'new\n';
    addTearDown(controller.dispose);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container
        .read(fileProvider.notifier)
        .saveTab(tabFor(file, controller));

    expect(file.readAsStringSync(), 'new\n');
  });
}
