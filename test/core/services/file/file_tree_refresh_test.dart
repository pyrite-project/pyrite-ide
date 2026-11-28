import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/core/services/file/local_backend.dart' as local;
import 'package:pyrite_ide/core/services/file/local_tree.dart';
import 'package:super_tree/super_tree.dart';

void main() {
  late Directory temporaryDirectory;
  late ProviderContainer container;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'pyrite_file_tree_refresh_test_',
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

  LocalFileItemsNotifier notifier() =>
      container.read(localFileItemsProvider.notifier);

  TreeController<FileSystemItem> controller() =>
      container.read(localFileTreeViewControllerProvider);

  test('a downloaded file appears under its loaded folder', () async {
    final folder = Directory(path.join(temporaryDirectory.path, 'src'));
    await folder.create();
    await notifier().buildRootFileListItems();
    // Expanding is what loads a folder's children; only a loaded folder has
    // rows that a new path can be inserted next to.
    await controller().toggleNodeExpansion(
      controller().findNodeById(folder.path)!,
    );

    final downloaded = path.join(folder.path, 'main.py');
    await File(downloaded).writeAsString('print(1)');
    await notifier().notePathAdded(downloaded, isFolder: false);

    final node = controller().findNodeById(downloaded);
    expect(node, isNotNull);
    expect(node!.parent?.id, folder.path);
    expect(node.data, isA<local.LocalFileItem>());
  });

  test('a path in a never-expanded folder waits for that folder', () async {
    final folder = Directory(path.join(temporaryDirectory.path, 'src'));
    await folder.create();
    await notifier().buildRootFileListItems();

    final downloaded = path.join(folder.path, 'main.py');
    await File(downloaded).writeAsString('print(1)');
    await notifier().notePathAdded(downloaded, isFolder: false);
    // Inserting here would make the folder's own listing collide on expand, so
    // the row is left to that listing.
    expect(controller().findNodeById(downloaded), isNull);

    await controller().toggleNodeExpansion(
      controller().findNodeById(folder.path)!,
    );
    expect(controller().hasNodeLoadError(folder.path), isFalse);
    expect(controller().findNodeById(downloaded), isNotNull);
  });

  test(
    'a downloaded file at the workspace root becomes a top-level row',
    () async {
      final downloaded = path.join(temporaryDirectory.path, 'README.md');
      await File(downloaded).writeAsString('#');
      await notifier().notePathAdded(downloaded, isFolder: false);

      expect(controller().findNodeById(downloaded), isNotNull);
      expect(controller().roots.map((node) => node.id), contains(downloaded));
    },
  );

  test('a downloaded folder is inserted as a folder row', () async {
    final downloaded = path.join(temporaryDirectory.path, 'docs');
    await Directory(downloaded).create();
    await notifier().notePathAdded(downloaded, isFolder: true);

    final node = controller().findNodeById(downloaded);
    expect(node, isNotNull);
    expect(node!.data, isA<local.LocalFolderItem>());
    expect(node.canLoadChildren, isTrue);
  });

  test('noting the same path twice does not duplicate the row', () async {
    final downloaded = path.join(temporaryDirectory.path, 'README.md');
    await File(downloaded).writeAsString('#');
    await notifier().notePathAdded(downloaded, isFolder: false);
    await notifier().notePathAdded(downloaded, isFolder: false);

    final matches = controller().roots.where((node) => node.id == downloaded);
    expect(matches, hasLength(1));
  });

  test('a refresh requested during a walk still lands', () async {
    final first = notifier().buildRootFileListItems();
    // Lands while the walk started by `first` is already running: only a
    // trailing pass can see it.
    final late = path.join(temporaryDirectory.path, 'late.txt');
    await File(late).create();
    final second = notifier().buildRootFileListItems();

    await Future.wait([first, second]);

    expect(controller().findNodeById(late), isNotNull);
  });

  test('saving a git ignore file is recognised by path', () {
    expect(local.isGitIgnoreFilePath('/project/.gitignore'), isTrue);
    expect(local.isGitIgnoreFilePath('/project/sub/.gitignore'), isTrue);
    expect(local.isGitIgnoreFilePath('/project/gitignore'), isFalse);
    expect(local.isGitIgnoreFilePath('/project/.gitignore.bak'), isFalse);
  });
}
