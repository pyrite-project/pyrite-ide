import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:super_tree/super_tree.dart';

Future<List<TreeNode<FileSystemItem>>> buildFileListItems(
  List<Map<String, String>> datas,
) async {
  List<TreeNode<FileSystemItem>> items = [];
  // print("debug: buildFileListItems with datas $datas");
  for (Map<String, String> data in datas) {
    if (data["type"] == "folder") {
      items.add(
        TreeNode(
          id: data["path"]!,
          data: FolderItem(data["name"]!),
          canLoadChildren: true,
        ),
      );
      // print(data.path);
    } else {
      items.add(TreeNode(id: data["path"]!, data: FileItem(data["name"]!)));
    }
  }

  return items;
}

Future<File> getLocalFilePath(TreeNode<FileSystemItem> node) async {
  final supportDir = await getApplicationSupportDirectory();
  debugPrint("debug: appSupportDir ${supportDir.path}");
  List<String> fileNameList = node.id.split("/");
  String fileNameResult = "";
  for (int i = 1; i < fileNameList.length; i++) {
    fileNameResult = path.join(fileNameResult, fileNameList[i]);
  }
  File file = File(path.join(supportDir.path, fileNameResult));
  await file.create(recursive: true, exclusive: false);
  debugPrint("debug: open board file ${file.path}");

  return file;
}
