import 'package:flserial/flserial.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/models/board_manager.dart';
import 'package:pyrite_ide/core/services/serial/serial_provider.dart';

/// A serial transport the OS refuses to open, standing in for the native port
/// at the hardware boundary.
class _UnopenablePort implements FlSerial {
  _UnopenablePort(this.lastOpenError);

  @override
  final SerialOpenError lastOpenError;

  @override
  Stream<SerialEvent> get events => const Stream.empty();

  @override
  Future<bool> open(String path, SerialConfig config) async => false;

  @override
  Future<void> close() async {}

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const permissionDenied = SerialOpenError(
    SerialOpenFailure.permissionDenied,
    'errno 13',
  );

  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        serialPortFactoryProvider.overrideWithValue(
          () => _UnopenablePort(permissionDenied),
        ),
      ],
    );
  });

  tearDown(() => container.dispose());

  test('connecting to a port the OS refuses reports why', () async {
    final serial = container.read(serialProvider.notifier);

    await expectLater(
      serial.connectPort('/dev/ttyACM0'),
      throwsA(
        isA<SerialOpenException>()
            .having((e) => e.path, 'path', '/dev/ttyACM0')
            .having(
              (e) => e.cause?.reason,
              'reason',
              SerialOpenFailure.permissionDenied,
            ),
      ),
    );
    expect(container.read(serialProvider).isConnected, isFalse);
  });

  test('reconnecting at a new baud rate fails when the port cannot be '
      'reopened', () async {
    final serial = container.read(serialProvider.notifier);
    serial.state = const SerialProviderState(
      selectedPortName: '/dev/ttyACM0',
      isConnected: true,
    );

    expect(await serial.reconnectAtBaud(9600), isFalse);
    expect(container.read(serialProvider).isConnected, isFalse);
  });
}
