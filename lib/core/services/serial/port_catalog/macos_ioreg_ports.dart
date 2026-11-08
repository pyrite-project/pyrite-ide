import 'package:pyrite_ide/core/models/serial_port_descriptor.dart';
import 'package:pyrite_ide/core/services/serial/port_catalog/process_output.dart';
import 'package:xml/xml.dart';

/// Queries the IORegistry for USB serial ports, keyed by `/dev/cu.*` path.
///
/// pyserial's `list_ports_osx` walks up from each `IOSerialBSDClient` to its
/// `IOUSBHostDevice` (or legacy `IOUSBDevice`); `ioreg -r -c` prints those
/// device subtrees, so walking down them reaches the same pairs. Returns null
/// when `ioreg` is unavailable or its output cannot be parsed.
Future<Map<String, SerialPortDescriptor>?> queryIoregPorts() async {
  for (final usbClass in const ['IOUSBHostDevice', 'IOUSBDevice']) {
    final output = await runForOutput('ioreg', [
      '-a',
      '-l',
      '-r',
      '-c',
      usbClass,
    ]);
    if (output == null) return null;
    try {
      final ports = parseIoregPlist(output);
      if (ports.isNotEmpty) return ports;
    } on XmlException {
      return null;
    }
  }
  return const {};
}

/// Parses `ioreg -a -l -r -c <usb device class>` output.
Map<String, SerialPortDescriptor> parseIoregPlist(String xml) {
  if (xml.trim().isEmpty) return const {};
  final top = XmlDocument.parse(xml).rootElement.childElements.firstOrNull;
  if (top == null) return const {};
  final value = _plistValue(top);
  final roots = value is List ? value : [value];

  final clients = <_SerialClient>[];
  void walk(
    Object? node,
    Map<String, Object?>? usbDevice,
    Map<String, Object?>? usbInterface,
  ) {
    if (node is! Map<String, Object?>) return;
    final objectClass = node['IOObjectClass'];
    // pyserial matches the exact class, preferring IOUSBHostDevice.
    if (objectClass == 'IOUSBHostDevice' ||
        (objectClass == 'IOUSBDevice' &&
            usbDevice?['IOObjectClass'] != 'IOUSBHostDevice')) {
      usbDevice = node;
    }
    if (objectClass == 'IOUSBInterface') usbInterface = node;
    final callout = node['IOCalloutDevice'];
    if (callout is String && callout.isNotEmpty) {
      clients.add(_SerialClient(callout, usbDevice, usbInterface));
    }
    final children = node['IORegistryEntryChildren'];
    if (children is List) {
      for (final child in children) {
        walk(child, usbDevice, usbInterface);
      }
    }
  }

  for (final root in roots) {
    walk(root, null, null);
  }

  // pyserial `scan_interfaces` + `search_for_locationID_in_interfaces`: an
  // interface name is matched to a port through the USB locationID, and the
  // first interface seen for a locationID wins. Only the legacy
  // IOUSBInterface class is consulted, so modern systems usually report none.
  final interfaceNames = <int, String?>{};
  for (final client in clients) {
    final usbInterface = client.usbInterface;
    if (usbInterface == null) continue;
    final locationId = _int(usbInterface['locationID']);
    if (locationId == null) continue;
    interfaceNames.putIfAbsent(
      locationId,
      () => _string(usbInterface['USB Interface Name']),
    );
  }

  final ports = <String, SerialPortDescriptor>{};
  for (final client in clients) {
    final usbDevice = client.usbDevice;
    if (usbDevice == null) {
      ports[client.path] = SerialPortDescriptor(path: client.path);
      continue;
    }
    final locationId = _int(usbDevice['locationID']);
    ports[client.path] = SerialPortDescriptor.usb(
      path: client.path,
      vid: _int(usbDevice['idVendor']),
      pid: _int(usbDevice['idProduct']),
      serialNumber: _string(usbDevice['USB Serial Number']),
      product:
          _string(usbDevice['IORegistryEntryName']) ??
          SerialPortDescriptor.notAvailable,
      manufacturer: _string(usbDevice['USB Vendor Name']),
      location: locationId == null ? null : ioregLocationToString(locationId),
      interface: locationId == null ? null : interfaceNames[locationId],
    );
  }
  return ports;
}

/// pyserial `location_to_string`: `0x14200000` becomes `20-2`.
String ioregLocationToString(int locationId) {
  final buffer = StringBuffer('${locationId >> 24}-');
  var remaining = locationId;
  var parts = 0;
  while (remaining & 0xf00000 != 0) {
    if (parts++ > 0) buffer.write('.');
    buffer.write((remaining >> 20) & 0xf);
    remaining <<= 4;
  }
  return buffer.toString();
}

class _SerialClient {
  const _SerialClient(this.path, this.usbDevice, this.usbInterface);

  final String path;
  final Map<String, Object?>? usbDevice;
  final Map<String, Object?>? usbInterface;
}

Object? _plistValue(XmlElement element) {
  final text = element.innerText;
  return switch (element.name.local) {
    'dict' => _plistDict(element),
    'array' => [for (final child in element.childElements) _plistValue(child)],
    // 64-bit unsigned registry values can overflow int; keep them as text.
    'integer' => int.tryParse(text.trim()) ?? text.trim(),
    'real' => double.tryParse(text.trim()),
    'true' => true,
    'false' => false,
    _ => text,
  };
}

Map<String, Object?> _plistDict(XmlElement element) {
  final map = <String, Object?>{};
  String? key;
  for (final child in element.childElements) {
    if (child.name.local == 'key') {
      key = child.innerText;
    } else if (key != null) {
      map[key] = _plistValue(child);
      key = null;
    }
  }
  return map;
}

int? _int(Object? value) => value is int ? value : null;

String? _string(Object? value) => value is String ? value : null;
