import 'dart:async';

import 'package:flserial/serial_scanner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/models/serial_port_descriptor.dart';
import 'package:pyrite_ide/core/services/serial/port_catalog/serial_port_catalog.dart';

void main() {
  final com3 = SerialPortInfo('COM3', 'Windows Serial Device');
  final com5 = SerialPortInfo('COM5', 'Windows Serial Device');
  final ch340 = SerialPortDescriptor.usb(
    path: 'COM5',
    vid: 0x1a86,
    pid: 0x7523,
    product: 'USB-SERIAL CH340',
  );

  test('merges metadata and marks ports the query did not report', () async {
    final catalog = SerialPortCatalog(
      metadataQuery: () async => {'COM5': ch340},
    );
    final ports = await catalog.enrich([com3, com5]);
    expect(ports[0], const SerialPortDescriptor(path: 'COM3'));
    expect(ports[1], ch340);
  });

  test('queries again only when the port set changes or on refresh', () async {
    var queries = 0;
    final catalog = SerialPortCatalog(
      metadataQuery: () async {
        queries++;
        return {'COM5': ch340};
      },
    );
    await catalog.enrich([com3, com5]);
    await catalog.enrich([com5, com3]);
    expect(queries, 1);

    await catalog.enrich([com5]);
    expect(queries, 2);

    await catalog.enrich([com5], refreshMetadata: true);
    expect(queries, 3);
  });

  test('falls back to flserial descriptions when the query fails', () async {
    final failing = SerialPortCatalog(metadataQuery: () async => null);
    expect(
      (await failing.enrich([com3])).single.description,
      'Windows Serial Device',
    );

    final throwing = SerialPortCatalog(
      metadataQuery: () => Future.error(StateError('no ioreg')),
    );
    expect(
      (await throwing.enrich([com3])).single.description,
      'Windows Serial Device',
    );
  });

  test('concurrent scans share one in-flight query', () async {
    var queries = 0;
    final gate = Completer<Map<String, SerialPortDescriptor>?>();
    final catalog = SerialPortCatalog(
      metadataQuery: () {
        queries++;
        return gate.future;
      },
    );
    final first = catalog.enrich([com5]);
    final second = catalog.enrich([com5]);
    gate.complete({'COM5': ch340});
    expect((await first).single, ch340);
    expect((await second).single, ch340);
    expect(queries, 1);
  });
}
