import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/file/board_utils.dart';
import 'package:pyrite_ide/core/services/file/board_provider.dart';
import 'package:super_tree/super_tree.dart';

class BoardFileItemsNotifier
    extends StateNotifier<List<TreeNode<FileSystemItem>>> {
  final Ref ref;

  BoardFileItemsNotifier(this.ref) : super(const []);

  Future<List<TreeNode<FileSystemItem>>> buildRootFileListItems() async {
    final entries = await ref.read(boardProvider.notifier).getFileList();
    List<TreeNode<FileSystemItem>> items = await buildFileListItems(entries);
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
