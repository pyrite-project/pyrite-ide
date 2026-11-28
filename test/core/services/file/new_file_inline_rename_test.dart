import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/core/services/file/local_tree.dart';

void main() {
  late Directory temporaryDirectory;
  late ProviderContainer container;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'pyrite_new_file_inline_rename_test_',
    );
    container = ProviderContainer();
    container.read(fileProvider.notifier).setDirectory(temporaryDirectory);
    await container
        .read(localFileItemsProvider.notifier)
        .buildRootFileListItems();
  });

  tearDown(() async {
    container.dispose();
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('creating a file selects it and starts an inline rename', () async {
    final notifier = container.read(fileProvider.notifier);
    final target = path.join(temporaryDirectory.path, 'new_file');

    await notifier.createFileAndStartRename(target);

    final controller = container.read(localFileTreeViewControllerProvider);
    expect(File(target).existsSync(), isTrue);
    expect(controller.findNodeById(target), isNotNull);
    expect(controller.selectedNodeId, target);
    expect(controller.renamingNodeId, target);
  });

  test('submitting the inline rename renames the file on disk', () async {
    final notifier = container.read(fileProvider.notifier);
    final target = path.join(temporaryDirectory.path, 'new_file');
    await notifier.createFileAndStartRename(target);

    final controller = container.read(localFileTreeViewControllerProvider);
    controller.renameNode(target, 'main.py');
    final renamed = path.join(temporaryDirectory.path, 'main.py');
    await _waitUntil(() => File(renamed).existsSync());

    expect(File(renamed).existsSync(), isTrue);
    expect(File(target).existsSync(), isFalse);
    expect(controller.renamingNodeId, isNull);
  });
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
