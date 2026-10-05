import 'package:pyrite_ide/core/platform/pyrite_io.dart';

/// Native platforms use file_selector directly; these are never called.
Future<File?> openExternalFileIntoWorkspace() async => null;

Future<File?> createWorkspaceFileForSave() async => null;

Future<bool> saveTextToDisk(String content) async => false;
