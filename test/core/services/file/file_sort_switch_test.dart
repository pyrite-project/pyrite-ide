import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/models/settings.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/core/services/file/local_tree.dart';
import 'package:pyrite_ide/core/services/settings.dart';

void main() {
  late Directory temporaryDirectory;
  late ProviderContainer container;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'pyrite_file_sort_switch_test_',
    );
    for (final name in ['b.py', 'a.txt', 'c.py', 'z.md']) {
      await File(path.join(temporaryDirectory.path, name)).writeAsString('');
    }
    container = ProviderContainer();
    container.read(fileProvider.notifier).setDirectory(temporaryDirectory);
  });

  tearDown(() async {
    container.dispose();
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  List<String> rootNames() => container
      .read(localFileTreeViewControllerProvider)
      .roots
      .map((node) => node.data.name)
      .toList();

  test('switching the sort mode reorders the tree', () async {
    container.read(fileSortModeProvider.notifier).state = FileSortMode.byName;
    await container
        .read(localFileItemsProvider.notifier)
        .buildRootFileListItems();
    // ignore: avoid_print
    print('byName -> ${rootNames()}');

    container.read(fileSortModeProvider.notifier).state = FileSortMode.byType;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await container
        .read(localFileItemsProvider.notifier)
        .buildRootFileListItems();
    // ignore: avoid_print
    print('byType -> ${rootNames()}');
  });
}
