import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/shared/toly_tree.dart';

final StateProvider<Directory?> directory = StateProvider<Directory?>(
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

final StateProvider<Map<String, File>> openFilesMap =
    StateProvider<Map<String, File>>((ref) => {});

Future<Directory?> getDirectory(WidgetRef ref) async {
  final String? path = await getDirectoryPath();
  final Directory? dir;
  if (path != null) {
    dir = Directory(path);
    ref.watch(directory.notifier).state = dir;
    return dir;
  } else {
    return null;
  }
}

Future<File?> getFile() async {
  final XFile? file = await openFile();
  if (file != null) {
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
  if (ref.read(directory) != null &&
      (path == null || path == ref.read(directory)!.path)) {
    datas = ref.read(directory)!.list();
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
  if (update) {
    ref.watch(treeItems.notifier).state = items;
  }

  return items;
}

Future<File> getOpenFile(String path, WidgetRef ref) async {
  Map<String, File> map = ref.read(openFilesMap);
  if (map[path] == null) {
    map[path] = File(path);
  }
  return map[path]!;
}

Future<File?> createFile() async {
  FileSaveLocation? _path = await getSaveLocation();
  File? file;
  if (_path != null) {
    String path = _path.path;
    file = File(path);
    await file.create();
  } else {
    file = null;
  }
  return file;
}

Future<void> saveFile(File file, String content) async {
  await file.writeAsString(content);
}
