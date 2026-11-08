import 'dart:io';

import 'package:flserial/flserial.dart';
import 'package:flserial/serial_scanner.dart';
import 'package:pyrite_ide/core/models/serial_port_descriptor.dart';
import 'package:pyrite_ide/core/services/serial/port_catalog/linux_sysfs_ports.dart';
import 'package:pyrite_ide/core/services/serial/port_catalog/macos_ioreg_ports.dart';
import 'package:pyrite_ide/core/services/serial/port_catalog/windows_pnp_ports.dart';

typedef PortMetadataQuery =
    Future<Map<String, SerialPortDescriptor>?> Function();

/// Enumerates serial ports with the metadata `pyrcli scan` reports.
///
/// Linux reads sysfs directly on every scan; it is a few dozen small file
/// reads. Windows and macOS keep flserial's lightweight scan for presence and
/// only run the slower PowerShell / ioreg query when the set of ports changes
/// or a refresh is forced, because the provider polls every few seconds.
class SerialPortCatalog {
  SerialPortCatalog({PortMetadataQuery? metadataQuery})
    : _metadataQuery = metadataQuery ?? _platformMetadataQuery();

  final PortMetadataQuery? _metadataQuery;

  String? _metadataKey;
  Map<String, SerialPortDescriptor>? _metadata;
  Future<Map<String, SerialPortDescriptor>?>? _pendingQuery;
  String? _pendingKey;

  Future<List<SerialPortDescriptor>> scan({
    bool refreshMetadata = false,
  }) async {
    if (Platform.isLinux) return scanLinuxSysfs();
    final basic = await FlSerial.availablePorts();
    return enrich(basic, refreshMetadata: refreshMetadata);
  }

  /// Merges cached platform metadata into flserial's [basic] ports.
  Future<List<SerialPortDescriptor>> enrich(
    List<SerialPortInfo> basic, {
    bool refreshMetadata = false,
  }) async {
    final query = _metadataQuery;
    if (query == null) {
      return [for (final port in basic) SerialPortDescriptor.fromBasic(port)];
    }
    final key = (basic.map((port) => port.path).toList()..sort()).join('\n');
    if (refreshMetadata || key != _metadataKey) {
      _metadata = await _queryOnce(key, query);
      _metadataKey = key;
    }
    final metadata = _metadata;
    return [
      for (final port in basic)
        // A successful query that does not mention a port means pyserial
        // would know nothing about it either.
        if (metadata == null)
          SerialPortDescriptor.fromBasic(port)
        else
          metadata[port.path] ?? SerialPortDescriptor(path: port.path),
    ];
  }

  /// Shares one in-flight query between the poller and a manual refresh.
  Future<Map<String, SerialPortDescriptor>?> _queryOnce(
    String key,
    PortMetadataQuery query,
  ) {
    final pending = _pendingQuery;
    if (pending != null && _pendingKey == key) return pending;
    _pendingKey = key;
    Future<Map<String, SerialPortDescriptor>?> guarded() async {
      try {
        return await query();
      } catch (_) {
        return null;
      }
    }

    final future = guarded();
    _pendingQuery = future;
    return future.whenComplete(() {
      if (identical(_pendingQuery, future)) {
        _pendingQuery = null;
        _pendingKey = null;
      }
    });
  }

  static PortMetadataQuery? _platformMetadataQuery() {
    if (Platform.isWindows) return queryWindowsPnpPorts;
    if (Platform.isMacOS) return queryIoregPorts;
    return null;
  }
}
