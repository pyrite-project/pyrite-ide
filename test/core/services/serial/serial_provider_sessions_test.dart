import 'dart:async';
import 'dart:typed_data';

import 'package:flserial/flserial.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/serial/device_executor.dart';
import 'package:pyrite_ide/core/services/serial/hardware_reset_provider.dart';
import 'package:pyrite_ide/core/services/serial/serial_provider.dart';

/// Stand-in for a native serial port at the OS boundary.
///
/// `flserial` events carry no port identity, so the double exposes its own
/// event controller: a test can emit bytes for one handle and observe where
/// the notifier routes them.
class _FakeSerial implements FlSerial {
  _FakeSerial();

  final StreamController<SerialEvent> _events =
      StreamController<SerialEvent>.broadcast();

  bool closed = false;
  bool disposed = false;
  final List<int> written = <int>[];

  @override
  SerialOpenError? lastOpenError;

  @override
  Stream<SerialEvent> get events => _events.stream;

  void emitData(List<int> bytes) {
    _events.add(SerialEvent(SerialEventType.data, Uint8List.fromList(bytes)));
  }

  void emitDisconnected() {
    _events.add(SerialEvent(SerialEventType.disconnected, null));
  }

  @override
  Future<bool> open(String path, SerialConfig config) async => true;

  @override
  Future<void> close() async => closed = true;

  @override
  Future<void> dispose() async {
    disposed = true;
    await _events.close();
  }

  @override
  Future<SerialControlCapabilities> getControlCapabilities() async =>
      const SerialControlCapabilities(dtr: true, rts: true);

  @override
  Future<void> setDTR(bool active) async {}

  @override
  Future<void> setRTS(bool active) async {}

  @override
  void write(Uint8List data) => written.addAll(data);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late ProviderContainer container;
  late List<_FakeSerial> handles;

  setUp(() {
    handles = <_FakeSerial>[];
    container = ProviderContainer(
      overrides: [
        serialPortFactoryProvider.overrideWithValue(() {
          final handle = _FakeSerial();
          handles.add(handle);
          return handle;
        }),
      ],
    );
  });

  tearDown(() => container.dispose());

  Future<void> connectBoth(SerialNotifier notifier) async {
    await notifier.connectPort('/dev/ttyACM0');
    await notifier.connectPort('/dev/ttyACM1');
    expect(notifier.sessions.sessions, hasLength(2));
  }

  test(
    'hardware reset leaves the registry owning the reopened handle',
    () async {
      final notifier = container.read(serialProvider.notifier);
      await notifier.connectPort('/dev/ttyACM0');
      final original = handles.single;
      final session = notifier.sessions.activeSession!;

      expect(
        await notifier.hardwareReset(HardwareResetStrategy.dtrPulse),
        isTrue,
      );

      final replacement = handles.last;
      expect(handles, hasLength(2));
      expect(notifier.sessions.activeSession?.id, session.id);
      expect(session.serial, same(replacement));
      expect(original.disposed, isTrue);

      // Writes address the reopened handle rather than the closed one.
      notifier.sendBytes(Uint8List.fromList(<int>[7]));
      expect(replacement.written, <int>[7]);

      await notifier.disconnectPort();
      expect(replacement.closed, isTrue);
      expect(replacement.disposed, isTrue);
    },
  );

  test(
    'data from an inactive port never reaches the active transaction',
    () async {
      final notifier = container.read(serialProvider.notifier);
      await connectBoth(notifier);
      final first = handles[0];
      final second = handles[1];

      final received = <List<int>>[];
      container
          .read(serialDataCallbacksProvider.notifier)
          .add((data) => received.add(data.toList()));

      first.emitData(<int>[1, 2, 3]);
      await pumpEventQueue();
      expect(received, isEmpty);

      second.emitData(<int>[4, 5]);
      await pumpEventQueue();
      expect(received, [
        <int>[4, 5],
      ]);

      // Switching boards moves the REPL with the active session.
      notifier.activateSession(
        notifier.sessions.sessionForPort('/dev/ttyACM0')!.id,
      );
      second.emitData(<int>[6]);
      first.emitData(<int>[7]);
      await pumpEventQueue();
      expect(received, [
        <int>[4, 5],
        <int>[7],
      ]);
    },
  );

  test('losing an inactive board leaves the active board connected', () async {
    final notifier = container.read(serialProvider.notifier);
    await connectBoth(notifier);
    final inactive = handles[0];
    final active = handles[1];
    final activeSession = notifier.sessions.activeSession!;

    inactive.emitDisconnected();
    await pumpEventQueue();

    expect(notifier.sessions.sessions, hasLength(1));
    expect(notifier.sessions.activeSession?.id, activeSession.id);
    expect(notifier.sessions.activeSession?.serial, same(active));
    expect(notifier.state.isConnected, isTrue);
    expect(notifier.state.selectedPortName, '/dev/ttyACM1');
    expect(inactive.disposed, isTrue);
    expect(active.disposed, isFalse);
  });

  test('losing the active board promotes the remaining session', () async {
    final notifier = container.read(serialProvider.notifier);
    await connectBoth(notifier);
    final remaining = handles[0];
    final lost = handles[1];
    final lostSession = notifier.sessions.activeSession!;

    lost.emitDisconnected();
    await pumpEventQueue();

    expect(notifier.sessions.sessions, hasLength(1));
    expect(notifier.sessions.activeSession?.id, isNot(lostSession.id));
    expect(notifier.sessions.activeSession?.serial, same(remaining));
    expect(notifier.state.isConnected, isTrue);
    expect(notifier.state.selectedPortName, '/dev/ttyACM0');
    expect(lost.disposed, isTrue);
    expect(remaining.disposed, isFalse);
  });
}
