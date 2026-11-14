import 'dart:async';

import 'package:flserial/flserial.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/serial/serial_session_registry.dart';

/// Stand-in for an open [FlSerial] handle.
///
/// The registry only ever closes and disposes the handle, so the double records
/// what it was asked to do and nothing else.
class _FakeSerial implements FlSerial {
  _FakeSerial(this.path);

  final String path;
  bool closed = false;
  bool disposed = false;

  @override
  Future<void> close() async => closed = true;

  @override
  Future<void> dispose() async => disposed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SerialSession _session(
  SerialSessionRegistry registry, {
  required String port,
  _FakeSerial? serial,
}) {
  final handle = serial ?? _FakeSerial(port);
  return registry.create(
    portPath: port,
    serial: handle,
    events: const Stream<SerialEvent>.empty().listen((_) {}),
    baudRate: 115200,
  );
}

void main() {
  group('SerialSessionRegistry', () {
    test('adopting a second port keeps the first one open', () {
      final registry = SerialSessionRegistry();
      final first = _session(registry, port: 'COM3');
      final second = _session(registry, port: 'COM5');

      registry.adopt(first);
      registry.adopt(second);

      expect(registry.sessions, hasLength(2));
      expect(registry.isPortOpen('COM3'), isTrue);
      expect(registry.isPortOpen('COM5'), isTrue);
      // The newest connection becomes the one the IDE talks to.
      expect(registry.activeSession?.portPath, 'COM5');
    });

    test('only one session is active at a time', () {
      final registry = SerialSessionRegistry();
      final first = _session(registry, port: 'COM3');
      final second = _session(registry, port: 'COM5');

      registry.adopt(first);
      registry.adopt(second);
      registry.setActive(first.id);

      expect(registry.sessions.where((s) => s.isActive), hasLength(1));
      expect(registry.activeSession?.portPath, 'COM3');
    });

    test('closing an inactive session leaves the active one alone', () async {
      final registry = SerialSessionRegistry();
      final first = _session(registry, port: 'COM3');
      final second = _session(registry, port: 'COM5');
      registry.adopt(first);
      registry.adopt(second);

      await registry.close(first.id);

      expect(registry.sessions, hasLength(1));
      expect(registry.activeSession?.portPath, 'COM5');
    });

    test(
      'closing the active session promotes the oldest remaining one',
      () async {
        final registry = SerialSessionRegistry();
        final first = _session(registry, port: 'COM3');
        final second = _session(registry, port: 'COM5');
        registry.adopt(first);
        registry.adopt(second);

        await registry.close(second.id);

        expect(registry.activeSession?.portPath, 'COM3');
      },
    );

    test('closing the last session leaves no active device', () async {
      final registry = SerialSessionRegistry();
      final only = _session(registry, port: 'COM3');
      registry.adopt(only);

      await registry.close(only.id);

      expect(registry.sessions, isEmpty);
      expect(registry.activeSession, isNull);
    });

    test('closing a session disposes its handle', () async {
      final registry = SerialSessionRegistry();
      final handle = _FakeSerial('COM3');
      final session = _session(registry, port: 'COM3', serial: handle);
      registry.adopt(session);

      await registry.close(session.id);

      expect(handle.closed, isTrue);
      expect(handle.disposed, isTrue);
    });

    test('closeAll disposes every handle', () async {
      final registry = SerialSessionRegistry();
      final a = _FakeSerial('COM3');
      final b = _FakeSerial('COM5');
      registry.adopt(_session(registry, port: 'COM3', serial: a));
      registry.adopt(_session(registry, port: 'COM5', serial: b));

      await registry.closeAll();

      expect(registry.sessions, isEmpty);
      expect(a.disposed, isTrue);
      expect(b.disposed, isTrue);
    });

    test('activating an unknown session reports failure', () {
      final registry = SerialSessionRegistry();

      expect(registry.setActive('nope'), isFalse);
      expect(registry.setActive(null), isTrue);
    });

    test('sessionForPort finds the open session for a path', () {
      final registry = SerialSessionRegistry();
      final session = _session(registry, port: 'COM7');
      registry.adopt(session);

      expect(registry.sessionForPort('COM7')?.id, session.id);
      expect(registry.sessionForPort('COM9'), isNull);
    });

    test('notifies listeners when the active session changes', () {
      final registry = SerialSessionRegistry();
      var notifications = 0;
      registry.addListener(() => notifications++);

      final a = _session(registry, port: 'COM3');
      final b = _session(registry, port: 'COM5');
      registry.adopt(a);
      registry.adopt(b);
      registry.setActive(a.id);

      expect(notifications, greaterThanOrEqualTo(3));
    });

    test('each session reports its own port and baud rate', () {
      final registry = SerialSessionRegistry();
      final session = registry.create(
        portPath: 'COM11',
        serial: _FakeSerial('COM11'),
        events: const Stream<SerialEvent>.empty().listen((_) {}),
        baudRate: 921600,
      );

      expect(session.portPath, 'COM11');
      expect(session.baudRate, 921600);
      expect(session.id, isNot(session.portPath));
    });

    test(
      'replacing a transport keeps the session and drops the old handle',
      () async {
        final registry = SerialSessionRegistry();
        final oldHandle = _FakeSerial('COM3');
        final session = _session(registry, port: 'COM3', serial: oldHandle);
        registry.adopt(session);
        final replacement = _FakeSerial('COM3');

        final replaced = await registry.replaceTransport(
          session.id,
          () async => SerialTransport(
            serial: replacement,
            events: const Stream<SerialEvent>.empty().listen((_) {}),
          ),
        );

        expect(replaced, isTrue);
        expect(registry.sessions, hasLength(1));
        expect(registry.activeSession?.id, session.id);
        expect(session.serial, same(replacement));
        expect(oldHandle.closed, isTrue);
        expect(oldHandle.disposed, isTrue);
      },
    );

    test('a failed transport replacement removes only that session', () async {
      final registry = SerialSessionRegistry();
      final firstHandle = _FakeSerial('COM3');
      final secondHandle = _FakeSerial('COM5');
      final first = _session(registry, port: 'COM3', serial: firstHandle);
      final second = _session(registry, port: 'COM5', serial: secondHandle);
      registry.adopt(first);
      registry.adopt(second);

      final replaced = await registry.replaceTransport(second.id, () async {
        return null;
      });

      expect(replaced, isFalse);
      expect(registry.sessions, hasLength(1));
      expect(registry.activeSession?.id, first.id);
      expect(firstHandle.disposed, isFalse);
      expect(secondHandle.disposed, isTrue);
    });

    test('replacing an unknown session reports failure', () async {
      final registry = SerialSessionRegistry();

      expect(
        await registry.replaceTransport('nope', () async => null),
        isFalse,
      );
    });
  });
}
