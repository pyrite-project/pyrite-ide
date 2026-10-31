import 'package:path/path.dart' as p;

/// The device directory a run should execute from, or null to keep whatever
/// working directory the device already has.
///
/// Device-side files carry their own absolute path, so that path's parent is
/// used directly. Workspace files follow the board-sync convention that maps
/// the workspace root onto the device root (`/`), so the file's directory
/// relative to the workspace becomes its device directory — a workspace file
/// at the root level maps to `/` and needs no switch.
String? resolveDeviceRunWorkingDirectory({
  bool? isBoardFile,
  String? boardFilePath,
  String? localFilePath,
  String? workspaceRootPath,
}) {
  if (isBoardFile == true &&
      boardFilePath != null &&
      boardFilePath.isNotEmpty) {
    final devicePath = boardFilePath.startsWith('/')
        ? boardFilePath
        : '/$boardFilePath';
    final directory = p.posix.dirname(devicePath);
    return directory == '/' ? null : directory;
  }

  final file = localFilePath;
  final root = workspaceRootPath;
  if (file == null ||
      file.isEmpty ||
      root == null ||
      root.isEmpty ||
      !p.isWithin(root, file)) {
    return null;
  }
  // The relative path uses the host's separators; the device always wants
  // POSIX ones.
  final parent = p.dirname(p.relative(file, from: root));
  if (parent == '.' || parent.isEmpty) return null;
  final directory = p.posix.joinAll(['/', ...p.split(parent)]);
  return directory == '/' ? null : directory;
}
