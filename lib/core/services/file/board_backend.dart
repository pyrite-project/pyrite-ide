import 'dart:convert';
import 'dart:io' as io;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/file/file_ops.dart';
import 'package:pyrite_ide/core/services/serial/device_executor.dart';
import 'package:pyrite_ide/core/services/serial/repl_mode_provider.dart';
import 'package:pyrite_ide/core/services/file/file_transfer_mode_provider.dart';
import 'package:pyrite_ide/core/services/serial/serial_byte_queue.dart';
import 'package:pyrite_ide/core/services/serial/serial_provider.dart';
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
  Future<Uint8List> readFileBytes(
    String path, {
    void Function(int received, int total)? onProgress,
  });
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

  /// Device signals readiness for data transfer (matches CLI's 'READY').
  static const _writeReadyMarker = 'PYRITE_WRITE_READY';

  /// Host/device end-of-transfer handshake byte (matches CLI's 'ok').
  static const _writeDoneMarker = 'PYRITE_WRITE_DONE';
  static const _longTimeout = Duration(seconds: 60);
  static const _defaultChunkSize = 2048;
  static const _defaultWriteChunkSize = 2048;
  static const _rawWriteAckEvery = 1;

  static final _boardPath = path.Context(style: path.Style.posix);

  final Ref ref;

  /// Cached free heap from the last successful probe. `null` = not probed yet.
  int? _cachedFreeHeap;

  SerialBoardFileBackend(this.ref);

  /// Returns a safe chunk size for file I/O based on cached device memory.
  ///
  /// Probes `gc.mem_free()` on the device once, then caches the result.
  /// Returns [_defaultChunkSize] when probing fails or has not run yet.
  int get _safeChunkSize {
    final free = _cachedFreeHeap;
    if (free == null) return _defaultChunkSize;
    if (free < 4 * 1024) return 256;
    if (free < 8 * 1024) return 512;
    if (free < 16 * 1024) return 1024;
    if (free < 32 * 1024) return 2048;
    if (free < 64 * 1024) return 4096;
    return 8192;
  }

  /// Returns a safe write chunk size.  Write operations need extra headroom
  /// for the base64 decode buffer and file write buffer on the device, so
  /// this is more conservative than [_safeChunkSize] (roughly half).
  int get _safeWriteChunkSize {
    final free = _cachedFreeHeap;
    if (free == null) return _defaultWriteChunkSize;
    if (free < 4 * 1024) return 64;
    if (free < 8 * 1024) return 128;
    if (free < 16 * 1024) return 256;
    if (free < 32 * 1024) return 512;
    if (free < 64 * 1024) return 1024;
    return 2048;
  }

  /// Probe the device for free heap memory.  Caches the result so
  /// subsequent calls are free.  Silently returns on failure.
  Future<void> _probeFreeHeap() async {
    if (_cachedFreeHeap != null) return;
    try {
      final raw = await runPythonOnDevice(
        ref,
        _wrapSimplePython('''
import gc
_emit_ok(gc.mem_free())
'''),
        timeout: const Duration(seconds: 5),
      );
      final value = _extractValue(raw);
      if (value is int) {
        _cachedFreeHeap = value;
        debugPrint('[board-backend] device free heap: ${value}B');
      } else if (value is num) {
        _cachedFreeHeap = value.toInt();
        debugPrint('[board-backend] device free heap: ${value.toInt()}B');
      }
    } catch (e) {
      debugPrint('[board-backend] heap probe failed: $e');
    }
  }

  static const _maxRetries = 2;

  /// Retry [action] up to [_maxRetries] times on transient errors.
  ///
  /// Protocol errors ([BoardFileProtocolException]) are never retried
  /// because they indicate deterministic failures (missing marker, bad
  /// JSON, etc.). User-initiated cancellation is never retried.
  /// Only runtime errors (timeout, connection drop, etc.) are retried
  /// with exponential backoff.
  Future<T> _withRetry<T>(
    Future<T> Function() action, {
    int maxRetries = _maxRetries,
  }) async {
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        return await action();
      } catch (e) {
        if (e is SerialCancelledException) {
          debugPrint('[board-backend] user cancelled, not retrying');
          rethrow;
        }
        if (attempt == maxRetries || e is BoardFileProtocolException) rethrow;
        debugPrint('[board-backend] attempt ${attempt + 1} failed: $e');
        _cachedFreeHeap = null;
        await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }
    throw StateError('unreachable');
  }

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
  Future<Uint8List> readFileBytes(
    String path, {
    void Function(int received, int total)? onProgress,
  }) async {
    return _withRetry(() async {
      final effectiveMode = resolveFileTransferMode(
        ref.read(replModeProvider),
        ref.read(fileTransferModeProvider),
      );
      if (effectiveMode == FileTransferMode.chunked) {
        await _probeFreeHeap();
        return _readFileBytesChunked(path, onProgress: onProgress);
      }
      return runPythonReadDeviceFile(ref, path, onProgress: onProgress);
    });
  }

  /// Thonny-style chunked download. Size lookup, open, reads, and close all
  /// happen inside one REPL transaction.
  Future<Uint8List> _readFileBytesChunked(
    String path, {
    void Function(int received, int total)? onProgress,
  }) async {
    final chunkSize = _safeChunkSize;
    final encodedPath = jsonEncode(encodeBoardFileText(path));
    late Uint8List result;
    await runPythonInReplSession(ref, (session, replMode) async {
      Future<String> execute(String code) =>
          session.executeCommand(code, mode: replMode, timeout: _longTimeout);

      final sizeOutput = await execute('''
import ubinascii
try:
  import uos as os
except ImportError:
  import os
__pyrite_read_path = ubinascii.a2b_base64($encodedPath).decode()
print(os.stat(__pyrite_read_path)[6])
__pyrite_read_fp = open(__pyrite_read_path, 'rb')
''');
      final fileSize = int.tryParse(sizeOutput.trim());
      if (fileSize == null || fileSize < 0) {
        throw BoardFileProtocolException(
          'File size response is not a number: ${sizeOutput.trim()}',
        );
      }
      result = Uint8List(fileSize);
      onProgress?.call(0, fileSize);
      var offset = 0;
      try {
        while (offset < fileSize) {
          final length = math.min(chunkSize, fileSize - offset);
          final output = await execute('''
print(ubinascii.b2a_base64(__pyrite_read_fp.read($length)).decode().strip())
''');
          final chunk = decodeBoardFileBytes(output.trim());
          if (chunk.length != length) {
            throw BoardFileProtocolException(
              'Read chunk size mismatch: expected $length, got ${chunk.length}',
            );
          }
          result.setRange(offset, offset + length, chunk);
          offset += length;
          onProgress?.call(offset, fileSize);
        }
      } finally {
        try {
          await execute('''
__pyrite_read_fp.close()
del __pyrite_read_fp
del __pyrite_read_path
''');
        } catch (_) {}
      }
    });
    return result;
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
    final preferredMode = ref.read(fileTransferModeProvider);
    final transferMode = resolveFileTransferMode(mode, preferredMode);
    await _probeFreeHeap();
    debugPrint(
      '[board-backend] writeFileBytes path=$path size=${bytes.length}B mode=$mode '
      'transferMode=$transferMode chunkSize=$_safeWriteChunkSize freeHeap=$_cachedFreeHeap',
    );

    if (transferMode == FileTransferMode.chunked) {
      await _writeFileBytesChunked(path, bytes, onProgress: onProgress);
      return;
    }

    // The resolver only returns streaming while using raw REPL.
    final target = boardFileTextExpression(path);
    final tempPath = _temporaryPathFor(path);
    final temp = boardFileTextExpression(tempPath);
    final payload = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final timeoutSeconds = 60 + (payload.length / 20000).ceil();
    final baudRate = ref.read(serialProvider).baudRate;
    final ackEvery = baudRate <= 57600 ? 1 : _rawWriteAckEvery;
    debugPrint(
      '[board-backend] rawUpload path: ackEvery=$ackEvery baud=$baudRate '
      'timeout=${timeoutSeconds}s temp=$tempPath',
    );

    await _withRetry(
      () => runPythonOnDeviceWithRawInput(
        ref,
        _buildWriteFileScript(
          target: target,
          temp: temp,
          remaining: payload.length,
          chunkSize: _safeWriteChunkSize,
          ackEvery: ackEvery,
        ),
        payload,
        startupTimeout: const Duration(seconds: 10),
        completionTimeout: Duration(seconds: timeoutSeconds),
        readyMarker: utf8.encode(_writeReadyMarker),
        doneMarker: utf8.encode(_writeDoneMarker),
        chunkSize: _safeWriteChunkSize,
        ackEvery: ackEvery,
        onProgress: onProgress,
      ),
    );
  }

  Future<void> _writeFileBytesChunked(
    String targetPath,
    List<int> bytes, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final payload = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final totalSize = payload.length;
    onProgress?.call(0, totalSize);

    final tempPath = _temporaryPathFor(targetPath);
    final tempExpr = boardFileTextExpression(tempPath);
    final targetExpr = boardFileTextExpression(targetPath);
    final timeoutSeconds = 60 + (payload.length / 20000).ceil();
    final commandTimeout = Duration(seconds: timeoutSeconds);
    final chunkSize = ref.read(replModeProvider) == ReplMode.paste
        ? math.min(_safeWriteChunkSize, 128)
        : _safeWriteChunkSize;

    await _withRetry(
      () => runPythonInReplSession(ref, (session, replMode) async {
        Future<void> expectQuiet(String script) async {
          final output = await session.executeCommand(
            script,
            mode: replMode,
            timeout: commandTimeout,
          );
          if (output.trim().isNotEmpty) {
            throw BoardFileProtocolException(
              'Unexpected board output during file write: '
              '${output.length <= 240 ? output : '${output.substring(0, 240)}...'}',
            );
          }
        }

        var committed = false;
        try {
          await expectQuiet('''
import ubinascii
try:
  import uos as os
except ImportError:
  import os
def _decode_text(value):
  return ubinascii.a2b_base64(value).decode()

__pyrite_target = $targetExpr
__pyrite_tmp = $tempExpr
__pyrite_written = 0
try:
  os.remove(__pyrite_tmp)
except OSError:
  pass
__pyrite_fp = open(__pyrite_tmp, 'wb')

def __pyrite_W(value):
  global __pyrite_written
  data = ubinascii.a2b_base64(value)
  __pyrite_written += __pyrite_fp.write(data)
  __pyrite_fp.flush()
''');

          var offset = 0;
          while (offset < totalSize) {
            final end = (offset + chunkSize < totalSize)
                ? offset + chunkSize
                : totalSize;
            await expectQuiet(
              "__pyrite_W('${base64Encode(payload.sublist(offset, end))}')",
            );
            offset = end;
            onProgress?.call(offset, totalSize);
          }

          await expectQuiet('''
__pyrite_fp.close()
try:
  os.remove(__pyrite_target)
except OSError:
  pass
os.rename(__pyrite_tmp, __pyrite_target)
__pyrite_actual = os.stat(__pyrite_target)[6]
if __pyrite_actual != $totalSize:
  raise Exception('file size mismatch: expected $totalSize, got ' + str(__pyrite_actual))
del __pyrite_W
del __pyrite_written
del __pyrite_target
del __pyrite_tmp
del __pyrite_fp
del __pyrite_actual
''');
          committed = true;
        } finally {
          if (!committed) {
            try {
              await expectQuiet('''
try:
  __pyrite_fp.close()
except Exception:
  pass
try:
  os.remove(__pyrite_tmp)
except Exception:
  pass
''');
            } catch (_) {}
          }
        }
      }),
    );

    onProgress?.call(totalSize, totalSize);
  }

  static String _buildWriteFileScript({
    required String target,
    required String temp,
    required int remaining,
    required int chunkSize,
    required int ackEvery,
  }) {
    return '''
import sys
try:
  import uos as os
except ImportError:
  import os
import ubinascii
def _log(msg):
  try:
    sys.stderr.write('[DEV-LOG] ' + msg + '\\n')
    sys.stderr.flush()
  except Exception:
    pass

def _decode_text(value):
  return ubinascii.a2b_base64(value).decode()

target = $target
tmp = $temp
original_size = $remaining
remaining = original_size
ack_every = $ackEvery
ack_count = 0
chunk_size = $chunkSize

_log('start size=' + str(original_size) + ' chunk=' + str(chunk_size) + ' ack=' + str(ack_every))

try:
  usb = sys.stdin
  try:
    try:
      os.remove(tmp)
    except OSError:
      pass
    _log('opening ' + tmp)
    f = open(tmp, 'wb')
  except Exception as exc:
    _log('ERROR open: ' + str(exc))
    sys.stdout.write('$_writeDoneMarker')
    try:
      sys.stdout.flush()
    except Exception:
      pass
    raise
  _log('sending READY')
  sys.stdout.write('$_writeReadyMarker')
  try:
    sys.stdout.flush()
  except Exception:
    pass
  try:
    while remaining:
      line = usb.readline()
      if not line:
        raise Exception('unexpected end of transfer')
      d = ubinascii.a2b_base64(line)
      if not d or len(d) > chunk_size or len(d) > remaining:
        raise Exception('invalid transfer chunk')
      f.write(d)
      remaining -= len(d)
      ack_count += 1
      if ack_every and ack_count % ack_every == 0:
        f.flush()
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
  actual_size = os.stat(target)[6]
  if actual_size != original_size:
    sys.stdout.write(
      'PYRITE_WRITE_ERR:size mismatch: expected '
      + str(original_size) + ', got ' + str(actual_size) + '\\n')
    sys.stdout.write('$_writeDoneMarker')
    sys.stdout.flush()
    raise Exception('file size mismatch')
  _log('done size=' + str(actual_size))
  sys.stdout.write('$_writeDoneMarker')
  try:
    sys.stdout.flush()
  except Exception:
    pass
except Exception as exc:
  _log('ERROR: ' + str(exc))
  try:
    sys.stdout.write('PYRITE_WRITE_ERR:' + str(exc) + '\\n')
    sys.stdout.write('$_writeDoneMarker')
    sys.stdout.flush()
  except Exception:
    pass
  raise
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
      // Detect MemoryError in device output and invalidate cache so next
      // probe picks a smaller chunk size.
      if (output.contains('MemoryError') ||
          output.contains('memory allocation failed')) {
        _cachedFreeHeap = 0;
        debugPrint(
          '[board-backend] MemoryError detected, '
          'invalidating heap cache',
        );
      }
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
      // Also check for MemoryError in the error string itself.
      if (error.contains('MemoryError') ||
          error.contains('memory allocation failed')) {
        _cachedFreeHeap = 0;
        debugPrint(
          '[board-backend] MemoryError in error response, '
          'invalidating heap cache',
        );
      }
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

  /// Parse the raw output from a simple `_emit_ok(value)` call and return
  /// the decoded value.  Throws if the marker is missing.
  dynamic _extractValue(String raw) {
    String? line;
    for (final candidate in raw.split('\n').map((l) => l.trim())) {
      if (candidate.startsWith(_resultMarker)) {
        line = candidate;
      }
    }
    if (line == null) return null;
    final decoded = jsonDecode(line.substring(_resultMarker.length));
    if (decoded is Map<String, dynamic> && decoded['ok'] == true) {
      return decoded['value'];
    }
    return null;
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
    progress.startFile(
      file: currentFile,
      index: index,
      totalFiles: totalFiles,
      bytesTotal: 0,
    );
    return backend.readFileBytes(sourcePath, onProgress: progress.updateBytes);
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

  Future<List<BoardFileEntry>> lisFolderRecursive({String path = "/"}) async {
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
    final files = items.where((item) => !item.isFolder).toList(growable: false);
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
