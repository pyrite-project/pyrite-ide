import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/services/file/board_file_backend.dart';
import 'package:super_tree/super_tree.dart';

Future<List<TreeNode<FileSystemItem>>> buildFileListItems(
  List<BoardFileEntry> entries,
) async {
  List<TreeNode<FileSystemItem>> items = [];
  for (final entry in entries) {
    if (entry.isFolder) {
      items.add(
        TreeNode(
          id: entry.path,
          data: FolderItem(entry.name),
          canLoadChildren: true,
        ),
      );
    } else {
      items.add(TreeNode(id: entry.path, data: FileItem(entry.name)));
    }
  }

  return items;
}

Future<File> getLocalFile(String boardFilePath) async {
  final supportDir = path.join(
    (await getApplicationSupportDirectory()).path,
    "temporary_board_files",
  );
  final relativePath = boardFilePath.split("/").skip(1).join("/");
  final file = File(path.join(supportDir, relativePath));
  await file.create(recursive: true, exclusive: false);
  return file;
}
