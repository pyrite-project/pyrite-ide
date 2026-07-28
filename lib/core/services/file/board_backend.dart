import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/file/file_ops.dart';
import 'package:pyrite_ide/core/services/serial/device_executor.dart';
import 'package:pyrite_ide/core/services/serial/repl_mode_provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:super_tree/super_tree.dart';

// ---------------------------------------------------------------------------
// Wire codec
// ---------------------------------------------------------------------------

String encodeBoardFileText(String value) => base64.encode(utf8.encode(value));

String decodeBoardFileText(String value) {
  return utf8.decode(base64.decode(value));
}

String encodeBoardFileBytes(List<int> value) => base64.encode(value);

Uint8List decodeBoardFileBytes(String value) => base64.decode(value);

String boardFileTextExpression(String value) {
  return '_decode_text(${jsonEncode(encodeBoardFileText(value))})';
}

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

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
}

// ---------------------------------------------------------------------------
// Abstract interface
// ---------------------------------------------------------------------------

abstract class BoardFileBackend {
  Future<List<BoardFileEntry>> listDirectory({String path = '/'});
  Future<List<BoardFileEntry>> listTree({String path = '/'});
  Future<String> readTextFile(String path);
  Future<Uint8List> readFileBytes(String path);
  Future<int> getFileSize(String path);
  Future<Uint8List> readFileChunk(String path, int offset, int length);
  Future<void> writeTextFile(String path, String content);
  Future<void> writeFileBytes(
    String path,
    List<int> bytes, {
    void Function(int sent, int total)? onProgress,
  });
  Future<void> deleteFile(String path);
  Future<void> deleteFolder(String path);
  Future<void> rename(String path, String newName);
  Future<void> move(String oldPath, String newPath);
  Future<void> createFolder(String path);
  Future<void> pathExists(String path);
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

// ---------------------------------------------------------------------------
// Serial implementation
// ---------------------------------------------------------------------------

class SerialBoardFileBackend implements BoardFileBackend {
  static const _resultMarker = '__PYRITE_BOARD_FILE_RESULT__';
  static const _writeReadyMarker = 'PYRITE_WRITE_READY';
  static const _writeDoneMarker = 'PYRITE_WRITE_DONE';
  static const _longTimeout = Duration(seconds: 60);
  static const _rawWriteChunkSize = 4096;
  static const _rawWriteAckEvery = 8;

  static final _boardPath = path.Context(style: path.Style.posix);

  final Ref ref;

  SerialBoardFileBackend(this.ref);

  @override
  Future<List<BoardFileEntry>> listDirectory({String path = '/'}) async {
    final value = await _runJsonValue(
      _wrapSimplePython('''
base = ${boardFileTextExpression(path)}
if base != '/' and base.endswith('/'):
  base = base[:-1]
items = []
for entry in os.ilistdir(base):
  name = entry[0]
  mode = entry[1] if len(entry) > 1 else 0
  item_path = '/' + name if base == '/' else base + '/' + name
  is_dir = bool(mode & 0x4000) if mode else False
  items.append({
    'path_b64': _encode_text(item_path),
    'name_b64': _encode_text(name),
    'type': 'folder' if is_dir else 'file',
  })
_emit_ok(items)
'''),
    );
    return _parseEntries(value);
  }

  @override
  Future<List<BoardFileEntry>> listTree({String path = '/'}) async {
    final value = await _runJsonValue(
      _wrapSimplePython('''
base = ${boardFileTextExpression(path)}
if base != '/' and base.endswith('/'):
  base = base[:-1]

def walk(base_path):
  result = []
  for entry in os.ilistdir(base_path):
    name = entry[0]
    mode = entry[1] if len(entry) > 1 else 0
    item_path = '/' + name if base_path == '/' else base_path + '/' + name
    is_dir = bool(mode & 0x4000) if mode else False
    result.append({
      'path_b64': _encode_text(item_path),
      'name_b64': _encode_text(name),
      'type': 'folder' if is_dir else 'file',
    })
    if is_dir:
      result.extend(walk(item_path))
  return result

_emit_ok(walk(base))
'''),
      timeout: _longTimeout,
    );
    return _parseEntries(value);
  }

  @override
  Future<String> readTextFile(String path) async {
    return utf8.decode(await readFileBytes(path));
  }

  @override
  Future<Uint8List> readFileBytes(String path) async {
    final value = await _runJsonValue(
      _wrapSimplePython('''
target = ${boardFileTextExpression(path)}
with open(target, 'rb') as f:
  data = f.read()
encoded = ubinascii.b2a_base64(data).decode().strip()
_emit_ok(encoded)
'''),
      timeout: _longTimeout,
    );
    if (value is! String) {
      throw const BoardFileProtocolException('Read response is not a string');
    }
    return decodeBoardFileBytes(value);
  }

  @override
  Future<int> getFileSize(String path) async {
    final value = await _runJsonValue(
      _wrapSimplePython('''
target = ${boardFileTextExpression(path)}
_emit_ok(os.stat(target)[6])
'''),
    );
    if (value is int) return value;
    if (value is num) return value.toInt();
    throw const BoardFileProtocolException(
      'File size response is not a number',
    );
  }

  @override
  Future<Uint8List> readFileChunk(String path, int offset, int length) async {
    final value = await _runJsonValue(
      _wrapSimplePython('''
target = ${boardFileTextExpression(path)}
with open(target, 'rb') as f:
  f.seek($offset)
  data = f.read($length)
encoded = ubinascii.b2a_base64(data).decode().strip()
_emit_ok(encoded)
'''),
      timeout: _longTimeout,
    );
    if (value is! String) {
      throw const BoardFileProtocolException(
        'Read chunk response is not a string',
      );
    }
    return decodeBoardFileBytes(value);
  }

  @override
  Future<void> writeTextFile(String path, String content) async {
    await writeFileBytes(path, utf8.encode(content));
  }

  @override
  Future<void> writeFileBytes(
    String path,
    List<int> bytes, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final mode = ref.read(replModeProvider);
    if (mode == ReplMode.paste) {
      await _writeFileBytesViaPaste(path, bytes, onProgress: onProgress);
      return;
    }

    final target = boardFileTextExpression(path);
    final tempPath = _temporaryPathFor(path);
    final temp = boardFileTextExpression(tempPath);
    final payload = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final timeoutSeconds = 60 + (payload.length / 20000).ceil();

    await runPythonOnDeviceWithRawInput(
      ref,
      _buildWriteFileScript(
        target: target,
        temp: temp,
        remaining: payload.length,
      ),
      payload,
      startupTimeout: const Duration(seconds: 10),
      completionTimeout: Duration(seconds: timeoutSeconds),
      readyMarker: utf8.encode(_writeReadyMarker),
      doneMarker: utf8.encode(_writeDoneMarker),
      chunkSize: _rawWriteChunkSize,
      ackEvery: _rawWriteAckEvery,
      onProgress: onProgress,
    );
  }

  Future<void> _writeFileBytesViaPaste(
    String targetPath,
    List<int> bytes, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final payload = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final totalSize = payload.length;
    onProgress?.call(0, totalSize);

    const chunkSize = 2000;
    final tempPath = _temporaryPathFor(targetPath);
    final tempExpr = boardFileTextExpression(tempPath);
    final targetExpr = boardFileTextExpression(targetPath);

    await runPythonOnDevice(
      ref,
      _wrapSimplePython('''
import os
try:
  os.remove($tempExpr)
except OSError:
  pass
f = open($tempExpr, 'wb')
f.close()
_emit_ok(True)
'''),
    );

    var offset = 0;
    while (offset < totalSize) {
      final end = (offset + chunkSize < totalSize)
          ? offset + chunkSize
          : totalSize;
      final chunk = payload.sublist(offset, end);
      final b64 = base64Encode(chunk);

      await runPythonOnDevice(
        ref,
        _wrapSimplePython('''
import ubinascii
data = ubinascii.a2b_base64('$b64')
f = open($tempExpr, 'ab')
f.write(data)
f.close()
_emit_ok(True)
'''),
      );

      offset = end;
      onProgress?.call(offset, totalSize);
    }

    await runPythonOnDevice(
      ref,
      _wrapSimplePython('''
import os
try:
  os.remove($targetExpr)
except OSError:
  pass
os.rename($tempExpr, $targetExpr)
_emit_ok(True)
'''),
    );

    onProgress?.call(totalSize, totalSize);
  }

  static String _buildWriteFileScript({
    required String target,
    required String temp,
    required int remaining,
  }) {
    return '''
import sys
try:
  import uos as os
except ImportError:
  import os
import ubinascii
try:
  import micropython
except ImportError:
  micropython = None

def _decode_text(value):
  return ubinascii.a2b_base64(value).decode()

target = $target
tmp = $temp
remaining = $remaining
ack_every = $_rawWriteAckEvery
ack_count = 0

try:
  if micropython is not None:
    micropython.kbd_intr(-1)
  usb = sys.stdin.buffer
  sys.stdout.write('$_writeReadyMarker')
  try:
    sys.stdout.flush()
  except Exception:
    pass
  try:
    try:
      os.remove(tmp)
    except OSError:
      pass
    f = open(tmp, 'wb')
    try:
      while remaining:
        want = min($_rawWriteChunkSize, remaining)
        data = b''
        while len(data) < want:
          chunk = usb.read(min(64, want - len(data)))
          if chunk:
            data += chunk
        f.write(data)
        remaining -= len(data)
        ack_count += 1
        if ack_every and ack_count % ack_every == 0:
          f.flush()
          if remaining:
            sys.stdout.write('+')
            try:
              sys.stdout.flush()
            except Exception:
              pass
      f.flush()
    finally:
      f.close()
    try:
      os.remove(target)
    except OSError:
      pass
    try:
      os.rename(tmp, target)
    except Exception:
      try:
        os.remove(tmp)
      except OSError:
        pass
      raise
    sys.stdout.write('$_writeDoneMarker')
    try:
      sys.stdout.flush()
    except Exception:
      pass
  except Exception as exc:
    sys.stdout.write('PYRITE_WRITE_ERR:' + str(exc) + '\\n')
    sys.stdout.write('$_writeDoneMarker')
    try:
      sys.stdout.flush()
    except Exception:
      pass
    raise
finally:
  if micropython is not None:
    try:
      micropython.kbd_intr(3)
    except Exception:
      pass
''';
  }

  @override
  Future<void> deleteFile(String path) async {
    await _runJsonValue(
      _wrapSimplePython('''
os.remove(${boardFileTextExpression(path)})
_emit_ok('DeleteFileSuccessfully')
'''),
    );
  }

  @override
  Future<void> deleteFolder(String path) async {
    await _runJsonValue(
      _wrapSimplePython('''
target = ${boardFileTextExpression(path)}

def delete_recursive(folder):
  for entry in os.ilistdir(folder):
    name = entry[0]
    mode = entry[1] if len(entry) > 1 else 0
    entry_path = folder.rstrip('/') + '/' + name
    is_dir = bool(mode & 0x4000) if mode else False
    if is_dir:
      delete_recursive(entry_path)
    else:
      os.remove(entry_path)
  os.rmdir(folder)

delete_recursive(target)
_emit_ok('DeleteDirSuccessfully')
'''),
      timeout: _longTimeout,
    );
  }

  @override
  Future<void> rename(String path, String newName) async {
    final parent = _boardPath.dirname(path);
    final target = parent == '/'
        ? '/$newName'
        : _boardPath.join(parent, newName);
    await _runJsonValue(
      _wrapSimplePython('''
os.rename(${boardFileTextExpression(path)}, ${boardFileTextExpression(target)})
_emit_ok('RenameSuccessfully')
'''),
    );
  }

  @override
  Future<void> move(String oldPath, String newPath) async {
    await _runJsonValue(
      _wrapSimplePython('''
os.rename(${boardFileTextExpression(oldPath)}, ${boardFileTextExpression(newPath)})
_emit_ok('MoveSuccessfully')
'''),
    );
  }

  @override
  Future<void> createFolder(String path) async {
    await _runJsonValue(
      _wrapSimplePython('''
try:
  os.mkdir(${boardFileTextExpression(path)})
  _emit_ok('MkdirSuccessfully')
except OSError as exc:
  if len(exc.args) > 0 and exc.args[0] == 17:
    _emit_ok('DirExists')
  else:
    raise
'''),
    );
  }

  @override
  Future<void> pathExists(String path) async {
    await _runJsonValue(
      _wrapSimplePython('''
os.stat(${boardFileTextExpression(path)})
_emit_ok(True)
'''),
    );
  }

  Future<dynamic> _runJsonValue(
    String python, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final output = await runPythonOnDevice(ref, python, timeout: timeout);
    String? line;
    for (final candidate in output.split('\n').map((line) => line.trim())) {
      if (candidate.startsWith(_resultMarker)) {
        line = candidate;
      }
    }
    if (line == null) {
      throw BoardFileProtocolException(
        'Missing board file result marker. Output: ${output.length <= 240 ? output : '${output.substring(0, 240)}...'}',
      );
    }

    final decoded = jsonDecode(line.substring(_resultMarker.length));
    if (decoded is! Map<String, dynamic>) {
      throw const BoardFileProtocolException('Board response is not a map');
    }
    if (decoded['ok'] != true) {
      final error = _decodeError(decoded);
      throw BoardFileBackendException(error);
    }
    return decoded['value'];
  }

  static const _simpleBoilerplate = '''
try:
  import ujson as json
except ImportError:
  import json
try:
  import uos as os
except ImportError:
  import os
import ubinascii

def _decode_text(value):
  return ubinascii.a2b_base64(value).decode()

def _encode_text(value):
  if isinstance(value, bytes):
    data = value
  else:
    data = value.encode()
  return ubinascii.b2a_base64(data).decode().strip()

def _emit_ok(value):
  print(__PYRITE_MARKER__ + json.dumps({'ok': True, 'value': value}))

def _emit_error(exc):
  try:
    name = type(exc).__name__
  except Exception:
    name = 'Exception'
  print(__PYRITE_MARKER__ + json.dumps({
    'ok': False,
    'error_b64': _encode_text(name + ': ' + str(exc)),
  }))
''';

  String _wrapSimplePython(String body) {
    final indentedBody = body
        .trim()
        .split('\n')
        .map((line) => line.isEmpty ? line : '  $line')
        .join('\n');

    final marker = jsonEncode(_resultMarker);
    final boilerplate = _simpleBoilerplate.replaceAll(
      '__PYRITE_MARKER__',
      marker,
    );

    return '''
$boilerplate

_PYRITE_MARKER = $marker

try:
$indentedBody
except Exception as _pyrite_exc:
  _emit_error(_pyrite_exc)
''';
  }

  List<BoardFileEntry> _parseEntries(dynamic value) {
    if (value is! List) {
      throw const BoardFileProtocolException(
        'File list response is not a list',
      );
    }
    return value.map((entry) {
      if (entry is! Map) {
        throw const BoardFileProtocolException('File list item is not a map');
      }
      final type = entry['type'] == 'folder'
          ? BoardFileEntryType.folder
          : BoardFileEntryType.file;
      return BoardFileEntry(
        path: _entryText(entry, 'path'),
        name: _entryText(entry, 'name'),
        type: type,
      );
    }).toList();
  }

  String _entryText(Map<dynamic, dynamic> entry, String key) {
    final encoded = entry['${key}_b64'];
    if (encoded != null) {
      try {
        return decodeBoardFileText(encoded.toString());
      } on FormatException catch (error) {
        throw BoardFileProtocolException(
          'Invalid encoded $key in board file list: $error',
        );
      }
    }

    final value = entry[key];
    if (value == null) {
      throw BoardFileProtocolException('Missing $key in board file list item');
    }
    return value.toString();
  }

  String _decodeError(Map<String, dynamic> decoded) {
    final encoded = decoded['error_b64'];
    if (encoded is String) {
      try {
        return decodeBoardFileText(encoded);
      } on FormatException {
        return 'Invalid board error payload';
      }
    }
    return decoded['error']?.toString() ?? 'Unknown board error';
  }

  String _temporaryPathFor(String targetPath) {
    final parent = _boardPath.dirname(targetPath);
    final basename = _boardPath.basename(targetPath);
    final tempName = '.$basename.pyrite.tmp';
    return parent == '/' ? '/$tempName' : _boardPath.join(parent, tempName);
  }
}

// ---------------------------------------------------------------------------
// Backend provider
// ---------------------------------------------------------------------------

final boardFileBackendProvider = Provider<BoardFileBackend>(
  (ref) => SerialBoardFileBackend(ref),
);

// ---------------------------------------------------------------------------
// BoardFileOps — pure file I/O operations (no BuildContext)
// ---------------------------------------------------------------------------

class BoardFileOps {
  static final boardPath = path.Context(style: path.Style.posix);

  final Ref ref;

  BoardFileOps(this.ref);

  String normalizeBoardPath(String filePath) {
    final normalized = boardPath.normalize(filePath.replaceAll('\\', '/'));
    if (normalized == '.' || normalized.isEmpty) return '/';
    return normalized.startsWith('/') ? normalized : '/$normalized';
  }

  bool isBoardPathInside(String childPath, String parentPath) {
    final child = normalizeBoardPath(childPath);
    final parent = normalizeBoardPath(parentPath);
    return child == parent || boardPath.isWithin(parent, child);
  }

  Future<List<BoardFileEntry>> getFileList({String path = "/"}) async {
    return ref.read(boardFileBackendProvider).listDirectory(path: path);
  }

  Future<String> getFileContent(String path) async {
    return ref.read(boardFileBackendProvider).readTextFile(path);
  }

  Future<Uint8List> getFileBytes(String path) async {
    return ref.read(boardFileBackendProvider).readFileBytes(path);
  }

  Future<Uint8List> getFileBytesWithProgress(
    String sourcePath, {
    required String currentFile,
    required int index,
    required int totalFiles,
  }) async {
    final backend = ref.read(boardFileBackendProvider);
    final progress = ref.read(fileTransferProgressProvider.notifier);
    final size = await backend.getFileSize(sourcePath);
    progress.startFile(
      file: currentFile,
      index: index,
      totalFiles: totalFiles,
      bytesTotal: size,
    );
    if (size == 0) return Uint8List(0);

    const chunkSize = 4096;
    final result = Uint8List(size);
    var offset = 0;
    while (offset < size) {
      final len = (size - offset < chunkSize) ? size - offset : chunkSize;
      final chunk = await backend.readFileChunk(sourcePath, offset, len);
      result.setRange(offset, offset + len, chunk);
      offset += len;
      progress.updateBytes(offset, size);
    }
    return result;
  }

  Future<void> writeFile(String targetPath, String content) async {
    await ref.read(boardFileBackendProvider).writeTextFile(targetPath, content);
  }

  Future<void> writeFileBytes(
    String targetPath,
    List<int> bytes, {
    void Function(int sent, int total)? onProgress,
  }) async {
    await ref
        .read(boardFileBackendProvider)
        .writeFileBytes(targetPath, bytes, onProgress: onProgress);
  }

  Future<void> writeFileBytesWithProgress(
    String targetPath,
    List<int> bytes, {
    required String currentFile,
    required int index,
    required int totalFiles,
  }) async {
    final backend = ref.read(boardFileBackendProvider);
    final progress = ref.read(fileTransferProgressProvider.notifier);
    progress.startFile(
      file: currentFile,
      index: index,
      totalFiles: totalFiles,
      bytesTotal: bytes.length,
    );
    await backend.writeFileBytes(
      targetPath,
      bytes,
      onProgress: progress.updateBytes,
    );
    progress.updateBytes(bytes.length, bytes.length);
  }

  Future<void> deleteFile(String path) async {
    await ref.read(boardFileBackendProvider).deleteFile(path);
  }

  Future<void> deleteFolder(String path) async {
    await ref.read(boardFileBackendProvider).deleteFolder(path);
  }

  Future<void> rename(String path, String newName) async {
    await ref.read(boardFileBackendProvider).rename(path, newName);
  }

  Future<void> move(String oldPath, String newPath) async {
    await ref.read(boardFileBackendProvider).move(oldPath, newPath);
  }

  Future<void> createFolder(String path) async {
    await ref.read(boardFileBackendProvider).createFolder(path);
  }

  Future<List<BoardFileEntry>> lisFolderRecursive({
    String path = "/",
  }) async {
    return ref.read(boardFileBackendProvider).listTree(path: path);
  }

  Future<bool> boardFolderExists(String folderPath) async {
    try {
      await getFileList(path: folderPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> boardPathExistsAny(String targetPath) async {
    try {
      await ref.read(boardFileBackendProvider).pathExists(targetPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> deleteBoardPathAny(String targetPath) async {
    final exists = await boardPathExistsAny(targetPath);
    if (!exists) return;
    try {
      await deleteFolder(targetPath);
    } catch (_) {
      await deleteFile(targetPath);
    }
  }
}

// ---------------------------------------------------------------------------
// BoardTransfer — folder upload/download orchestration
// ---------------------------------------------------------------------------

class BoardTransfer {
  static final _boardPath = path.Context(style: path.Style.posix);

  final Ref ref;
  final BoardFileOps _ops;

  BoardTransfer(this.ref, this._ops);

  Future<void> uploadFolder(String localPath, String remotePath) async {
    final dir = io.Directory(localPath);
    final entities = await dir.list(recursive: true).toList();
    final files = entities.whereType<io.File>().toList(growable: false);
    final createdDirs = <String>{};
    ref
        .read(fileTransferProgressProvider.notifier)
        .start(
          direction: FileTransferDirection.upload,
          scope: FileTransferScope.folder,
          totalFiles: files.length,
          message: translateWithReplacements(
            ref,
            I18nKey.fileTransferPrepareUploadFolder,
          ),
        );

    await _ensureBoardFolder(remotePath, createdDirs);

    for (final entity in entities) {
      final relativePath = path
          .relative(entity.path, from: localPath)
          .replaceAll('\\', '/');
      final remoteEntityPath = _boardPath.join(remotePath, relativePath);

      if (entity is io.Directory) {
        debugPrint('[BoardWS] Creating remote dir: $remoteEntityPath');
        await _ensureBoardFolder(remoteEntityPath, createdDirs);
      }
    }

    for (var i = 0; i < files.length; i++) {
      final entity = files[i];
      final relativePath = path
          .relative(entity.path, from: localPath)
          .replaceAll('\\', '/');
      final remoteEntityPath = _boardPath.join(remotePath, relativePath);
      final parentDir = _boardPath.dirname(remoteEntityPath);
      if (!createdDirs.contains(parentDir)) {
        debugPrint('[BoardWS] Creating parent dir: $parentDir');
        await _ensureBoardFolder(parentDir, createdDirs);
      }
      debugPrint('[BoardWS] Uploading file: $remoteEntityPath');
      await _ops.writeFileBytesWithProgress(
        remoteEntityPath,
        await entity.readAsBytes(),
        currentFile: entity.path,
        index: i + 1,
        totalFiles: files.length,
      );
      debugPrint('[BoardWS] Uploaded: $remoteEntityPath');
    }
  }

  Future<void> _ensureBoardFolder(
    String folderPath,
    Set<String> createdDirs,
  ) async {
    final normalized = _ops.normalizeBoardPath(folderPath);
    if (normalized == '/') return;

    var current = '/';
    for (final part in _boardPath.split(normalized)) {
      if (part.isEmpty || part == '/') continue;
      current = current == '/'
          ? _boardPath.join('/', part)
          : _boardPath.join(current, part);
      if (createdDirs.contains(current)) continue;

      try {
        await _ops.createFolder(current);
      } catch (error) {
        if (!await _ops.boardFolderExists(current)) {
          debugPrint('[BoardWS] Failed to create dir: $current: $error');
          rethrow;
        }
      }
      createdDirs.add(current);
    }
  }

  Future<void> downloadFolder(String remotePath, String localPath) async {
    final items = await _ops.lisFolderRecursive(path: remotePath);
    final folders = items
        .where((item) => item.isFolder)
        .toList(growable: false);
    final files = items
        .where((item) => !item.isFolder)
        .toList(growable: false);
    ref
        .read(fileTransferProgressProvider.notifier)
        .start(
          direction: FileTransferDirection.download,
          scope: FileTransferScope.folder,
          totalFiles: files.length,
          message: translateWithReplacements(
            ref,
            I18nKey.fileTransferPrepareDownloadFolder,
          ),
        );

    final localDir = io.Directory(localPath);
    if (!await localDir.exists()) {
      await localDir.create(recursive: true);
    }

    for (final item in folders) {
      final relativePath = _boardPath
          .relative(item.path, from: remotePath)
          .replaceAll('\\', '/');
      final localItemPath = path.join(localPath, relativePath);
      await io.Directory(localItemPath).create(recursive: true);
    }

    for (var i = 0; i < files.length; i++) {
      final item = files[i];
      final relativePath = _boardPath
          .relative(item.path, from: remotePath)
          .replaceAll('\\', '/');
      final localItemPath = path.join(localPath, relativePath);
      debugPrint('[BoardWS] Downloading: ${item.path}');
      final bytes = await _ops.getFileBytesWithProgress(
        item.path,
        currentFile: item.path,
        index: i + 1,
        totalFiles: files.length,
      );
      final file = io.File(localItemPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      debugPrint('[BoardWS] Downloaded: $localItemPath');
    }
  }
}

// ---------------------------------------------------------------------------
// Board utilities
// ---------------------------------------------------------------------------

Future<List<TreeNode<FileSystemItem>>> buildBoardFileListItems(
  List<BoardFileEntry> entries,
) async {
  final items = <TreeNode<FileSystemItem>>[];
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

Future<io.File> getLocalFile(String boardFilePath) async {
  final supportDir = path.join(
    (await getApplicationSupportDirectory()).path,
    "temporary_board_files",
  );
  final relativePath = boardFilePath.split("/").skip(1).join("/");
  final file = io.File(path.join(supportDir, relativePath));
  await file.create(recursive: true, exclusive: false);
  return file;
}

// ---------------------------------------------------------------------------
// Board filesystem mount
// ---------------------------------------------------------------------------

const _ensureFilesystemMountedScript = r'''
import os

def _fs_ready():
  try:
    s = os.statvfs('/')
    return bool(s[0] and s[2])
  except Exception:
    return False

def _mount_flashbdev():
  try:
    import flashbdev
    b = flashbdev.bdev
    if isinstance(b, (list, tuple)):
      b = b[0]
  except Exception:
    return

  candidates = [b]
  try:
    candidates.append(os.VfsLfs2(b))
  except Exception:
    pass

  for candidate in candidates:
    try:
      os.mount(candidate, '/')
      return
    except Exception:
      pass

if not _fs_ready():
  _mount_flashbdev()
print('FS_READY' if _fs_ready() else 'FS_NOT_READY')
''';

Future<void> ensureBoardFilesystemMountedOnce(Ref ref) async {
  try {
    final output = await runPythonOnDevice(
      ref,
      _ensureFilesystemMountedScript,
      timeout: const Duration(seconds: 5),
    );
    if (output.contains('FS_NOT_READY')) {
      debugPrint('Board filesystem is not ready after mount attempt.');
    }
  } catch (error) {
    debugPrint('Board filesystem mount check failed: $error');
  }
}
