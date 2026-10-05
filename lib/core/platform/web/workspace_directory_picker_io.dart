/// Native platforms open a directory through `file_selector` instead of the
/// browser's File System Access API, so this is never called.
Future<String?> pickWorkspaceDirectory() async => null;