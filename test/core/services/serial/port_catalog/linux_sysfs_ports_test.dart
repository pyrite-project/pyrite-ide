import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pyrite_ide/core/models/serial_port_descriptor.dart';
import 'package:pyrite_ide/core/services/serial/port_catalog/linux_sysfs_ports.dart';

/// Builds a miniature `/sys` and `/dev` laid out like a 6.5+ kernel, where
/// serial-core ports sit behind serial-base "ctrl" and "port" devices.
class _SysfsFixture {
  _SysfsFixture(this.root);

  final Directory root;

  String get sys => p.join(root.path, 'sys');
  String get dev => p.join(root.path, 'dev');

  void dir(String path) =>
      Directory(p.join(sys, path)).createSync(recursive: true);

  void attr(String dirPath, String name, String value) {
    File(p.join(sys, dirPath, name))
      ..createSync(recursive: true)
      ..writeAsStringSync('$value\n');
  }

  void subsystem(String devicePath, String bus) {
    dir('bus/$bus');
    Link(
      p.join(sys, devicePath, 'subsystem'),
    ).createSync(p.join(sys, 'bus', bus));
  }

  void tty(String name, String devicePath) {
    dir('class/tty/$name');
    Link(
      p.join(sys, 'class/tty', name, 'device'),
    ).createSync(p.join(sys, devicePath));
    File(p.join(dev, name)).createSync(recursive: true);
  }

  /// A serial-core port behind the two serial-base layers.
  String serialCorePort(String controller, String bus, {required String port}) {
    final ctrl = '$controller/${p.basename(controller)}:0';
    final portDevice = '$ctrl/${p.basename(controller)}:0.$port';
    dir(portDevice);
    subsystem(controller, bus);
    subsystem(ctrl, 'serial-base');
    subsystem(portDevice, 'serial-base');
    return portDevice;
  }
}

void main() {
  late Directory temp;
  late _SysfsFixture fx;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('pyrite_sysfs_');
    fx = _SysfsFixture(temp);
    Directory(fx.dev).createSync(recursive: true);

    // ESP32-S3 USB-Serial/JTAG over CDC-ACM: a two-interface device.
    const esp = 'devices/pci0000:00/0000:00:14.0/usb1/1-2';
    fx.dir('$esp/1-2:1.0');
    fx.attr(esp, 'idVendor', '303a');
    fx.attr(esp, 'idProduct', '1001');
    fx.attr(esp, 'serial', 'F4:12:FA:00:00:01');
    fx.attr(esp, 'manufacturer', 'Espressif');
    fx.attr(esp, 'product', 'USB JTAG/serial debug unit');
    fx.attr(esp, 'bNumInterfaces', ' 2');
    fx.subsystem('$esp/1-2:1.0', 'usb');
    fx.tty('ttyACM0', '$esp/1-2:1.0');

    // CH340 behind the usb-serial bus, one interface, no serial number.
    const ch340 = 'devices/pci0000:00/0000:00:14.0/usb1/1-3';
    fx.dir('$ch340/1-3:1.0/ttyUSB0');
    fx.attr(ch340, 'idVendor', '1a86');
    fx.attr(ch340, 'idProduct', '7523');
    fx.attr(ch340, 'product', 'USB Serial');
    fx.attr(ch340, 'bNumInterfaces', ' 1');
    fx.attr('$ch340/1-3:1.0', 'interface', 'CH340 serial');
    fx.subsystem('$ch340/1-3:1.0/ttyUSB0', 'usb-serial');
    fx.tty('ttyUSB0', '$ch340/1-3:1.0/ttyUSB0');

    final pnpPort = fx.serialCorePort('devices/pnp0/00:02', 'pnp', port: '0');
    fx.attr('devices/pnp0/00:02', 'id', 'PNP0501');
    fx.tty('ttyS0', pnpPort);

    fx.tty(
      'ttyS1',
      fx.serialCorePort('devices/platform/serial8250', 'platform', port: '1'),
    );
    fx.tty(
      'ttyAMA0',
      fx.serialCorePort('devices/platform/fe201000.serial', 'amba', port: '0'),
    );

    // Not a pyserial glob match.
    File(p.join(fx.dev, 'tty0')).createSync();
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Future<Map<String, SerialPortDescriptor>> scan() async {
    final ports = await scanLinuxSysfs(sysRoot: fx.sys, devRoot: fx.dev);
    return {for (final port in ports) port.name: port};
  }

  test('lists exactly the device nodes pyserial globs', () async {
    final ports = await scan();
    expect(
      ports.keys,
      unorderedEquals(['ttyACM0', 'ttyUSB0', 'ttyS0', 'ttyS1', 'ttyAMA0']),
    );
    expect(ports['ttyACM0']!.path, p.join(fx.dev, 'ttyACM0'));
  });

  test('CDC-ACM port reads USB info like pyserial', () async {
    final acm = (await scan())['ttyACM0']!;
    expect(acm.description, 'USB JTAG/serial debug unit');
    expect(
      acm.hwid,
      'USB VID:PID=303A:1001 SER=F4:12:FA:00:00:01 LOCATION=1-2:1.0',
    );
    expect(acm.vid, 0x303a);
    expect(acm.pid, 0x1001);
    expect(acm.manufacturer, 'Espressif');
    expect(acm.interface, isNull);
    expect(acm.hiddenInternal, isFalse);
  });

  test('usb-serial port uses the interface and device location', () async {
    final usb = (await scan())['ttyUSB0']!;
    expect(usb.description, 'USB Serial - CH340 serial');
    expect(usb.hwid, 'USB VID:PID=1A86:7523 LOCATION=1-3');
    expect(usb.serialNumber, isNull);
  });

  test(
    'serial-base layers are skipped to reach pnp, platform and amba',
    () async {
      final ports = await scan();

      final pnp = ports['ttyS0']!;
      expect(pnp.description, 'ttyS0');
      expect(pnp.hwid, 'PNP0501');
      expect(pnp.hiddenInternal, isFalse);

      final platform = ports['ttyS1']!;
      expect(platform.description, SerialPortDescriptor.notAvailable);
      expect(platform.hiddenInternal, isTrue);

      final amba = ports['ttyAMA0']!;
      expect(amba.description, 'ttyAMA0');
      expect(amba.hwid, 'fe201000.serial');
    },
  );

  test('a missing dev root lists nothing', () async {
    final ports = await scanLinuxSysfs(
      sysRoot: fx.sys,
      devRoot: p.join(temp.path, 'missing'),
    );
    expect(ports, isEmpty);
  });
}
