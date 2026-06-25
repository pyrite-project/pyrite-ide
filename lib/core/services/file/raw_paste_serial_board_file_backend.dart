import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/services/board_manager/repl_mutex_provider.dart';
import 'package:pyrite_ide/core/services/board_manager/serial_data_callbacks_provider.dart';
import 'package:pyrite_ide/core/services/board_manager/serial_repl_gate_provider.dart';
import 'package:pyrite_ide/core/services/board_manager/utils.dart';
import 'package:pyrite_ide/core/services/file/board_file_backend.dart';
import 'package:pyrite_ide/core/services/file/board_file_wire_codec.dart';

/// Board file backend that talks to every supported platform through the
/// existing serial provider and MicroPython raw-paste protocol.
class RawPasteSerialBoardFileBackend implements BoardFileBackend {
  static const _resultMarker = '__PYRITE_BOARD_FILE_RESULT__';
  static const _defaultTimeout = Duration(seconds: 20);
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
    return decodeBoardFileText(value);
  }

  @override
  Future<void> writeTextFile(String path, String content) async {
    final encoded = encodeBoardFileText(content);
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
    Duration timeout = _defaultTimeout,
  }) async {
    final output = await _runPython(python, timeout: timeout);
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

  Future<String> _runPython(String python, {required Duration timeout}) async {
    final mutex = ref.read(replMutexProvider);
    return mutex.runExclusive(() async {
      _ensureConnected();

      final queue = _SerialByteQueue();
      void callback(Uint8List data) => queue.add(data);

      ref.read(serialReplIoPausedProvider.notifier).state = true;
      ref.read(serialDataCallbacksProvider.notifier).add(callback);

      final session = _RawPasteSession(ref, queue);
      try {
        await session.enterRawRepl(timeout: timeout);
        return await session.execute(python, timeout: timeout);
      } finally {
        try {
          await session.exitRawRepl();
        } finally {
          ref.read(serialDataCallbacksProvider.notifier).remove(callback);
          ref.read(serialReplIoPausedProvider.notifier).state = false;
        }
      }
    });
  }

  void _ensureConnected() {
    final serialProvider = getUsbSerialProvider();
    final serialState = ref.read(serialProvider);
    if (serialState.isConnected != true) {
      throw const BoardFileBackendException('No serial device is connected');
    }
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

class _RawPasteSession {
  static final _rawReplBanner = utf8.encode('raw REPL; CTRL-B to exit');
  static final _prompt = Uint8List.fromList([0x3e]);
  static final _eot = Uint8List.fromList([0x04]);
  static final _rawPasteRequest = Uint8List.fromList([0x05, 0x41, 0x01]);
  static final _ok = utf8.encode('OK');

  final Ref ref;
  final _SerialByteQueue queue;

  _RawPasteSession(this.ref, this.queue);

  Future<void> enterRawRepl({required Duration timeout}) async {
    _write(const [0x03, 0x03]);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    queue.clear();

    _write(const [0x01]);
    await queue.readUntil(_rawReplBanner, timeout);
    await queue.readUntil(_prompt, timeout);
  }

  Future<void> exitRawRepl() async {
    try {
      _write(const [0x02]);
      await queue.readUntil(utf8.encode('>>>'), const Duration(seconds: 2));
    } catch (_) {
      // A failed exit prompt read should not mask the actual file operation
      // result. The next transaction will re-enter raw REPL from a known state.
    }
  }

  Future<String> execute(String python, {required Duration timeout}) async {
    final code = Uint8List.fromList(utf8.encode(python));
    final windowIncrement = await _tryEnterRawPaste(timeout);
    final result = windowIncrement == null
        ? await _executeStandardRaw(code, timeout)
        : await _executeRawPaste(code, windowIncrement, timeout);

    if (result.stderr.isNotEmpty) {
      throw BoardFileProtocolException(
        utf8.decode(result.stderr, allowMalformed: true).trim(),
      );
    }
    return utf8.decode(result.stdout, allowMalformed: true);
  }

  Future<int?> _tryEnterRawPaste(Duration timeout) async {
    _write(_rawPasteRequest);
    final response = await queue.readBytes(2, timeout);
    if (response[0] == 0x52 && response[1] == 0x01) {
      final window = await queue.readBytes(2, timeout);
      return window[0] | (window[1] << 8);
    }
    if (response[0] == 0x52 && response[1] == 0x00) {
      return null;
    }
    if (response[0] == 0x72 && response[1] == 0x61) {
      await queue.readUntil(_prompt, timeout);
      return null;
    }
    throw BoardFileProtocolException(
      'Unexpected raw-paste handshake: ${response.toList()}',
    );
  }

  Future<_RawExecutionResult> _executeRawPaste(
    Uint8List code,
    int windowIncrement,
    Duration timeout,
  ) async {
    var remainingWindow = windowIncrement;
    var offset = 0;
    var sentEndOfData = false;

    while (offset < code.length) {
      while (queue.hasData) {
        final signal = (await queue.readBytes(1, timeout))[0];
        if (signal == 0x01) {
          remainingWindow += windowIncrement;
        } else if (signal == 0x04) {
          _write(_eot);
          sentEndOfData = true;
          offset = code.length;
          break;
        }
      }
      if (offset >= code.length) break;

      if (remainingWindow <= 0) {
        final signal = (await queue.readBytes(1, timeout))[0];
        if (signal == 0x01) {
          remainingWindow += windowIncrement;
          continue;
        }
        if (signal == 0x04) {
          _write(_eot);
          sentEndOfData = true;
          break;
        }
        continue;
      }

      final count = math.min(remainingWindow, code.length - offset);
      _write(code.sublist(offset, offset + count));
      offset += count;
      remainingWindow -= count;
    }

    if (!sentEndOfData) {
      _write(_eot);
    }
    await queue.readUntil(_eot, timeout);
    final stdout = await _readPayloadUntilEot(timeout);
    final stderr = await _readPayloadUntilEot(timeout);
    await queue.readUntil(_prompt, timeout);
    return _RawExecutionResult(stdout: stdout, stderr: stderr);
  }

  Future<_RawExecutionResult> _executeStandardRaw(
    Uint8List code,
    Duration timeout,
  ) async {
    await _writeChunksWithoutFlowControl(code);
    _write(_eot);
    await queue.readUntil(_ok, timeout);
    final stdout = await _readPayloadUntilEot(timeout);
    final stderr = await _readPayloadUntilEot(timeout);
    await queue.readUntil(_prompt, timeout);
    return _RawExecutionResult(stdout: stdout, stderr: stderr);
  }

  Future<void> _writeChunksWithoutFlowControl(Uint8List code) async {
    const chunkSize = 64;
    for (int i = 0; i < code.length; i += chunkSize) {
      final end = math.min(i + chunkSize, code.length);
      _write(code.sublist(i, end));
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  Future<Uint8List> _readPayloadUntilEot(Duration timeout) async {
    final data = await queue.readUntil(_eot, timeout);
    return Uint8List.fromList(data.sublist(0, data.length - 1));
  }

  void _write(List<int> bytes) {
    final serialProvider = getUsbSerialProvider();
    ref.read(serialProvider.notifier).sendBytes(Uint8List.fromList(bytes));
  }
}

class _RawExecutionResult {
  final Uint8List stdout;
  final Uint8List stderr;

  const _RawExecutionResult({required this.stdout, required this.stderr});
}

class _SerialByteQueue {
  final List<int> _buffer = [];
  Completer<void>? _dataCompleter;

  bool get hasData => _buffer.isNotEmpty;

  void add(Uint8List data) {
    if (data.isEmpty) return;
    _buffer.addAll(data);
    _dataCompleter?.complete();
    _dataCompleter = null;
  }

  void clear() {
    _buffer.clear();
  }

  Future<Uint8List> readBytes(int count, Duration timeout) async {
    final stopwatch = Stopwatch()..start();
    while (_buffer.length < count) {
      await _waitForData(_remaining(timeout, stopwatch));
    }
    final result = _buffer.sublist(0, count);
    _buffer.removeRange(0, count);
    return Uint8List.fromList(result);
  }

  Future<Uint8List> readUntil(List<int> pattern, Duration timeout) async {
    final stopwatch = Stopwatch()..start();
    while (true) {
      final index = _indexOf(pattern);
      if (index >= 0) {
        final end = index + pattern.length;
        final result = _buffer.sublist(0, end);
        _buffer.removeRange(0, end);
        return Uint8List.fromList(result);
      }
      await _waitForData(_remaining(timeout, stopwatch));
    }
  }

  Future<void> _waitForData(Duration timeout) async {
    _dataCompleter ??= Completer<void>();
    await _dataCompleter!.future.timeout(timeout);
  }

  Duration _remaining(Duration timeout, Stopwatch stopwatch) {
    final remainingMs = timeout.inMilliseconds - stopwatch.elapsedMilliseconds;
    if (remainingMs <= 0) {
      throw TimeoutException('Timed out waiting for serial data', timeout);
    }
    return Duration(milliseconds: remainingMs);
  }

  int _indexOf(List<int> pattern) {
    if (pattern.isEmpty || _buffer.length < pattern.length) return -1;
    for (int i = 0; i <= _buffer.length - pattern.length; i++) {
      var matched = true;
      for (int j = 0; j < pattern.length; j++) {
        if (_buffer[i + j] != pattern[j]) {
          matched = false;
          break;
        }
      }
      if (matched) return i;
    }
    return -1;
  }
}
