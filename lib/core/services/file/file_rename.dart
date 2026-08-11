import 'package:path/path.dart' as path;

final _boardPath = path.Context(style: path.Style.posix);

class FileRenameTargetExistsException implements Exception {
  const FileRenameTargetExistsException(this.targetPath);

  final String targetPath;

  @override
  String toString() => 'Rename target already exists: $targetPath';
}

String renamedLocalSiblingPath(String sourcePath, String newName) {
  return path.join(path.dirname(sourcePath), newName);
}

String renamedBoardSiblingPath(String sourcePath, String newName) {
  final parent = _boardPath.dirname(sourcePath);
  return parent == '/' ? '/$newName' : _boardPath.join(parent, newName);
}

String? rebaseLocalPath(
  String candidatePath, {
  required String oldRoot,
  required String newRoot,
}) {
  if (path.equals(candidatePath, oldRoot)) return newRoot;
  if (!path.isWithin(oldRoot, candidatePath)) return null;
  return path.join(newRoot, path.relative(candidatePath, from: oldRoot));
}

String? rebaseBoardPath(
  String candidatePath, {
  required String oldRoot,
  required String newRoot,
}) {
  if (_boardPath.equals(candidatePath, oldRoot)) return newRoot;
  if (!_boardPath.isWithin(oldRoot, candidatePath)) return null;
  return _boardPath.join(
    newRoot,
    _boardPath.relative(candidatePath, from: oldRoot),
  );
}

String rebaseBoardCachePath({
  required String oldCachePath,
  required String oldBoardPath,
  required String newBoardPath,
}) {
  final oldSegments = _boardPath
      .split(_boardPath.normalize(oldBoardPath))
      .where((segment) => segment != '/')
      .toList(growable: false);
  var cacheRoot = oldCachePath;
  for (var index = 0; index < oldSegments.length; index++) {
    cacheRoot = path.dirname(cacheRoot);
  }

  final newSegments = _boardPath
      .split(_boardPath.normalize(newBoardPath))
      .where((segment) => segment != '/')
      .toList(growable: false);
  return path.joinAll([cacheRoot, ...newSegments]);
}
