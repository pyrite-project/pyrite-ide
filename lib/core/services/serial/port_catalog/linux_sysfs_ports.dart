import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pyrite_ide/core/models/serial_port_descriptor.dart';

/// Device name prefixes pyserial 3.5 globs in `/dev`
/// (`serial.tools.list_ports_linux.comports`).
const linuxSerialDevicePrefixes = <String>[
  'ttyS', // built-in serial ports
  'ttyUSB', // usb-serial with its own driver
  'ttyXRUSB', // xr-usb-serial port exar
  'ttyACM', // usb-serial with the CDC-ACM profile
  'ttyAMA', // ARM internal port (Raspberry Pi)
  'rfcomm', // Bluetooth serial
  'ttyAP', // Advantech multi-port serial controllers
];

/// Lists the same ports as pyserial's Linux `comports()`, with the fields its
/// `SysFS` class reads.
///
/// Ports pyserial drops as "non-present internal serial ports" are returned
/// with [SerialPortDescriptor.hiddenInternal] set instead of being removed.
Future<List<SerialPortDescriptor>> scanLinuxSysfs({
  String sysRoot = '/sys',
  String devRoot = '/dev',
}) async {
  final devDir = Directory(devRoot);
  if (!await devDir.exists()) return const [];
  final paths = <String>[];
  await for (final entity in devDir.list(followLinks: false)) {
    final name = p.basename(entity.path);
    if (linuxSerialDevicePrefixes.any(name.startsWith)) paths.add(entity.path);
  }
  return [
    for (final path in paths) await describeLinuxPort(path, sysRoot: sysRoot),
  ];
}

/// Port of pyserial's `list_ports_linux.SysFS.__init__` for one device node.
Future<SerialPortDescriptor> describeLinuxPort(
  String devicePath, {
  String sysRoot = '/sys',
}) async {
  final name = p.basename(devicePath);
  var sysDevice = await _resolve(
    p.join(sysRoot, 'class', 'tty', name, 'device'),
  );
  String? subsystem;
  if (sysDevice != null) {
    subsystem = await _subsystemOf(sysDevice);
    // Linux 6.5 put serial-core "ctrl" and "port" devices of the serial-base
    // bus between the tty and its controller. pyserial 3.5 predates that and
    // reads `serial-base` here, which breaks both its pnp/amba descriptions
    // and its hiding of non-present `platform` ports. Climbing past those
    // layers restores the subsystem pyserial was written against.
    while (subsystem == 'serial-base') {
      final parent = p.dirname(sysDevice!);
      if (parent == sysDevice) break;
      sysDevice = parent;
      subsystem = await _subsystemOf(sysDevice);
    }
  }

  final String? usbInterfacePath = switch (subsystem) {
    'usb-serial' => p.dirname(sysDevice!),
    'usb' => sysDevice,
    _ => null,
  };

  final SerialPortDescriptor port;
  if (usbInterfacePath != null) {
    final usbDevicePath = p.dirname(usbInterfacePath);
    final numInterfaces =
        int.tryParse(await _readLine(usbDevicePath, 'bNumInterfaces') ?? '') ??
        1;
    port = SerialPortDescriptor.usb(
      path: devicePath,
      vid: _parseHex(await _readLine(usbDevicePath, 'idVendor')),
      pid: _parseHex(await _readLine(usbDevicePath, 'idProduct')),
      serialNumber: await _readLine(usbDevicePath, 'serial'),
      // Multi-interface devices such as the FT4232 are told apart by interface.
      location: numInterfaces > 1
          ? p.basename(usbInterfacePath)
          : p.basename(usbDevicePath),
      manufacturer: await _readLine(usbDevicePath, 'manufacturer'),
      product: await _readLine(usbDevicePath, 'product'),
      interface: await _readLine(usbInterfacePath, 'interface'),
    );
  } else if (subsystem == 'pnp') {
    port = SerialPortDescriptor(
      path: devicePath,
      description: name,
      hwid:
          await _readLine(sysDevice!, 'id') ??
          SerialPortDescriptor.notAvailable,
    );
  } else if (subsystem == 'amba') {
    port = SerialPortDescriptor(
      path: devicePath,
      description: name,
      hwid: p.basename(sysDevice!),
    );
  } else {
    port = SerialPortDescriptor(path: devicePath);
  }

  final linkTarget = await FileSystemEntity.isLink(devicePath)
      ? await _resolve(devicePath)
      : null;
  return port.copyWith(
    hwid: linkTarget == null ? null : '${port.hwid} LINK=$linkTarget',
    hiddenInternal: subsystem == 'platform',
  );
}

/// `os.path.realpath`, or null when the path does not exist.
Future<String?> _resolve(String path) async {
  if (await FileSystemEntity.type(path) == FileSystemEntityType.notFound) {
    return null;
  }
  try {
    return await File(path).resolveSymbolicLinks();
  } on FileSystemException {
    return null;
  }
}

Future<String?> _subsystemOf(String sysDevice) async {
  final target = await _resolve(p.join(sysDevice, 'subsystem'));
  return target == null ? null : p.basename(target);
}

/// pyserial `SysFS.read_line`: the first line, stripped, or null when the
/// attribute cannot be read.
Future<String?> _readLine(String dir, String attribute) async {
  try {
    final bytes = await File(p.join(dir, attribute)).readAsBytes();
    final text = utf8.decode(bytes, allowMalformed: true);
    return text.split('\n').first.trim();
  } on FileSystemException {
    return null;
  }
}

int? _parseHex(String? value) =>
    value == null ? null : int.tryParse(value, radix: 16);
