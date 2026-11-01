import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/models/device_status.dart';
import 'package:pyrite_ide/core/services/serial/device_executor.dart';
import 'package:pyrite_ide/core/services/serial/serial_provider.dart';

const _statusMarker = '__PYRITE_DEVICE_STATUS__';

class DeviceStatusNotifier extends StateNotifier<AsyncValue<DeviceStatus?>> {
  final Ref ref;
  bool _busy = false;

  DeviceStatusNotifier(this.ref) : super(const AsyncValue.data(null));

  void clear() {
    _busy = false;
    state = const AsyncValue.data(null);
  }

  Future<void> refresh() async {
    if (_busy) return;
    _busy = true;
    state = const AsyncValue.loading();
    try {
      final result = await _queryDeviceStatus();
      state = AsyncValue.data(result);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    } finally {
      _busy = false;
    }
  }

  Future<DeviceStatus> _queryDeviceStatus() async {
    _ensureConnected();
    final output = await runPythonOnDevice(ref, _buildQueryScript());
    return _parseResult(output);
  }

  void _ensureConnected() {
    final serialState = ref.read(serialProvider);
    if (serialState.isConnected != true) {
      throw StateError(translate(ref, I18nKey.devicesStatusNotConnected));
    }
  }

  String _buildQueryScript() {
    return '''
try:
  import gc, sys
except ImportError:
  pass
try:
  import ujson as json
except ImportError:
  import json
try:
  import uos as os
except ImportError:
  import os
try:
  import machine
  platform_model = machine.board() if hasattr(machine, 'board') else sys.platform
except:
  platform_model = sys.platform
try:
  _st = os.statvfs('/')
  _bsize = _st[1] if len(_st) > 1 and _st[1] > 0 else _st[0]
  flash_total_bytes = _st[2] * _bsize
  flash_free_bytes = _st[3] * _bsize
  flash_used_bytes = flash_total_bytes - flash_free_bytes
  if flash_total_bytes < 0:
    flash_total_bytes = 0
    flash_used_bytes = 0
except:
  flash_total_bytes = 0
  flash_used_bytes = 0
try:
  ram_free = gc.mem_free()
  ram_alloc = gc.mem_alloc()
  ram_total = ram_free + ram_alloc
except:
  ram_free = 0
  ram_alloc = 0
  ram_total = 0
try:
  fw_version = sys.version
except:
  fw_version = 'unknown'
result = {
  'ram_used': ram_alloc,
  'ram_total': ram_total,
  'flash_used': flash_used_bytes,
  'flash_total': flash_total_bytes,
  'firmware_version': fw_version,
  'platform_model': platform_model
}
print('$_statusMarker' + json.dumps(result))
''';
  }

  DeviceStatus _parseResult(String raw) {
    final status = parseDeviceStatusOutput(raw);
    if (status == null) {
      throw StateError(translate(ref, I18nKey.devicesStatusParseError));
    }
    return status;
  }
}

/// Extracts the status line printed by the query script.
///
/// Returns null when no complete marker line is present. Lines that carry the
/// marker but do not decode are skipped rather than fatal: the REPL echoes the
/// script back, so a truncated copy of the payload can precede the real one,
/// and one bad line must not discard the good line behind it.
DeviceStatus? parseDeviceStatusOutput(String raw) {
  for (final line in raw.split('\n')) {
    final trimmed = line.trim();
    if (!trimmed.startsWith(_statusMarker)) continue;
    final decoded = _decodeStatusPayload(
      trimmed.substring(_statusMarker.length),
    );
    if (decoded == null) continue;
    return DeviceStatus(
      ramUsed: _asByteCount(decoded['ram_used']),
      ramTotal: _asByteCount(decoded['ram_total']),
      flashUsed: _asByteCount(decoded['flash_used']),
      flashTotal: _asByteCount(decoded['flash_total']),
      firmwareVersion: decoded['firmware_version']?.toString() ?? 'unknown',
      platformModel: decoded['platform_model']?.toString() ?? 'unknown',
    );
  }
  return null;
}

/// Decodes one marker payload, or null when the line is not a JSON object.
Map<String, dynamic>? _decodeStatusPayload(String payload) {
  try {
    final decoded = jsonDecode(payload);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } on FormatException {
    return null;
  }
}

/// Reads a byte count from one payload field.
///
/// A plain `as int?` threw on a port whose `gc.mem_free()` comes back as a
/// float, turning a readable status into a parse error. Anything unusable
/// reads as zero, which the panel already renders as "unknown".
int _asByteCount(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

final deviceStatusProvider =
    StateNotifierProvider<DeviceStatusNotifier, AsyncValue<DeviceStatus?>>(
      (ref) => DeviceStatusNotifier(ref),
    );
