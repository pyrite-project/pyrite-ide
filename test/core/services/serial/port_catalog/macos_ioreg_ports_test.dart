import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/serial/port_catalog/macos_ioreg_ports.dart';
import 'package:xml/xml.dart';

void main() {
  final fixture = File(
    'test/fixtures/serial/ioreg_usb.plist',
  ).readAsStringSync();

  test('pairs each serial client with its USB device', () {
    final ports = parseIoregPlist(fixture);
    expect(ports.keys, ['/dev/cu.usbmodem1101', '/dev/cu.usbserial-A50285BI']);

    final esp = ports['/dev/cu.usbmodem1101']!;
    expect(esp.vidPid, '303A:1001');
    expect(esp.manufacturer, 'Espressif');
    expect(esp.product, 'USB JTAG/serial debug unit');
    // Only the legacy IOUSBInterface class provides an interface name.
    expect(esp.interface, isNull);
    expect(esp.description, 'USB JTAG/serial debug unit');
    expect(
      esp.hwid,
      'USB VID:PID=303A:1001 SER=F4:12:FA:00:00:01 LOCATION=20-2',
    );
  });

  test('legacy devices pick up the interface name by locationID', () {
    final ftdi = parseIoregPlist(fixture)['/dev/cu.usbserial-A50285BI']!;
    expect(ftdi.interface, 'FT232R Interface');
    expect(ftdi.description, 'FT232R USB UART - FT232R Interface');
    expect(ftdi.hwid, 'USB VID:PID=0403:6001 SER=A50285BI LOCATION=20-3.2');
  });

  test('location strings match pyserial location_to_string', () {
    expect(ioregLocationToString(0x14200000), '20-2');
    expect(ioregLocationToString(0x14320000), '20-3.2');
    expect(ioregLocationToString(0x01000000), '1-');
  });

  test('empty output has no ports and malformed output throws', () {
    expect(parseIoregPlist(''), isEmpty);
    expect(
      () => parseIoregPlist('<plist><array>'),
      throwsA(isA<XmlException>()),
    );
  });
}
