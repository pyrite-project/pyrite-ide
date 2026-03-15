import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/shared/toly_tree.dart';
import 'package:pyrite_ide/core/services/board_manager/main.dart';

final StateProvider<List<TreeNode<FileTreeItem>>> treeItems =
    StateProvider<List<TreeNode<FileTreeItem>>>((ref) => []);

class FileTreeItem {
  final String name;
  final IconData icon;
  final bool isDicrectory;

  const FileTreeItem({
    required this.name,
    required this.icon,
    this.isDicrectory = false,
  });
}

Future<String> _getFilesList(WidgetRef ref, {String path = "/"}) async {
  final completer = Completer<String>();
  String result = "";
  bool completed = false;

  void callback(Uint8List data) {
    if (completed) return;

    final decoded = utf8.decode(data);
    if (decoded.contains("\x04")) {
      completed = true;
      completer.complete(result);
      return;
    }
    result += decoded;
  }

  ref.read(serialDataCallbacks.notifier).state = [
    ...ref.read(serialDataCallbacks),
    callback,
  ];

  try {
    await enterRawRepl(ref);
    await Future.delayed(Duration(milliseconds: 50));

    sendCommand(ref, "\x04");
    await Future.delayed(Duration(milliseconds: 50));

    String command = "import uos\n";
    command += "try:\n";
    command += "  l=[]\n";
    command += "  for f in uos.ilistdir('$path'):\n";
    command +=
        '    l.append({"path": "${(path[path.length - 1] != '/') ? '$path/' : path}"+f[0], "name": f[0], "type": "folder" if f[1]==0x4000 else "file"})\n';
    command += "  print('!@#PyriteIDEStart#@!'+str(l)+'!@#PyriteIDEEnd#@!')\n";
    command += "except OSError:\n";
    command += "  print([])\n";

    sendCommand(ref, command);
    await Future.delayed(Duration(milliseconds: 100));

    sendCommand(ref, "\x04");

    final filesList = await completer.future.timeout(
      Duration(milliseconds: 300),
      onTimeout: () => result,
    );

    return filesList;
  } finally {
    completed = true;
    ref.read(serialDataCallbacks.notifier).state = ref
        .read(serialDataCallbacks)
        .where((cb) => cb != callback)
        .toList();

    await exitRawRepl(ref);
  }
}

Future<List<Map<String, String>>> getFilesList(
  WidgetRef ref, {
  String path = "/",
}) async {
  String originalData = await _getFilesList(ref, path: path);

  print(originalData);

  final String startIdentifier = "!@#PyriteIDEStart#@!";
  final String endIdentifier = "!@#PyriteIDEEnd#@!";

  final int startIdentifierIndex = originalData.indexOf(startIdentifier);
  final int endIdentifierIndex = originalData.indexOf(endIdentifier);

  final List<int> startIdentifierPosition = [
    startIdentifierIndex,
    startIdentifierIndex + startIdentifier.length,
  ];
  final List<int> endIdentifierPosition = [
    endIdentifierIndex,
    endIdentifierIndex + endIdentifier.length,
  ];

  String filesListString = originalData.substring(
    startIdentifierPosition[1],
    endIdentifierPosition[0],
  );

  filesListString = filesListString.replaceAll("'", '"');
  print(filesListString);

  return (jsonDecode(filesListString) as List)
      .cast<Map<String, dynamic>>()
      .map((map) => map.map((key, value) => MapEntry(key, value.toString())))
      .toList();
}

Future<List<TreeNode<FileTreeItem>>> buildFileListItems(
  WidgetRef ref,
  List<Map<String, String>> datas, {
  bool update = true,
}) async {
  List<TreeNode<FileTreeItem>> items = [];

  for (Map<String, String> data in datas) {
    if (data["type"] == "folder") {
      items.add(
        TreeNode(
          id: data["path"]!,
          data: FileTreeItem(
            name: data["name"]!,
            icon: Icons.folder,
            isDicrectory: true,
          ),
        ),
      );
      // print(data.path);
    } else {
      items.add(
        TreeNode(
          id: data["path"]!,
          data: FileTreeItem(name: data["name"]!, icon: Icons.file_open),
          isLeaf: false,
        ),
      );
    }
  }

  if (update) {
    ref.watch(treeItems.notifier).state = items;
  }

  return items;
}
