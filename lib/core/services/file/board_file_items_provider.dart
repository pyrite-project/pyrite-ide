import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/file/board_file_backend_provider.dart';
import 'package:pyrite_ide/core/services/file/board_utils.dart';
import 'package:pyrite_ide/core/services/file/board_workspace_provider.dart';
import 'package:super_tree/super_tree.dart';

class BoardFileItemsNotifier
    extends StateNotifier<List<TreeNode<FileSystemItem>>> {
  final Ref ref;

  BoardFileItemsNotifier(this.ref) : super(const []);

  Future<List<TreeNode<FileSystemItem>>> buildRootFileListItems() async {
    List<TreeNode<FileSystemItem>> items = await buildFileListItems(
      await ref.read(boardWorkspaceProvider.notifier).getFileList(),
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
