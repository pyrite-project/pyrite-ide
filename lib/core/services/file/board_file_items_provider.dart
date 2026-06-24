import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/file/board_utils.dart';
import 'package:pyrite_ide/core/services/file/board_workspace_provider.dart';
import 'package:super_tree/super_tree.dart';

class BoardFileItemsNotifier
    extends StateNotifier<List<TreeNode<FileSystemItem>>> {
  final Ref ref;

  BoardFileItemsNotifier(this.ref) : super(const []);

  Future<List<Map<String, String>>> getFilesList({String path = "/"}) async {
    String command = "import uos\n";
    command += "try:\n";
    command += "  l=[]\n";
    command += "  for f in uos.ilistdir('$path'):\n";
    command +=
        '    l.append({"path": "${(path[path.length - 1] != '/') ? '$path/' : path}"+f[0], "name": f[0], "type": "folder" if f[1]==0x4000 else "file"})\n';
    command += "  import ujson\n";
    command +=
        "  print('!@#PyriteIDEStart#@!'+ujson.dumps(l)+'!@#PyriteIDEEnd#@!')\n";
    command += "except OSError:\n";
    command += "  print([])\n";

    debugPrint('[BoardWS] getFilesList command: $command');

    var originalData = await ref
        .read(boardWorkspaceProvider.notifier)
        .getCommandResult(command);

    debugPrint('[BoardWS] getFilesList result: $originalData');

    return (jsonDecode(originalData) as List)
        .cast<Map<String, dynamic>>()
        .map((map) => map.map((key, value) => MapEntry(key, value.toString())))
        .toList();
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
