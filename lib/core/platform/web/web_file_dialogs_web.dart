/// File System Access API implementations of the native file dialogs.
///
/// * Open file — the browser file picker returns bytes; they are copied into
///   the mounted workspace (or the app-support uploads folder) so the editor
///   can read and save them like any workspace file.
/// * New file (save target) — a uniquely named file inside the workspace.
/// * Save to disk — `showSaveFilePicker` streams the text to a real file on
///   the user's machine (browser download).
library;

import 'dart:convert';
import 'dart:js_interop';

import 'package:file_selector/file_selector.dart';
import 'package:pyrite_ide/core/platform/pyrite_io.dart';
import 'package:pyrite_ide/core/platform/web/web_fs_backend.dart';
import 'package:web/web.dart' as web;

extension type _SaveFileOptions._(JSObject _) implements JSObject {
  external factory _SaveFileOptions({JSString? suggestedName});
}

extension WindowSavePicker on web.Window {
  external JSPromise<web.FileSystemFileHandle> showSaveFilePicker([
    _SaveFileOptions? options,
  ]);
}

/// Opens a file with the browser picker and copies it into the virtual
/// filesystem so it can be opened and saved by the editor.
Future<File?> openExternalFileIntoWorkspace() async {
  final files = await openFile();
  if (files == null) return null;
  final bytes = await files.readAsBytes();
  final name = files.name.isEmpty ? 'untitled.txt' : files.name;
  final target = await _incomingFilePath(name);
  await WebFs.instance.createFile(target, recursive: true);
  await WebFs.instance.writeFileBytes(target, bytes);
  return File(target);
}

/// Creates a uniquely named file in the workspace as the target of
/// "new file" / "save as" on the web.
Future<File?> createWorkspaceFileForSave() async {
  final target = await _incomingFilePath('untitled.py');
  final unique = await _uniquePath(target);
  await WebFs.instance.createFile(unique, recursive: true);
  return File(unique);
}

/// Saves [content] to a real file on the user's machine through
/// `showSaveFilePicker` (browser download flow).
Future<bool> saveTextToDisk(String content) async {
  try {
    final handle = await web.window
        .showSaveFilePicker(
          _SaveFileOptions(suggestedName: 'untitled.py'.toJS),
        )
        .toDart;
    final writable = await handle.createWritable().toDart;
    await writable
        .write(const Utf8Encoder().convert(content).toJS)
        .toDart;
    await writable.close().toDart;
    return true;
  } catch (_) {
    return false;
  }
}

/// Workspace root when one is mounted, otherwise the app-support uploads
/// directory.
Future<String> _incomingFilePath(String name) async {
  final label = WebFs.instance.workspaceLabel;
  if (label != null) return '/$label/$name';
  const uploads = '/.pyrite_ide/uploads';
  await WebFs.instance.createDirectory(uploads, recursive: true);
  return '$uploads/$name';
}

Future<String> _uniquePath(String desired) async {
  if (!await WebFs.instance.fileExists(desired)) return desired;
  final dot = desired.lastIndexOf('.');
  final base = dot <= 0 ? desired : desired.substring(0, dot);
  final ext = dot <= 0 ? '' : desired.substring(dot);
  for (var attempt = 1; attempt < 1000; attempt++) {
    final candidate = '$base ($attempt)$ext';
    if (!await WebFs.instance.fileExists(candidate)) return candidate;
  }
  return desired;
}
