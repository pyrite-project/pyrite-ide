import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tolyui/tolyui.dart';

final StateProvider<Directory?> directory = StateProvider<Directory?>(
  (ref) => null,
);

final StateProvider<List<TreeNode<FileTreeItem>>> treeItems =
    StateProvider<List<TreeNode<FileTreeItem>>>((ref) => []);

class FileTreeItem {
  final String name;
  final IconData icon;

  const FileTreeItem({required this.name, required this.icon});
}

final StateProvider<Map<String, File>> openFilesMap =
    StateProvider<Map<String, File>>((ref) => {});

Future<String?> openFolder(WidgetRef ref) async {
  final String? path = await getDirectoryPath();
  if (path != null) {
    ref.watch(directory.notifier).state = Directory(path);
  }
  return path;
}

Future<List> getFilesList(WidgetRef ref, {String? path}) async {
  List datas;
  if (ref.read(directory) != null &&
      (path == null || path == ref.read(directory)!.path)) {
    datas = await ref.read(directory)!.list().toList();
    return datas;
  } else {
    if (path != null) {
      return Directory(path).list().toList();
    } else {
      return [];
    }
  }
}

Future<List<TreeNode<FileTreeItem>>> buildFileListItems(
  WidgetRef ref,
  List datas, {
  bool update = true,
}) async {
  List<TreeNode<FileTreeItem>> items = [];
  String pattern = "\\";

  if (Platform.isWindows) {
    pattern = "\\";
  } else {
    pattern = "/";
  }

  for (FileSystemEntity data in datas) {
    if (data is Directory) {
      items.add(
        TreeNode(
          id: data.path,
          data: FileTreeItem(
            name: data.path.split(pattern).last,
            icon: Icons.folder,
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
