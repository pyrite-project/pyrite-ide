import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/models/serial_port_descriptor.dart';
import 'package:pyrite_ide/core/services/serial/port_catalog/windows_pnp_ports.dart';

void main() {
  final entries = [
    {
      'port': 'COM5',
      'name': 'USB-SERIAL CH340 (COM5)',
      'id': r'USB\VID_1A86&PID_7523\5&2A3B4C5D&0&3',
      'mfg': 'wch.cn',
    },
    {
      'port': 'COM6',
      'name': 'USB 串行设备 (COM6)',
      'id': r'USB\VID_2E8A&PID_0005\E6614103E7652B2F',
      'mfg': 'Microsoft',
    },
    {
      'port': 'COM7',
      'name': 'USB 串行设备 (COM7)',
      'id': r'USB\VID_303A&PID_1001&MI_00\7&2B1F2C3&0&0000',
      'mfg': 'Microsoft',
    },
    {
      'port': 'COM9',
      'name': 'USB Serial Port (COM9)',
      'id': r'FTDIBUS\VID_0403+PID_6001+A50285BIA\0000',
      'mfg': 'FTDI',
    },
    {
      'port': 'COM1',
      'name': '通讯端口 (COM1)',
      'id': r'ACPI\PNP0501\0',
      'mfg': '(标准端口类型)',
    },
    {
      'port': 'LPT1',
      'name': '打印机端口 (LPT1)',
      'id': r'ACPI\PNP0400\0',
      'mfg': null,
    },
    {'port': null, 'name': 'Standard Modem', 'id': r'ROOT\MODEM\0000'},
  ];

  Map<String, SerialPortDescriptor> parse(Object json) {
    final ports = parseWindowsPnpJson(jsonEncode(json));
    return {for (final port in ports) port.path: port};
  }

  test('skips LPT ports and entries without a PortName', () {
    expect(parse(entries).keys, ['COM5', 'COM6', 'COM7', 'COM9', 'COM1']);
  });

  test('USB instance IDs give VID/PID and plain serial numbers', () {
    final ports = parse(entries);

    final ch340 = ports['COM5']!;
    expect(ch340.description, 'USB-SERIAL CH340 (COM5)');
    expect(ch340.vidPid, '1A86:7523');
    // An ephemeral Windows ID is not a USB serial number.
    expect(ch340.serialNumber, isNull);
    expect(ch340.hwid, 'USB VID:PID=1A86:7523');
    expect(ch340.manufacturer, 'wch.cn');

    final pico = ports['COM6']!;
    expect(pico.serialNumber, 'E6614103E7652B2F');
    expect(pico.hwid, 'USB VID:PID=2E8A:0005 SER=E6614103E7652B2F');
    expect(pico.description, 'USB 串行设备 (COM6)');

    final composite = ports['COM7']!;
    expect(composite.vidPid, '303A:1001');
    expect(composite.serialNumber, isNull);
  });

  test('FTDIBUS instance IDs carry the serial number', () {
    final ftdi = parse(entries)['COM9']!;
    expect(ftdi.vidPid, '0403:6001');
    expect(ftdi.hwid, 'USB VID:PID=0403:6001 SER=A50285BIA');
  });

  test('other buses keep the instance ID as hwid', () {
    final builtIn = parse(entries)['COM1']!;
    expect(builtIn.isUsb, isFalse);
    expect(builtIn.hwid, r'ACPI\PNP0501\0');
    expect(builtIn.description, '通讯端口 (COM1)');
  });

  test('accepts the single object older PowerShell prints, and a BOM', () {
    final single = jsonEncode(entries.first);
    expect(parseWindowsPnpJson(single).single.path, 'COM5');
    expect(parseWindowsPnpJson('\uFEFF$single').single.path, 'COM5');
    expect(parseWindowsPnpJson('  '), isEmpty);
  });
}
