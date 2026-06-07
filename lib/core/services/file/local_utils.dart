import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as path;
import 'package:super_tree/super_tree.dart';

String getPattern() {
  final String pattern;
  if (Platform.isWindows) {
    pattern = "\\";
  } else {
    pattern = "/";
  }

  return pattern;
}

Future<List<TreeNode<FileSystemItem>>> buildFileListItems(
  Stream<FileSystemEntity> datas,
) async {
  List<TreeNode<FileSystemItem>> items = [];
  String pattern = getPattern();

  try {
    await for (FileSystemEntity data in datas) {
      if (data is Directory) {
        items.add(
          TreeNode(
            id: data.path,
            data: FolderItem(data.path.split(pattern).last),
            canLoadChildren: true,
          ),
        );
        // print(data.path);
      } else {
        items.add(
          TreeNode(
            id: data.path,
            data: FileItem(data.path.split(pattern).last),
          ),
        );
      }
    }
  } on FileSystemException {
    // Ignore: macOS sandbox/file permissions may deny some paths.
  }

  return items;
}

Future<File?> sysGetFile() async {
  final XFile? file = await openFile();
  if (file != null) {
    return File(file.path);
  } else {
    return null;
  }
}

Future<File?> sysCreateFile() async {
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

void writeFile(String path, String content) async {
  final File file = File(path);
  await file.writeAsString(content);
}

Future<bool> sysSaveAs(String content) async {
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

Future<void> renameDir(String path, String newName) async {
  final directory = Directory(path);
  final newPath0 = path.split(getPattern());
  newPath0.last = newName;
  final newPath = newPath0.join(getPattern());
  await directory.rename(newPath);
}

Future<void> renameFile(String path, String newName) async {
  final file = File(path);
  final newPath0 = path.split(getPattern());
  newPath0.last = newName;
  final newPath = newPath0.join(getPattern());
  await file.rename(newPath);
}

Future<void> deleteDir(String path) async {
  final directory = Directory(path);
  await directory.delete(recursive: true);
}

Future<void> deleteFile(String path) async {
  final file = File(path);
  await file.delete();
}

Future<String> getFileContent(String path) async {
  final File file = File(path);
  return await file.readAsString();
}

Future<String> createFileWithUniqueName(String desiredPath) async {
  final uniquePath = await getUniqueFilePath(desiredPath);

  final directory = path.dirname(uniquePath);
  await Directory(directory).create(recursive: true);

  final file = File(uniquePath);
  await file.create();

  return uniquePath;
}

Future<String> getUniqueFilePath(
  String originalPath, {
  int maxAttempts = 10000,
}) async {
  // 先检查原始路径是否可用
  if (!await File(originalPath).exists()) {
    return originalPath;
  }

  final directory = path.dirname(originalPath);
  final basename = path.basenameWithoutExtension(originalPath);
  final extension = path.extension(originalPath);

  int attempt = 1;
  while (attempt <= maxAttempts) {
    final candidatePath = path.join(
      directory,
      '$basename ($attempt)$extension',
    );
    if (!await File(candidatePath).exists()) {
      return candidatePath;
    }
    attempt++;
  }

  throw Exception('无法生成唯一文件名，已达最大尝试次数 ($maxAttempts)');
}

Future<String> getUniqueFolderPath(
  String desiredPath, {
  int maxAttempts = 10000,
}) async {
  if (!await Directory(desiredPath).exists()) {
    return desiredPath;
  }
  final dir = path.dirname(desiredPath);
  final basename = path.basename(desiredPath);
  int attempt = 1;
  while (attempt <= maxAttempts) {
    final candidate = path.join(dir, '$basename ($attempt)');
    if (!await Directory(candidate).exists()) {
      return candidate;
    }
    attempt++;
  }
  throw Exception('无法生成唯一文件夹名，已达最大尝试次数 $maxAttempts');
}

Future<String> createFolderWithUniqueName(String desiredPath) async {
  final uniquePath = await getUniqueFolderPath(desiredPath);
  final parentDir = path.dirname(uniquePath);
  await Directory(parentDir).create(recursive: true);
  await Directory(uniquePath).create();
  return uniquePath;
}
