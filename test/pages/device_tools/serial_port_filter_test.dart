import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/models/board_manager.dart';
import 'package:pyrite_ide/core/models/serial_port_descriptor.dart';
import 'package:pyrite_ide/core/services/serial/serial_provider.dart';
import 'package:pyrite_ide/pages/device_tools/main.dart';

/// A [SerialNotifier] holding fixed ports and never touching the system.
class _FakeSerialNotifier extends SerialNotifier {
  _FakeSerialNotifier(super.ref, List<SerialPortDescriptor> ports) {
    state = SerialProviderState(ports: ports);
  }

  @override
  Future<void> performUpdate() async {}

  @override
  Future<void> refresh() async {}
}

void main() {
  final ports = [
    const SerialPortDescriptor(path: '/dev/ttyS10'),
    const SerialPortDescriptor(
      path: '/dev/ttyS0',
      description: 'ttyS0',
      hwid: 'PNP0501',
    ),
    const SerialPortDescriptor(path: '/dev/ttyS3', hiddenInternal: true),
    SerialPortDescriptor.usb(
      path: '/dev/ttyACM0',
      vid: 0x303a,
      pid: 0x1001,
      product: 'USB JTAG/serial debug unit',
    ),
    const SerialPortDescriptor(path: '/dev/ttyS2'),
  ];

  Future<void> pumpPanel(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serialProvider.overrideWith((ref) => _FakeSerialNotifier(ref, ports)),
        ],
        child: const MaterialApp(home: Scaffold(body: Tools(compact: true))),
      ),
    );
  }

  List<String?> listedPaths(WidgetTester tester) => tester
      .widgetList<ExpansionTile>(find.byType(ExpansionTile))
      .map((tile) => (tile.title as Text).data)
      .toList();

  testWidgets('lists pyrcli --all ports, USB first in natural order', (
    tester,
  ) async {
    await pumpPanel(tester);
    expect(listedPaths(tester), [
      '/dev/ttyACM0',
      '/dev/ttyS0',
      '/dev/ttyS2',
      '/dev/ttyS10',
    ]);
    expect(find.textContaining('个串口'), findsNothing);
  });

  testWidgets('a query narrows the list and shows the count', (tester) async {
    await pumpPanel(tester);
    await tester.enterText(find.byType(TextField), 'ttyS');
    await tester.pump();
    expect(listedPaths(tester), ['/dev/ttyS0', '/dev/ttyS2', '/dev/ttyS10']);
    expect(find.text('显示 3 / 4 个串口'), findsOneWidget);
  });

  testWidgets('no match offers to clear the filter', (tester) async {
    await pumpPanel(tester);
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(find.text('没有匹配的串口'), findsOneWidget);

    await tester.tap(find.text('清除过滤'));
    await tester.pump();
    expect(listedPaths(tester), hasLength(4));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('an invalid regex is reported', (tester) async {
    await pumpPanel(tester);
    await tester.tap(find.text('.*'));
    await tester.enterText(find.byType(TextField), '[');
    await tester.pump();
    expect(find.text('正则表达式无效'), findsOneWidget);
    expect(find.byType(ExpansionTile), findsNothing);
  });

  testWidgets('the filter menu narrows to USB devices', (tester) async {
    await pumpPanel(tester);
    await tester.tap(find.byTooltip('过滤选项'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('仅显示 USB 设备（有 VID/PID）'));
    await tester.pumpAndSettle();
    expect(listedPaths(tester), ['/dev/ttyACM0']);
    expect(find.text('显示 1 / 4 个串口'), findsOneWidget);
  });

  testWidgets('expanded rows show the pyserial fields', (tester) async {
    await pumpPanel(tester);
    await tester.tap(find.text('/dev/ttyACM0'));
    await tester.pumpAndSettle();
    expect(find.text('USB VID:PID=303A:1001'), findsOneWidget);
    expect(find.text('303A:1001'), findsOneWidget);
    expect(find.text('硬件 ID'), findsOneWidget);
  });
}
