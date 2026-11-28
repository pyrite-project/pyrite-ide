import 'package:flserial/serial_scanner.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// One serial port as `pyrcli scan` would describe it.
///
/// Mirrors `serial.tools.list_ports_common.ListPortInfo` from pyserial 3.5,
/// which is what pyrcli prints, so the device panel and the CLI agree on what
/// a port is called. Text fields pyserial cannot fill stay `'n/a'`.
@immutable
class SerialPortDescriptor {
  const SerialPortDescriptor({
    required this.path,
    this.description = notAvailable,
    this.hwid = notAvailable,
    this.vid,
    this.pid,
    this.serialNumber,
    this.manufacturer,
    this.product,
    this.interface,
    this.location,
    this.hiddenInternal = false,
  });

  /// Builds a USB port the way pyserial's `apply_usb_info` does, deriving
  /// [description] and [hwid] from the USB fields.
  factory SerialPortDescriptor.usb({
    required String path,
    required int? vid,
    required int? pid,
    String? serialNumber,
    String? manufacturer,
    String? product,
    String? interface,
    String? location,
  }) {
    return SerialPortDescriptor(
      path: path,
      description: usbDescription(
        name: p.basename(path),
        product: product,
        interface: interface,
      ),
      hwid: usbInfo(
        vid: vid,
        pid: pid,
        serialNumber: serialNumber,
        location: location,
      ),
      vid: vid,
      pid: pid,
      serialNumber: serialNumber,
      manufacturer: manufacturer,
      product: product,
      interface: interface,
      location: location,
    );
  }

  /// Wraps a flserial scan result when no richer metadata is available.
  factory SerialPortDescriptor.fromBasic(SerialPortInfo info) =>
      SerialPortDescriptor(path: info.path, description: info.description);

  /// pyserial's placeholder for fields it could not determine.
  static const notAvailable = 'n/a';

  /// Platform-specific identifier passed to `FlSerial.open`.
  final String path;
  final String description;
  final String hwid;
  final int? vid;
  final int? pid;
  final String? serialNumber;
  final String? manufacturer;
  final String? product;
  final String? interface;
  final String? location;

  /// A built-in port pyserial hides as "non-present" (Linux `platform`
  /// subsystem). It stays in the provider state so a session already open on
  /// it is not treated as unplugged; only the device list leaves it out.
  final bool hiddenInternal;

  /// The device file name, like pyserial's `ListPortInfo.name`.
  String get name => p.basename(path);

  /// Whether the port belongs to a USB device, which is what `pyrcli scan`
  /// keeps unless `--all` is passed.
  bool get isUsb => vid != null;

  /// `303A:1001`, spelled like the `vid` / `pid` fields of
  /// `pyrcli scan --json`; null for non-USB ports.
  String? get vidPid {
    final vid = this.vid;
    if (vid == null) return null;
    return '${_hex4(vid)}:${_hex4(pid ?? 0)}';
  }

  SerialPortInfo toBasic() => SerialPortInfo(path, description);

  /// pyserial `usb_description`. A missing product next to an interface reads
  /// `None` there, so it does here too.
  static String usbDescription({
    required String name,
    String? product,
    String? interface,
  }) {
    if (interface != null) return '${product ?? 'None'} - $interface';
    return product ?? name;
  }

  /// pyserial `usb_info`.
  static String usbInfo({
    int? vid,
    int? pid,
    String? serialNumber,
    String? location,
  }) {
    final buffer = StringBuffer('USB VID:PID=')
      ..write(_hex4(vid ?? 0))
      ..write(':')
      ..write(_hex4(pid ?? 0));
    if (serialNumber != null) buffer.write(' SER=$serialNumber');
    if (location != null) buffer.write(' LOCATION=$location');
    return buffer.toString();
  }

  static String _hex4(int value) =>
      value.toRadixString(16).toUpperCase().padLeft(4, '0');

  SerialPortDescriptor copyWith({String? hwid, bool? hiddenInternal}) {
    return SerialPortDescriptor(
      path: path,
      description: description,
      hwid: hwid ?? this.hwid,
      vid: vid,
      pid: pid,
      serialNumber: serialNumber,
      manufacturer: manufacturer,
      product: product,
      interface: interface,
      location: location,
      hiddenInternal: hiddenInternal ?? this.hiddenInternal,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SerialPortDescriptor &&
      other.path == path &&
      other.description == description &&
      other.hwid == hwid &&
      other.vid == vid &&
      other.pid == pid &&
      other.serialNumber == serialNumber &&
      other.manufacturer == manufacturer &&
      other.product == product &&
      other.interface == interface &&
      other.location == location &&
      other.hiddenInternal == hiddenInternal;

  @override
  int get hashCode => Object.hash(
    path,
    description,
    hwid,
    vid,
    pid,
    serialNumber,
    manufacturer,
    product,
    interface,
    location,
    hiddenInternal,
  );

  @override
  String toString() => '$path ($description) [$hwid]';
}
