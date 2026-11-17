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
      'pyrite_focus_folder_target_test_',
    );
    container = ProviderContainer();
    container.read(fileProvider.notifier).setDirectory(temporaryDirectory);
  });

  tearDown(() async {
    container.dispose();
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('a focused file targets the subfolder that holds it', () async {
    // A nested row is what the context menu acts on: creating a file while
    // `cam/LICENSE` is focused has to land in `cam`, not in the workspace.
    final camDirectory = Directory(
      path.join(temporaryDirectory.path, 'cam'),
    )..createSync();
    final licenseFile = File(path.join(camDirectory.path, 'LICENSE'))
      ..writeAsStringSync('MIT');
    await container
        .read(localFileItemsProvider.notifier)
        .buildRootFileListItems();

    final controller = container.read(localFileTreeViewControllerProvider);
    final camNode = controller.findNodeById(camDirectory.path);
    expect(camNode, isNotNull);
    await controller.ensureNodeChildrenLoaded(camNode!);

    expect(controller.findNodeById(licenseFile.path), isNotNull);
    controller.setSelectedNodeId(licenseFile.path);

    final target = container.read(fileProvider.notifier).getFocusFolderNode();

    expect(target?.id, camDirectory.path);
    expect(target?.data.name, 'cam');
  });

  test('a focused folder targets itself', () async {
    final camDirectory = Directory(
      path.join(temporaryDirectory.path, 'cam'),
    )..createSync();
    await container
        .read(localFileItemsProvider.notifier)
        .buildRootFileListItems();

    final controller = container.read(localFileTreeViewControllerProvider);
    controller.setSelectedNodeId(camDirectory.path);

    final target = container.read(fileProvider.notifier).getFocusFolderNode();

    expect(target?.id, camDirectory.path);
  });
}
