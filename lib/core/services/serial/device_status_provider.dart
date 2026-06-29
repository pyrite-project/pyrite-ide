import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/models/device_status.dart';
import 'package:pyrite_ide/core/services/serial/device_executor.dart';
import 'package:pyrite_ide/core/services/serial/utils.dart';

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
    final serialProvider = getUsbSerialProvider();
    final serialState = ref.read(serialProvider);
    if (serialState.isConnected != true) {
      throw StateError('设备未连接');
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
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith(_statusMarker)) {
        final jsonStr = trimmed.substring(_statusMarker.length);
        final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
        return DeviceStatus(
          ramUsed: decoded['ram_used'] as int? ?? 0,
          ramTotal: decoded['ram_total'] as int? ?? 0,
          flashUsed: decoded['flash_used'] as int? ?? 0,
          flashTotal: decoded['flash_total'] as int? ?? 0,
          firmwareVersion: decoded['firmware_version']?.toString() ?? 'unknown',
          platformModel: decoded['platform_model']?.toString() ?? 'unknown',
        );
      }
    }
    throw StateError('未能从设备响应中解析到状态数据');
  }
}

final deviceStatusProvider =
    StateNotifierProvider<DeviceStatusNotifier, AsyncValue<DeviceStatus?>>(
      (ref) => DeviceStatusNotifier(ref),
    );
