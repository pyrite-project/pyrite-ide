import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/file/git_ignore_filter.dart';

export 'package:pyrite_ide/core/services/file/git_ignore_filter.dart'
    show gitIgnoredPaths;
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/platform/pyrite_io.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/core/services/file/file_rename.dart';
import 'package:super_tree/super_tree.dart';

// ---------------------------------------------------------------------------
// Local workspace provider (alias)
// ---------------------------------------------------------------------------

final ProviderListenable<Directory?> localWorkspaceProvider = fileProvider;

// ---------------------------------------------------------------------------
// Git-aware tree item types
// ---------------------------------------------------------------------------

class LocalFolderItem extends FolderItem {
  LocalFolderItem(super.name, {this.isGitIgnored = false});

  final bool isGitIgnored;
}

class LocalFileItem extends FileItem {
  LocalFileItem(super.name, {this.isGitIgnored = false});

  final bool isGitIgnored;
}

bool isGitIgnoredItem(FileSystemItem item) {
  return switch (item) {
    LocalFolderItem(:final isGitIgnored) => isGitIgnored,
    LocalFileItem(:final isGitIgnored) => isGitIgnored,
    _ => false,
  };
}

// ---------------------------------------------------------------------------
// Tree building
// ---------------------------------------------------------------------------

String getPattern() {
  if (Platform.isWindows) {
    return "\\";
  }
  return "/";
}

Future<List<TreeNode<FileSystemItem>>> buildFileListItems(
  Stream<FileSystemEntity> datas,
) async {
  final entities = <FileSystemEntity>[];
  final items = <TreeNode<FileSystemItem>>[];
  final pattern = getPattern();

  try {
    await for (final data in datas) {
      entities.add(data);
    }
  } on FileSystemException {
    // Ignore: macOS sandbox/file permissions may deny some paths.
  }

  final ignoredPaths = await gitIgnoredPaths(entities.map((data) => data.path));
  for (final data in entities) {
    final isIgnored = ignoredPaths.contains(path.normalize(data.path));
    if (data is Directory) {
      items.add(
        TreeNode(
          id: data.path,
          data: LocalFolderItem(
            data.path.split(pattern).last,
            isGitIgnored: isIgnored,
          ),
          canLoadChildren: true,
        ),
      );
    } else {
      items.add(
        TreeNode(
          id: data.path,
          data: LocalFileItem(
            data.path.split(pattern).last,
            isGitIgnored: isIgnored,
          ),
        ),
      );
    }
  }

  return items;
}

// ---------------------------------------------------------------------------
// Git ignore support
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// System file dialogs
// ---------------------------------------------------------------------------

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
  } else {
    file = null;
  }
  return file;
}

Future<bool> sysSaveAs(String content) async {
  FileSaveLocation? path0 = await getSaveLocation();
  if (path0 != null) {
    String path = path0.path;
    final file = File(path);
    await file.create();
    file.writeAsString(content);
    return true;
  }
  return false;
}

// ---------------------------------------------------------------------------
// Basic file operations
// ---------------------------------------------------------------------------

Future<Stream<FileSystemEntity>> getFileList(String path) async {
  return Directory(path).list();
}

Future<String> renameDir(String sourcePath, String newName) async {
  final targetPath = renamedLocalSiblingPath(sourcePath, newName);
  await _ensureRenameTargetAvailable(sourcePath, targetPath);
  if (path.normalize(sourcePath) != path.normalize(targetPath)) {
    await Directory(sourcePath).rename(targetPath);
  }
  return targetPath;
}

Future<String> renameFile(String sourcePath, String newName) async {
  final targetPath = renamedLocalSiblingPath(sourcePath, newName);
  await _ensureRenameTargetAvailable(sourcePath, targetPath);
  if (path.normalize(sourcePath) != path.normalize(targetPath)) {
    await File(sourcePath).rename(targetPath);
  }
  return targetPath;
}

Future<void> _ensureRenameTargetAvailable(
  String sourcePath,
  String targetPath,
) async {
  if (path.equals(sourcePath, targetPath)) return;
  final targetType = await FileSystemEntity.type(
    targetPath,
    followLinks: false,
  );
  if (targetType != FileSystemEntityType.notFound) {
    throw FileRenameTargetExistsException(targetPath);
  }
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
  final file = File(path);
  return await file.readAsString();
}

// ---------------------------------------------------------------------------
// Unique name generators
// ---------------------------------------------------------------------------

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
