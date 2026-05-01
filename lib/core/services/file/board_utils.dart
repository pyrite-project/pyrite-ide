import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pyrite_ide/core/models/file.dart';
import 'package:pyrite_ide/shared/toly_tree.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

Future<List<TreeNode<BoardFileTreeItem>>> buildFileListItems(
  List<Map<String, String>> datas,
) async {
  List<TreeNode<BoardFileTreeItem>> items = [];
  // print("debug: buildFileListItems with datas $datas");
  for (Map<String, String> data in datas) {
    if (data["type"] == "folder") {
      items.add(
        TreeNode(
          id: data["path"]!,
          data: BoardFileTreeItem(
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
          data: BoardFileTreeItem(name: data["name"]!, icon: Icons.file_open),
          isLeaf: false,
        ),
      );
    }
  }

  return items;
}

Future<File> getLocalFilePath(TreeNode<BoardFileTreeItem> node) async {
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

  return file;
}
