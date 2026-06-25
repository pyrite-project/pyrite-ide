import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/file/board_file_backend_provider.dart';
import 'package:pyrite_ide/core/services/file/board_utils.dart';
import 'package:super_tree/super_tree.dart';

class BoardFileItemsNotifier
    extends StateNotifier<List<TreeNode<FileSystemItem>>> {
  final Ref ref;

  BoardFileItemsNotifier(this.ref) : super(const []);

  Future<List<Map<String, String>>> getFilesList({String path = "/"}) async {
    final entries = await ref
        .read(boardFileBackendProvider)
        .listDirectory(path: path);
    return entries.map((entry) => entry.toLegacyMap()).toList();
  }

  Future<List<TreeNode<FileSystemItem>>> buildRootFileListItems() async {
    List<TreeNode<FileSystemItem>> items = await buildFileListItems(
      await getFilesList(),
    );
    state = items;

    return items;
  }

  void clear() {
    state = const [];
  }
}

final StateNotifierProvider<
  BoardFileItemsNotifier,
  List<TreeNode<FileSystemItem>>
>
boardFileItemsProvider = StateNotifierProvider(
  (ref) => BoardFileItemsNotifier(ref),
);
