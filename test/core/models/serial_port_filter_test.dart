import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/models/search_options.dart';
import 'package:pyrite_ide/core/models/serial_port_descriptor.dart';
import 'package:pyrite_ide/core/models/serial_port_filter.dart';

void main() {
  final esp = SerialPortDescriptor.usb(
    path: '/dev/ttyACM0',
    vid: 0x303a,
    pid: 0x1001,
    serialNumber: 'F4:12:FA:00:00:01',
    manufacturer: 'Espressif',
    product: 'USB JTAG/serial debug unit',
    location: '1-2:1.0',
  );
  const pnp = SerialPortDescriptor(
    path: '/dev/ttyS0',
    description: 'ttyS0',
    hwid: 'PNP0501',
  );
  const ttyS10 = SerialPortDescriptor(path: '/dev/ttyS10');
  const ttyS2 = SerialPortDescriptor(path: '/dev/ttyS2');
  const placeholder = SerialPortDescriptor(
    path: '/dev/ttyS3',
    hiddenInternal: true,
  );
  final ports = [ttyS10, pnp, placeholder, esp, ttyS2];

  List<String> visiblePaths(SerialPortFilter filter) =>
      filter.apply(ports).visible.map((port) => port.path).toList();

  test('lists what pyrcli scan --all would, USB first in natural order', () {
    final result = const SerialPortFilter().apply(ports);
    expect(result.total, 4);
    expect(result.visible.map((port) => port.path), [
      '/dev/ttyACM0',
      '/dev/ttyS0',
      '/dev/ttyS2',
      '/dev/ttyS10',
    ]);
  });

  test('usbOnly matches plain pyrcli scan', () {
    expect(visiblePaths(const SerialPortFilter(usbOnly: true)), [
      '/dev/ttyACM0',
    ]);
  });

  test('matches description, hwid hex IDs and serial numbers', () {
    expect(visiblePaths(const SerialPortFilter(query: 'jtag')), [
      '/dev/ttyACM0',
    ]);
    expect(visiblePaths(const SerialPortFilter(query: '303a')), [
      '/dev/ttyACM0',
    ]);
    expect(visiblePaths(const SerialPortFilter(query: 'pnp0501')), [
      '/dev/ttyS0',
    ]);
    expect(visiblePaths(const SerialPortFilter(query: 'FA:00')), [
      '/dev/ttyACM0',
    ]);
  });

  test('case sensitivity follows the Aa toggle', () {
    const options = SearchOptions(caseSensitive: true);
    expect(
      visiblePaths(
        const SerialPortFilter(query: 'espressif', options: options),
      ),
      isEmpty,
    );
    expect(
      visiblePaths(
        const SerialPortFilter(query: 'Espressif', options: options),
      ),
      ['/dev/ttyACM0'],
    );
  });

  test('whole word stops prefix matches', () {
    const options = SearchOptions(wholeWord: true);
    expect(
      visiblePaths(const SerialPortFilter(query: 'ttyS1', options: options)),
      isEmpty,
    );
    expect(
      visiblePaths(const SerialPortFilter(query: 'ttyS10', options: options)),
      ['/dev/ttyS10'],
    );
  });

  test('regex mode compiles the query and reports invalid patterns', () {
    const options = SearchOptions(regex: true);
    expect(
      visiblePaths(const SerialPortFilter(query: r'ttyS\d$', options: options)),
      ['/dev/ttyS0', '/dev/ttyS2'],
    );
    final invalid = const SerialPortFilter(
      query: '[',
      options: options,
    ).apply(ports);
    expect(invalid.regexError, isNotNull);
    expect(invalid.visible, isEmpty);
    expect(invalid.total, 4);
  });

  test('regex metacharacters are literal outside regex mode', () {
    expect(visiblePaths(const SerialPortFilter(query: '.*')), isEmpty);
  });

  test('compareNatural orders embedded numbers by value', () {
    final names = ['COM10', 'COM2', 'COM1', 'cu.usbmodem1101', 'COM2a'];
    names.sort(compareNatural);
    expect(names, ['COM1', 'COM2', 'COM2a', 'COM10', 'cu.usbmodem1101']);
  });
}
