import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/serial/device_executor.dart';
import 'package:pyrite_ide/core/services/editor/terminal.dart';
import 'package:pyrite_ide/core/services/file/board_backend.dart';
import 'package:pyrite_ide/core/services/periodic_task/provider.dart';
import 'package:pyrite_ide/core/services/settings.dart';

class UsbSerialState {
  const UsbSerialState({
    this.selectedPortName,
    this.isConnected = false,
    this.baudRate = 115200,
    this.autoReconnect = false,
  });

  final String? selectedPortName;
  final bool isConnected;
  final int baudRate;
  final bool autoReconnect;

  UsbSerialState copyWith({
    String? selectedPortName,
    bool? isConnected,
    int? baudRate,
    bool? autoReconnect,
  }) {
    return UsbSerialState(
      selectedPortName: selectedPortName ?? this.selectedPortName,
      isConnected: isConnected ?? this.isConnected,
      baudRate: baudRate ?? this.baudRate,
      autoReconnect: autoReconnect ?? this.autoReconnect,
    );
  }
}

abstract class BaseUsbSerialNotifier<T extends UsbSerialState>
    extends StateNotifier<T> {
  final Ref ref;
  Timer? _reconnectTimer;
  bool _reconnectEnabled = false;
  bool _reconnectInProgress = false;
  ByteConversionSink? _replOutputDecoder;
  void Function(String data)? _serialReplOutput;

  BaseUsbSerialNotifier(this.ref, T initialState) : super(initialState);

  void registerUpdateTask() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(periodicTaskManagerProvider)
          .registerTask(
            name: "port_message_update",
            interval: const Duration(seconds: 3),
            callback: () => performUpdate(),
          );
    });
  }

  Future<void> performUpdate();

  Future<void> refresh();

  Future<void> connectPort(String path);

  Future<void> disconnectPort();

  void scheduleReconnect(String path) {
    _reconnectEnabled = true;
    _reconnectTimer?.cancel();
    if (state.isConnected || _reconnectInProgress) return;
    _reconnectTimer = Timer(const Duration(seconds: 2), () async {
      if (!_reconnectEnabled || state.isConnected || _reconnectInProgress) {
        return;
      }
      _reconnectInProgress = true;
      try {
        await connectPort(path);
      } catch (_) {
        // Retried below while automatic reconnection remains enabled.
      } finally {
        _reconnectInProgress = false;
        if (_reconnectEnabled && !state.isConnected) {
          scheduleReconnect(path);
        }
      }
    });
  }

  void cancelReconnect() {
    _reconnectEnabled = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void setBaudRate(int value) {
    state = state.copyWith(baudRate: value) as T;
  }

  void setAutoReconnect(bool value) {
    state = state.copyWith(autoReconnect: value) as T;
  }

  void ensureFilesystemMountedIfEnabled() {
    if (!ref.read(ensureBoardFilesystemOnConnect)) return;
    unawaited(ensureBoardFilesystemMountedOnce(ref));
  }

  void sendBytes(Uint8List bytes);

  void sendCommand(String command, {bool chunked = true}) {
    final data = utf8.encode(command);
    if (chunked && data.length > 256) {
      _sendChunked(Uint8List.fromList(data));
    } else {
      sendBytes(Uint8List.fromList(data));
    }
  }

  void _sendChunked(Uint8List data) async {
    const chunkSize = 256;
    for (int i = 0; i < data.length; i += chunkSize) {
      if (!state.isConnected) return;
      final end = (i + chunkSize < data.length) ? i + chunkSize : data.length;
      sendBytes(data.sublist(i, end));
    }
  }

  void bindReplOnOutputCallback() {
    _replOutputDecoder = null;
    final previous = repl.onOutput;
    void callback(String data) {
      if (ref.read(serialReplIoPausedProvider)) return;
      final encode = ref.read(chineseToUnicodeConversion);
      final text = encode ? encodeReplInputForDevice(data) : data;
      final sink = replInputSink;
      if (sink != null) {
        sink(text);
      } else {
        sendCommand(text);
      }
    }

    final hostOwnsCallback =
        replInputSink != null &&
        previous != null &&
        previous != _serialReplOutput;
    _serialReplOutput = callback;
    if (!hostOwnsCallback) repl.onOutput = callback;
  }

  void handleData(Uint8List data) {
    if (ref.read(serialReplIoPausedProvider)) {
      // Protocol traffic is consumed by the active transaction. Do not let a
      // partial UTF-8 sequence leak into the next terminal output chunk.
      _replOutputDecoder = null;
    } else {
      _replOutputDecoder ??= const Utf8Decoder(allowMalformed: true)
          .startChunkedConversion(
            StringConversionSink.fromStringSink(
              _ReplOutputSink(writeReplOutput),
            ),
          );
      _replOutputDecoder!.add(data);
    }
    for (final cb in ref.read(serialDataCallbacksProvider)) {
      try {
        cb(data);
      } catch (_) {}
    }
  }

  void resetReplOutputDecoder() {
    _replOutputDecoder = null;
  }
}

class _ReplOutputSink implements StringSink {
  const _ReplOutputSink(this._write);

  final void Function(String) _write;

  @override
  void write(Object? object) => _write(object?.toString() ?? '');

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {
    _write(objects.join(separator));
  }

  @override
  void writeCharCode(int charCode) => _write(String.fromCharCode(charCode));

  @override
  void writeln([Object? object = '']) => _write('${object ?? ''}\n');
}

/// Encodes non-ASCII characters for MicroPython REPL input.
String encodeReplInputForDevice(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    if (rune < 0x80) {
      buffer.writeCharCode(rune);
    } else if (rune <= 0xFFFF) {
      buffer.write('\\u${rune.toRadixString(16).padLeft(4, '0')}');
    } else {
      buffer.write('\\U${rune.toRadixString(16).padLeft(8, '0')}');
    }
  }
  return buffer.toString();
}
