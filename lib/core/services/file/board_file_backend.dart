import 'dart:typed_data';

enum BoardFileEntryType { file, folder }

class BoardFileEntry {
  final String path;
  final String name;
  final BoardFileEntryType type;

  const BoardFileEntry({
    required this.path,
    required this.name,
    required this.type,
  });

  bool get isFolder => type == BoardFileEntryType.folder;

  Map<String, String> toLegacyMap() {
    return {'path': path, 'name': name, 'type': isFolder ? 'folder' : 'file'};
  }
}

/// Filesystem operations for a connected MicroPython board.
///
/// All paths are board-side POSIX-style paths. UI and workspace code should
/// depend on this interface instead of knowing how the board transport works.
abstract class BoardFileBackend {
  /// Lists one directory without recursively expanding descendants.
  Future<List<BoardFileEntry>> listDirectory({String path = '/'});

  /// Lists every descendant below [path], including child folders and files.
  Future<List<BoardFileEntry>> listTree({String path = '/'});

  /// Reads a UTF-8 text file from the board.
  Future<String> readTextFile(String path);

  /// Reads raw file bytes from the board.
  Future<Uint8List> readFileBytes(String path);

  Future<int> getFileSize(String path);

  Future<Uint8List> readFileChunk(String path, int offset, int length);

  /// Writes a UTF-8 text file through a temporary board-side file.
  Future<void> writeTextFile(String path, String content);

  /// Writes raw file bytes through a temporary board-side file.
  Future<void> writeFileBytes(String path, List<int> bytes);

  Future<void> beginWriteFile(String path);

  Future<void> appendWriteFileChunk(String path, List<int> bytes);

  Future<void> finishWriteFile(String path);

  Future<void> deleteFile(String path);

  Future<void> deleteFolder(String path);

  Future<void> rename(String path, String newName);

  Future<void> move(String oldPath, String newPath);

  Future<void> createFolder(String path);
}

class BoardFileBackendException implements Exception {
  final String message;

  const BoardFileBackendException(this.message);

  @override
  String toString() => 'BoardFileBackendException: $message';
}

class BoardFileProtocolException extends BoardFileBackendException {
  const BoardFileProtocolException(super.message);

  @override
  String toString() => 'BoardFileProtocolException: $message';
}
