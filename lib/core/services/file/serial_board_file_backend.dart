import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/services/serial/device_executor.dart';
import 'package:pyrite_ide/core/services/serial/repl_mode_provider.dart';
import 'package:pyrite_ide/core/services/file/board_file_backend.dart';
import 'package:pyrite_ide/core/services/file/board_file_wire_codec.dart';

/// Board file backend that communicates with MicroPython devices over serial,
/// supporting raw-paste, raw REPL, and paste modes.
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

  /// Writes file bytes via paste mode using base64 chunked encoding.
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
