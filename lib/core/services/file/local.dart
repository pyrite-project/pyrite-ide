import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/shared/toly_tree.dart';

final StateProvider<Directory?> rootDirectory = StateProvider<Directory?>(
  (ref) => null,
);
final StateProvider<String?> selectedPath = StateProvider<String?>(
  (ref) => null,
);

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

final Map<String, File> openFilesMap = {};

final Map<String, StateProvider<bool>> openFilesisSavedMap = {};

Future<Directory?> getDirectory(WidgetRef ref) async {
  final String? path = await getDirectoryPath();
  final Directory? dir;
  if (path != null) {
    dir = Directory(path);
    ref.watch(rootDirectory.notifier).state = dir;
    return dir;
  } else {
    return null;
  }
}

Future<File?> getFile() async {
  final XFile? file = await openFile();
  if (file != null) {
    openFilesisSavedMap[file.path] = StateProvider<bool>((ref) => true);
    return File(file.path);
  } else {
    return null;
  }
}

Future<Stream<FileSystemEntity>> getFilesList(
  WidgetRef ref, {
  String? path,
}) async {
  Stream<FileSystemEntity> datas;
  if (ref.read(rootDirectory) != null &&
      (path == null || path == ref.read(rootDirectory)!.path)) {
    datas = ref.read(rootDirectory)!.list();
  } else {
    if (path != null) {
      datas = Directory(path).list();
    } else {
      datas = Stream.empty();
    }
  }
  return datas;
}

Future<List<TreeNode<FileTreeItem>>> buildFileListItems(
  WidgetRef ref,
  Stream<FileSystemEntity> datas, {
  bool update = true,
}) async {
  List<TreeNode<FileTreeItem>> items = [];
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
            data: FileTreeItem(
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
            data: FileTreeItem(
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
  if (update) {
    ref.watch(treeItems.notifier).state = items;
  }

  return items;
}

Future<File> getOpenFile(String path, WidgetRef ref) async {
  Map<String, File> map = openFilesMap;
  if (map[path] == null) {
    map[path] = File(path);
  }
  return map[path]!;
}

Future<File?> createFile() async {
  FileSaveLocation? path0 = await getSaveLocation();
  File? file;
  if (path0 != null) {
    String path = path0.path;
    file = File(path);
    await file.create();
    openFilesisSavedMap[file.path] = StateProvider<bool>((ref) => true);
  } else {
    file = null;
  }
  return file;
}

void saveFile(File file, String content) async {
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
