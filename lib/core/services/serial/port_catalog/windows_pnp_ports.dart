import 'dart:convert';
import 'dart:typed_data';

import 'package:pyrite_ide/core/models/serial_port_descriptor.dart';
import 'package:pyrite_ide/core/services/serial/port_catalog/process_output.dart';

/// Lists Ports and Modem class devices the way pyserial's
/// `list_ports_windows.comports` does through SetupAPI: the COM name comes
/// from the device's `Device Parameters\PortName`, the description from its
/// friendly name and the hwid from its instance ID.
const _windowsPortsScript = r'''
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
$ports = @(Get-CimInstance -ClassName Win32_PnPEntity -Filter "PNPClass='Ports' OR PNPClass='Modem'" | ForEach-Object {
  $key = 'HKLM:\SYSTEM\CurrentControlSet\Enum\' + $_.PNPDeviceID + '\Device Parameters'
  [pscustomobject]@{
    port = (Get-ItemProperty -LiteralPath $key -Name PortName).PortName
    name = $_.Name
    id = $_.PNPDeviceID
    mfg = $_.Manufacturer
  }
})
ConvertTo-Json -InputObject $ports -Compress
''';

final _usbInstanceId = RegExp(
  r'VID_([0-9a-f]{4})(&PID_([0-9a-f]{4}))?(&MI_(\d{2}))?(\\(.*))?',
  caseSensitive: false,
);
final _ftdiInstanceId = RegExp(
  r'VID_([0-9a-f]{4})\+PID_([0-9a-f]{4})(\+(\w+))?',
  caseSensitive: false,
);
final _plainSerialNumber = RegExp(r'^\w+$');

/// Queries Windows PnP for serial port metadata, keyed by COM name.
/// Returns null when PowerShell is unavailable or fails.
Future<Map<String, SerialPortDescriptor>?> queryWindowsPnpPorts() async {
  final output = await runForOutput('powershell.exe', [
    '-NoProfile',
    '-NonInteractive',
    '-EncodedCommand',
    _encodePowerShellCommand(_windowsPortsScript),
  ]);
  if (output == null) return null;
  try {
    return {for (final port in parseWindowsPnpJson(output)) port.path: port};
  } on FormatException {
    return null;
  }
}

/// Parses the JSON printed by [_windowsPortsScript].
///
/// Accepts both an array and the single object older PowerShell versions
/// print for one result. Differences from pyserial: it reads a composite
/// device's serial number and its location from the parent device node,
/// which this query does not, so those stay null here.
List<SerialPortDescriptor> parseWindowsPnpJson(String json) {
  final text = json.replaceFirst('\uFEFF', '').trim();
  if (text.isEmpty) return const [];
  final decoded = jsonDecode(text);
  final items = decoded is List ? decoded : [decoded];
  final ports = <SerialPortDescriptor>[];
  for (final item in items) {
    if (item is! Map) continue;
    final portName = item['port'];
    // pyserial: "we could check for names starting with COM or just exclude LPT".
    if (portName is! String || portName.isEmpty || portName.startsWith('LPT')) {
      continue;
    }
    ports.add(
      _describe(
        portName,
        instanceId: switch (item['id']) {
          final String id => id,
          _ => '',
        },
        description: switch (item['name']) {
          final String name => name,
          _ => SerialPortDescriptor.notAvailable,
        },
        manufacturer: switch (item['mfg']) {
          final String mfg => mfg,
          _ => null,
        },
      ),
    );
  }
  return ports;
}

SerialPortDescriptor _describe(
  String portName, {
  required String instanceId,
  required String description,
  String? manufacturer,
}) {
  int? vid;
  int? pid;
  String? serialNumber;
  var hwid = instanceId;
  if (instanceId.startsWith('USB')) {
    final match = _usbInstanceId.firstMatch(instanceId);
    if (match != null) {
      vid = int.parse(match.group(1)!, radix: 16);
      if (match.group(3) != null) pid = int.parse(match.group(3)!, radix: 16);
      // Composite devices put an ephemeral Windows ID here, not a serial.
      final tail = match.group(7);
      if (tail != null && _plainSerialNumber.hasMatch(tail)) {
        serialNumber = tail;
      }
    }
    hwid = SerialPortDescriptor.usbInfo(
      vid: vid,
      pid: pid,
      serialNumber: serialNumber,
    );
  } else if (instanceId.startsWith('FTDIBUS')) {
    final match = _ftdiInstanceId.firstMatch(instanceId);
    if (match != null) {
      vid = int.parse(match.group(1)!, radix: 16);
      pid = int.parse(match.group(2)!, radix: 16);
      serialNumber = match.group(4);
    }
    // The FTDI driver hides the USB location, as in pyserial.
    hwid = SerialPortDescriptor.usbInfo(
      vid: vid,
      pid: pid,
      serialNumber: serialNumber,
    );
  }
  return SerialPortDescriptor(
    path: portName,
    description: description,
    hwid: hwid,
    vid: vid,
    pid: pid,
    serialNumber: serialNumber,
    manufacturer: manufacturer,
  );
}

/// `-EncodedCommand` takes base64 UTF-16LE, which avoids quoting the script
/// through the Windows command line.
String _encodePowerShellCommand(String script) {
  final units = script.codeUnits;
  final bytes = ByteData(units.length * 2);
  for (var i = 0; i < units.length; i++) {
    bytes.setUint16(i * 2, units[i], Endian.little);
  }
  return base64Encode(bytes.buffer.asUint8List());
}
