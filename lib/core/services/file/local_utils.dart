import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:pyrite_ide/core/models/file.dart';
import 'package:pyrite_ide/shared/toly_tree.dart';

Future<List<TreeNode<LocalFileTreeItem>>> buildFileListItems(
  Stream<FileSystemEntity> datas,
) async {
  List<TreeNode<LocalFileTreeItem>> items = [];
  String pattern;

  if (Platform.isWindows) {
    pattern = "\\";
  } else {
    pattern = "/";
  }

  try {
    await for (FileSystemEntity data in datas) {
      if (data is Directory) {
        items.add(
          TreeNode(
            id: data.path,
            data: LocalFileTreeItem(
              name: data.path.split(pattern).last,
              icon: Icons.folder,
              isDicrectory: true,
            ),
          ),
        );
        // print(data.path);
      } else {
        items.add(
          TreeNode(
            id: data.path,
            data: LocalFileTreeItem(
              name: data.path.split(pattern).last,
              icon: Icons.file_open,
            ),
            isLeaf: false,
          ),
        );
      }
    }
  } on FileSystemException {
    // Ignore: macOS sandbox/file permissions may deny some paths.
  }

  return items;
}

Future<File?> getFile() async {
  final XFile? file = await openFile();
  if (file != null) {
    return File(file.path);
  } else {
    return null;
  }
}

Future<File?> createFile() async {
  FileSaveLocation? path0 = await getSaveLocation();
  File? file;
  if (path0 != null) {
    String path = path0.path;
    file = File(path);
    await file.create();
    // openFilesisSavedMap[file.path] = StateProvider<bool>((ref) => true);
  } else {
    file = null;
  }
  return file;
}

void saveLocalFile(File file, String content) async {
  await file.writeAsString(content);
}

Future<bool> saveAs(String content) async {
  FileSaveLocation? path0 = await getSaveLocation();
  File? file;
  if (path0 != null) {
    String path = path0.path;
    file = File(path);
    await file.create();
    file.writeAsString(content);
    return true;
  } else {
    file = null;
    return false;
  }
}

Future<Stream<FileSystemEntity>> getFilesList(String path) async {
  return Directory(path).list();
}
