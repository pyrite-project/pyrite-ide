import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/services/serial/device_executor.dart';
import 'package:pyrite_ide/core/services/file/board_file_backend.dart';
import 'package:pyrite_ide/core/services/file/board_file_wire_codec.dart';

/// Board file backend that talks to every supported platform through the
/// existing serial provider and MicroPython raw-paste protocol.
class RawPasteSerialBoardFileBackend implements BoardFileBackend {
  static const _resultMarker = '__PYRITE_BOARD_FILE_RESULT__';
  static const _longTimeout = Duration(seconds: 60);
  static const _writeChunkSize = 768;

  static final _boardPath = path.Context(style: path.Style.posix);

  final Ref ref;

  RawPasteSerialBoardFileBackend(this.ref);

  @override
  Future<List<BoardFileEntry>> listDirectory({String path = '/'}) async {
    final value = await _runJsonValue(
      _wrapPython('''
base = ${_pythonTextExpression(path)}
if base != '/' and base.endswith('/'):
  base = base[:-1]
items = []
for entry in os.ilistdir(base):
  name = entry[0]
  mode = entry[1] if len(entry) > 1 else 0
  item_path = '/' + name if base == '/' else base + '/' + name
  is_dir = _is_dir(item_path, mode)
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
      _wrapPython('''
base = ${_pythonTextExpression(path)}
if base != '/' and base.endswith('/'):
  base = base[:-1]

def walk(base_path):
  result = []
  for entry in os.ilistdir(base_path):
    name = entry[0]
    mode = entry[1] if len(entry) > 1 else 0
    item_path = '/' + name if base_path == '/' else base_path + '/' + name
    is_dir = _is_dir(item_path, mode)
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
      _wrapPython('''
target = ${_pythonTextExpression(path)}
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
      _wrapPython('''
target = ${_pythonTextExpression(path)}
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
      _wrapPython('''
target = ${_pythonTextExpression(path)}
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
  Future<void> writeFileBytes(String path, List<int> bytes) async {
    final encoded = encodeBoardFileBytes(bytes);
    final chunks = <String>[];
    for (int i = 0; i < encoded.length; i += _writeChunkSize) {
      final end = math.min(i + _writeChunkSize, encoded.length);
      chunks.add(encoded.substring(i, end));
    }

    final target = _pythonTextExpression(path);
    final tempPath = _temporaryPathFor(path);
    final temp = _pythonTextExpression(tempPath);
    final chunkList = chunks.map(_pythonStringLiteral).join(', ');

    await _runJsonValue(
      _wrapPython('''
target = $target
tmp = $temp
chunks = [$chunkList]
try:
  os.remove(tmp)
except OSError:
  pass
f = open(tmp, 'wb')
try:
  for chunk in chunks:
    f.write(ubinascii.a2b_base64(chunk))
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
_emit_ok('SaveFileSuccessfully')
'''),
      timeout: _longTimeout,
    );
  }

  @override
  Future<void> beginWriteFile(String path) async {
    final temp = _pythonTextExpression(_temporaryPathFor(path));
    await _runJsonValue(
      _wrapPython('''
tmp = $temp
try:
  os.remove(tmp)
except OSError:
  pass
open(tmp, 'wb').close()
_emit_ok('BeginWriteSuccessfully')
'''),
      timeout: _longTimeout,
    );
  }

  @override
  Future<void> appendWriteFileChunk(String path, List<int> bytes) async {
    final encoded = _pythonStringLiteral(encodeBoardFileBytes(bytes));
    final temp = _pythonTextExpression(_temporaryPathFor(path));
    await _runJsonValue(
      _wrapPython('''
tmp = $temp
data = ubinascii.a2b_base64($encoded)
with open(tmp, 'ab') as f:
  f.write(data)
_emit_ok('AppendWriteSuccessfully')
'''),
      timeout: _longTimeout,
    );
  }

  @override
  Future<void> finishWriteFile(String path) async {
    final target = _pythonTextExpression(path);
    final temp = _pythonTextExpression(_temporaryPathFor(path));
    await _runJsonValue(
      _wrapPython('''
target = $target
tmp = $temp
try:
  os.remove(target)
except OSError:
  pass
os.rename(tmp, target)
_emit_ok('FinishWriteSuccessfully')
'''),
      timeout: _longTimeout,
    );
  }

  @override
  Future<void> deleteFile(String path) async {
    await _runJsonValue(
      _wrapPython('''
os.remove(${_pythonTextExpression(path)})
_emit_ok('DeleteFileSuccessfully')
'''),
    );
  }

  @override
  Future<void> deleteFolder(String path) async {
    await _runJsonValue(
      _wrapPython('''
target = ${_pythonTextExpression(path)}

def delete_recursive(folder):
  for entry in os.ilistdir(folder):
    name = entry[0]
    mode = entry[1] if len(entry) > 1 else 0
    entry_path = folder.rstrip('/') + '/' + name
    if _is_dir(entry_path, mode):
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
      _wrapPython('''
os.rename(${_pythonTextExpression(path)}, ${_pythonTextExpression(target)})
_emit_ok('RenameSuccessfully')
'''),
    );
  }

  @override
  Future<void> move(String oldPath, String newPath) async {
    await _runJsonValue(
      _wrapPython('''
os.rename(${_pythonTextExpression(oldPath)}, ${_pythonTextExpression(newPath)})
_emit_ok('MoveSuccessfully')
'''),
    );
  }

  @override
  Future<void> createFolder(String path) async {
    await _runJsonValue(
      _wrapPython('''
try:
  os.mkdir(${_pythonTextExpression(path)})
  _emit_ok('MkdirSuccessfully')
except OSError as exc:
  if len(exc.args) > 0 and exc.args[0] == 17:
    _emit_ok('DirExists')
  else:
    raise
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
        'Missing board file result marker. Output: ${_preview(output)}',
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

  String _wrapPython(String body) {
    final indentedBody = body
        .trim()
        .split('\n')
        .map((line) => line.isEmpty ? line : '  $line')
        .join('\n');

    return '''
try:
  import ujson as json
except ImportError:
  import json
try:
  import uos as os
except ImportError:
  import os
import ubinascii

_PYRITE_MARKER = ${_pythonStringLiteral(_resultMarker)}

def _decode_text(value):
  return ubinascii.a2b_base64(value).decode()

def _encode_text(value):
  if isinstance(value, bytes):
    data = value
  else:
    data = value.encode()
  return ubinascii.b2a_base64(data).decode().strip()

def _emit_ok(value):
  print(_PYRITE_MARKER + json.dumps({'ok': True, 'value': value}))

def _emit_error(exc):
  try:
    name = type(exc).__name__
  except Exception:
    name = 'Exception'
  print(_PYRITE_MARKER + json.dumps({
    'ok': False,
    'error_b64': _encode_text(name + ': ' + str(exc)),
  }))

def _is_dir(item_path, mode):
  try:
    if mode & 0x4000:
      return True
    if mode & 0x8000:
      return False
  except Exception:
    pass
  return bool(os.stat(item_path)[0] & 0x4000)

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

  String _pythonStringLiteral(String value) => jsonEncode(value);

  String _pythonTextExpression(String value) => boardFileTextExpression(value);

  String _preview(String value) {
    if (value.length <= 240) return value;
    return '${value.substring(0, 240)}...';
  }
}
