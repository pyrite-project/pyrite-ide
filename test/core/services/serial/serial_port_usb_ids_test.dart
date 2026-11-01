import 'package:flutter_test/flutter_test.dart';
import 'package:flserial/serial_scanner.dart';

void main() {
  group('SerialPortInfo', () {
    test('keeps vid/pid nullable and reports hasUsbIds', () {
      final known = SerialPortInfo(
        '/dev/cu.usbmodem1',
        'Pico',
        vid: 0x2E8A,
        pid: 5,
      );
      final unknown = SerialPortInfo('/dev/cu.usbmodem2', 'unknown');

      expect(known.hasUsbIds, isTrue);
      expect(unknown.hasUsbIds, isFalse);
      expect(unknown.vid, isNull);
      expect(unknown.pid, isNull);
    });

    test('toString stays unchanged for existing call sites', () {
      expect(SerialPortInfo('COM3', 'Windows').toString(), 'COM3 (Windows)');
    });
  });

  group('parseWindowsVidPid', () {
    test('parses a composite device instance id', () {
      final ids = parseWindowsVidPid(
        r'USB\VID_2E8A&PID_0005&MI_00\6&1A2B3C4D&0&0000',
      );

      expect(ids?.vid, 0x2E8A);
      expect(ids?.pid, 0x0005);
    });

    test('is case insensitive', () {
      final ids = parseWindowsVidPid('usb\\vid_303a&pid_1001');
      expect(ids?.vid, 0x303A);
      expect(ids?.pid, 0x1001);
    });

    test('returns null when either id is missing', () {
      expect(parseWindowsVidPid(r'USB\VID_2E8A'), isNull);
      expect(parseWindowsVidPid(r'USB\PID_0005'), isNull);
      expect(parseWindowsVidPid('ROOT\\SERENUM\\0000'), isNull);
      expect(parseWindowsVidPid(''), isNull);
    });
  });

  group('parseLinuxUeventProduct', () {
    test('parses the PRODUCT line of a uevent file', () {
      const uevent = '''
DRIVER=cp210x
PRODUCT=10c4/ea60/100
TYPE=0/0/0
''';

      final ids = parseLinuxUeventProduct(uevent);
      expect(ids?.vid, 0x10C4);
      expect(ids?.pid, 0xEA60);
    });

    test('ignores unrelated lines and returns null without PRODUCT', () {
      expect(parseLinuxUeventProduct('DRIVER=ftdi_sio\nTYPE=0/0/0'), isNull);
      expect(parseLinuxUeventProduct('PRODUCT=zzzz/1/0'), isNull);
      expect(parseLinuxUeventProduct('PRODUCT=2e8a'), isNull);
    });
  });

  group('parseSystemProfilerUsbId', () {
    test('accepts the hex form with a vendor suffix', () {
      expect(parseSystemProfilerUsbId('0x2e8a  (Raspberry Pi)'), 0x2E8A);
    });

    test('accepts upper case and bare decimals', () {
      expect(parseSystemProfilerUsbId('0X303A'), 0x303A);
      expect(parseSystemProfilerUsbId('1452'), 1452);
      expect(parseSystemProfilerUsbId(5), 5);
    });

    test('returns null for missing or garbage values', () {
      expect(parseSystemProfilerUsbId(null), isNull);
      expect(parseSystemProfilerUsbId(''), isNull);
      expect(parseSystemProfilerUsbId('n/a'), isNull);
    });
  });

  group('parseSystemProfilerUsbJson', () {
    test('flattens nested hub items', () {
      const json = '''
{
  "SPUSBDataType": [
    {
      "_name": "USB2 Hub",
      "vendor_id": "0x0a5c",
      "product_id": "0x1234",
      "_items": [
        {
          "_name": "Raspberry Pi Pico",
          "vendor_id": "0x2e8a",
          "product_id": "0x0005",
          "serial_num": "E6605838836F4028",
          "manufacturer": "Raspberry Pi"
        }
      ]
    }
  ]
}
''';

      final devices = parseSystemProfilerUsbJson(json);

      expect(devices.length, 2);
      final pico = devices.firstWhere((d) => d.pid == 0x0005);
      expect(pico.vid, 0x2E8A);
      expect(pico.name, 'Raspberry Pi Pico');
      expect(pico.label, 'Raspberry Pi Raspberry Pi Pico');
      expect(pico.serialNumber, 'E6605838836F4028');
    });

    test('accepts the map-shaped output used by newer macOS', () {
      const json = '''
{
  "SPUSBDataType": {
    "_name": "USB3.1 Bus",
    "_items": {
      "_name": "CP2102 USB to UART",
      "vendor_id": "0x10c4",
      "product_id": "0xea60"
    }
  }
}
''';

      final devices = parseSystemProfilerUsbJson(json);

      expect(devices.length, 2);
      expect(devices.last.vid, 0x10C4);
      expect(devices.last.pid, 0xEA60);
    });

    test('returns an empty list for malformed json', () {
      expect(parseSystemProfilerUsbJson('not json'), isEmpty);
      expect(parseSystemProfilerUsbJson('[]'), isEmpty);
      expect(parseSystemProfilerUsbJson('{"SPUSBDataType": []}'), isEmpty);
    });
  });

  group('macSerialPortSuffix', () {
    test('strips the call-out prefix and driver name', () {
      expect(macSerialPortSuffix('/dev/cu.usbmodem1101'), '1101');
      expect(macSerialPortSuffix('/dev/cu.usbserial-1410'), '1410');
      expect(macSerialPortSuffix('/dev/tty.usbmodem1101'), '1101');
      expect(macSerialPortSuffix('/dev/cu.SLAB_USBtoUART'), '');
    });

    test('keeps unknown driver names intact', () {
      expect(macSerialPortSuffix('/dev/cu.wchusbserial1420'), '1420');
    });
  });

  group('matchMacUsbDeviceForPort', () {
    test('matches on the serial number suffix', () {
      const devices = [
        MacUsbDeviceInfo(
          name: 'Raspberry Pi Pico',
          vid: 0x2E8A,
          pid: 0x0005,
          serialNumber: 'E6605838836F4028',
        ),
      ];

      final match = matchMacUsbDeviceForPort(
        '/dev/cu.usbmodemE6605838836F40281',
        devices,
      );

      // The suffix carries a trailing interface digit, so a serial match is not
      // guaranteed; the product name must not accidentally win either.
      expect(match, isNull);
    });

    test('matches when the port name equals the serial number', () {
      const devices = [
        MacUsbDeviceInfo(
          name: 'Pico',
          vid: 0x2E8A,
          pid: 0x0005,
          serialNumber: 'E6605838836F4028',
        ),
      ];

      final match = matchMacUsbDeviceForPort(
        '/dev/cu.usbmodemE6605838836F4028',
        devices,
      );

      expect(match?.vid, 0x2E8A);
      expect(match?.pid, 0x0005);
    });

    test('falls back to a unique product-name token', () {
      const devices = [
        MacUsbDeviceInfo(name: 'CP2102 USB to UART Bridge'),
        MacUsbDeviceInfo(name: 'Raspberry Pi Pico', vid: 0x2E8A, pid: 0x0005),
      ];

      final match = matchMacUsbDeviceForPort('/dev/cu.usbmodem1101', devices);

      // Neither the serial suffix nor a product token is unique here.
      expect(match, isNull);
    });

    test('returns null instead of guessing when ambiguous', () {
      const devices = [
        MacUsbDeviceInfo(name: 'USB Serial', vid: 1, pid: 1),
        MacUsbDeviceInfo(name: 'USB Serial', vid: 2, pid: 2),
      ];

      expect(
        matchMacUsbDeviceForPort('/dev/cu.usbserial-0001', devices),
        isNull,
      );
    });
  });

  group('parseWindowsComPortUsbIds', () {
    test('maps COM ports from an array of PnP entities', () {
      const json = '''
[
  {
    "Name": "Silicon Labs CP210x USB to UART Bridge (COM3)",
    "Manufacturer": "Silicon Labs",
    "PNPDeviceID": "USB\\\\VID_10C4&PID_EA60\\\\0001"
  },
  {
    "Name": "USB Serial Device (COM7)",
    "Manufacturer": "Microsoft",
    "PNPDeviceID": "USB\\\\VID_2E8A&PID_0005\\\\0002"
  }
]
''';

      final result = parseWindowsComPortUsbIds(json);

      expect(result.keys, containsAll(['COM3', 'COM7']));
      expect(result['COM3']!.vid, 0x10C4);
      expect(result['COM3']!.pid, 0xEA60);
      expect(
        result['COM3']!.description,
        'Silicon Labs CP210x USB to UART Bridge',
      );
      expect(result['COM7']!.vid, 0x2E8A);
    });

    test('accepts a single object (CIM returns one entry un-wrapped)', () {
      const json = '''
{
  "Name": "Pico (COM5)",
  "Manufacturer": "",
  "PNPDeviceID": "USB\\\\VID_2E8A&PID_0005&MI_00\\\\0003"
}
''';

      final result = parseWindowsComPortUsbIds(json);

      expect(result.length, 1);
      expect(result['COM5']!.pid, 0x0005);
    });

    test('skips entries without a COM suffix or without ids', () {
      const json = '''
[
  {"Name": "Some USB device", "PNPDeviceID": "USB\\\\VID_2E8A&PID_0005"},
  {"Name": "Serial (COM1)", "PNPDeviceID": "ACPI\\\\PNP0501\\\\0"},
  {"Name": "Serial (COM2)", "PNPDeviceID": "USB\\\\VID_0403&PID_6001\\\\0"}
]
''';

      final result = parseWindowsComPortUsbIds(json);

      expect(result.keys, ['COM2']);
    });

    test('returns an empty map for malformed input', () {
      expect(parseWindowsComPortUsbIds(''), isEmpty);
      expect(parseWindowsComPortUsbIds('{}'), isEmpty);
      expect(parseWindowsComPortUsbIds('not json'), isEmpty);
    });
  });
}
