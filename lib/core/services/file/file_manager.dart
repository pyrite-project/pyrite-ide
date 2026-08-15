import 'dart:io';

import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as path;

enum FileManagerPlatform { windows, macos, linux, android, unsupported }

class FileManagerCommand {
  const FileManagerCommand({required this.executable, required this.arguments});

  final String executable;
  final List<String> arguments;
}

class FileManagerLaunchException implements Exception {
  const FileManagerLaunchException(this.message);

  final String message;

  @override
  String toString() => message;
}

FileManagerPlatform get currentFileManagerPlatform {
  if (Platform.isWindows) return FileManagerPlatform.windows;
  if (Platform.isMacOS) return FileManagerPlatform.macos;
  if (Platform.isLinux) return FileManagerPlatform.linux;
  if (Platform.isAndroid) return FileManagerPlatform.android;
  return FileManagerPlatform.unsupported;
}

String fileManagerDirectoryPath({
  required FileManagerPlatform platform,
  required String itemPath,
  required bool isDirectory,
}) {
  if (isDirectory) return itemPath;
  final context = platform == FileManagerPlatform.windows
      ? path.Context(style: path.Style.windows)
      : path.Context(style: path.Style.posix);
  return context.dirname(itemPath);
}

FileManagerCommand? fileManagerCommand({
  required FileManagerPlatform platform,
  required String itemPath,
  required bool isDirectory,
}) {
  switch (platform) {
    case FileManagerPlatform.windows:
      return FileManagerCommand(
        executable: 'explorer.exe',
        arguments: isDirectory ? [itemPath] : ['/select,', itemPath],
      );
    case FileManagerPlatform.macos:
      return FileManagerCommand(
        executable: 'open',
        arguments: isDirectory ? [itemPath] : ['-R', itemPath],
      );
    case FileManagerPlatform.linux:
      return FileManagerCommand(
        executable: 'xdg-open',
        arguments: [
          fileManagerDirectoryPath(
            platform: platform,
            itemPath: itemPath,
            isDirectory: isDirectory,
          ),
        ],
      );
    case FileManagerPlatform.android:
    case FileManagerPlatform.unsupported:
      return null;
  }
}

typedef FileManagerCommandRunner =
    Future<void> Function(FileManagerCommand command);
typedef AndroidFileManagerOpener = Future<bool> Function(String directoryPath);

class FileManagerLauncher {
  FileManagerLauncher({
    FileManagerPlatform? platform,
    FileManagerCommandRunner? commandRunner,
    AndroidFileManagerOpener? androidFileManagerOpener,
  }) : _platform = platform ?? currentFileManagerPlatform,
       _commandRunner = commandRunner ?? _startCommand,
       _androidFileManagerOpener =
           androidFileManagerOpener ?? _openAndroidDirectory;

  final FileManagerPlatform _platform;
  final FileManagerCommandRunner _commandRunner;
  final AndroidFileManagerOpener _androidFileManagerOpener;

  Future<void> open(String itemPath, {required bool isDirectory}) async {
    final command = fileManagerCommand(
      platform: _platform,
      itemPath: itemPath,
      isDirectory: isDirectory,
    );
    if (command != null) {
      await _commandRunner(command);
      return;
    }

    if (_platform == FileManagerPlatform.android) {
      final directoryPath = fileManagerDirectoryPath(
        platform: _platform,
        itemPath: itemPath,
        isDirectory: isDirectory,
      );
      if (await _androidFileManagerOpener(directoryPath)) return;
      throw const FileManagerLaunchException('Unable to open file manager.');
    }

    throw const FileManagerLaunchException(
      'The system file manager is not supported on this platform.',
    );
  }

  static Future<void> _startCommand(FileManagerCommand command) async {
    await Process.start(command.executable, command.arguments);
  }

  static Future<bool> _openAndroidDirectory(String directoryPath) async {
    final result = await OpenFile.open(directoryPath);
    return result.type == ResultType.done;
  }
}

final systemFileManager = FileManagerLauncher();
