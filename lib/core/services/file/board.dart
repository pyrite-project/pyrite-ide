import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/shared/toly_tree.dart';
import 'package:pyrite_ide/core/services/board_manager/main.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

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

Future<String> _getCommandResult(WidgetRef ref, {required String command}) async {
  final completer = Completer<String>();
  String result = "";
  bool completed = false;

  void callback(Uint8List data) {
    if (completed) return;

    final decoded = utf8.decode(data);
    print("Received chunk: $decoded");
    result += decoded;
    if (decoded.contains("!@#PyriteIDEEnd#@!")) {
      print("Full data received, length: ${result.length}");
      completed = true;
      completer.complete(result);

      // 移除当前callback
      ref.read(serialDataCallbacks.notifier).state = ref
          .read(serialDataCallbacks)
          .where((cb) => cb != callback)
          .toList();
    }
  }

  ref.read(serialDataCallbacks.notifier).state = [
    ...ref.read(serialDataCallbacks),
    callback,
  ];

  try {
    enterRawRepl(ref);
    await Future.delayed(Duration(milliseconds: 50));

    sendCommand(ref, "\x04");
    await Future.delayed(Duration(milliseconds: 50));

    sendCommand(ref, command);
    await Future.delayed(Duration(milliseconds: 100));

    sendCommand(ref, "\x04");

    final res = await completer.future.timeout(
      Duration(milliseconds: 10000),
      onTimeout: () => result,
    );

    return res;
  } finally {
    completed = true;
    ref.read(serialDataCallbacks.notifier).state = ref
        .read(serialDataCallbacks)
        .where((cb) => cb != callback)
        .toList();

    exitRawRepl(ref);
  }
}

Future<String> getCommandResult(
  WidgetRef ref, {
  required String command,
}) async {
  String originalData = await _getCommandResult(ref, command: command);

  // print(originalData);

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

  String resultString = originalData.substring(
    startIdentifierPosition[1],
    endIdentifierPosition[0],
  );
  // print(resultString);

  return resultString;
}

Future<List<Map<String, String>>> getFilesList(
  WidgetRef ref, {
  String path = "/",
}) async {
  String command = "import uos\n";
  command += "try:\n";
  command += "  l=[]\n";
  command += "  for f in uos.ilistdir('$path'):\n";
  command +=
      '    l.append({"path": "${(path[path.length - 1] != '/') ? '$path/' : path}"+f[0], "name": f[0], "type": "folder" if f[1]==0x4000 else "file"})\n';
  command += "  print('!@#PyriteIDEStart#@!'+str(l)+'!@#PyriteIDEEnd#@!')\n";
  command += "except OSError:\n";
  command += "  print([])\n";
  var originalData = await getCommandResult(ref, command: command);
  return (jsonDecode(originalData.replaceAll("'", "\"")) as List)
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
  print("debug: buildFileListItems with datas $datas");
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

Future<String> getFileContent(
  WidgetRef ref, {
  required String path,
}) async {
  String command = "try:\n";
  command += "  with open('$path', 'r') as f:\n";
  command += "    print('!@#PyriteIDEStart#@!'+f.read()+'!@#PyriteIDEEnd#@!')\n";
  command += "except Exception as e:\n";
  command += "  print('$path', e)\n";
  String contentString = await _getCommandResult(ref, command: command);
  String resultString = contentString.split("!@#PyriteIDEStart#@!")[1].split("!@#PyriteIDEEnd#@!")[0];
  return resultString;
}

Future<File> getFileName(TreeNode<FileTreeItem> node) async {
  final supportDir = await getApplicationSupportDirectory();
  print("debug: appSupportDir ${supportDir.path}");
  List<String> fileNameList = node.id.split("/");
  String fileNameResult = "";
  for (int i = 1; i < fileNameList.length; i++) {
    fileNameResult = path.join(fileNameResult, fileNameList[i]);
  }
  File file = File(path.join(supportDir.path, fileNameResult));
  file.create(recursive: true, exclusive: false);
  print("debug: open board file ${file.path}");

  return File(fileNameResult);
}