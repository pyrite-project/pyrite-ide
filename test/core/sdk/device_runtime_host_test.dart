import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/models/board_manager.dart';
import 'package:pyrite_ide/core/sdk/device_runtime_backend.dart';
import 'package:pyrite_ide/core/sdk/device_runtime_host.dart';
import 'package:pyrite_ide/core/sdk/plugin_event_bus.dart';
import 'package:pyrite_ide/core/sdk/plugin_event_bus_provider.dart';
import 'package:pyrite_ide/core/sdk/runtime_inspection.dart';
import 'package:pyrite_ide/core/services/serial/serial_provider.dart';
import 'package:pyrite_ide/core/services/status_bar/running_operation_provider.dart';

/// A [SerialNotifier] that never touches the serial port, so the host can be
/// driven from synthetic [SerialProviderState] transitions.
class _FakeSerialNotifier extends SerialNotifier {
  _FakeSerialNotifier(super.ref);

  @override
  Future<void> performUpdate() async {}
}

void main() {
  late ProviderContainer container;
  late DeviceRuntimeHost host;
  late List<String> delivered;

  setUp(() {
    delivered = [];
    final bus = PluginEventBus(
      deliver: (pluginId, sessionId, generation, event) {
        delivered.add(event.topic);
      },
    );
    container = ProviderContainer(
      overrides: [
        pluginEventBusProvider.overrideWithValue(bus),
        serialProvider.overrideWith(_FakeSerialNotifier.new),
      ],
    );
    host = container.read(deviceRuntimeHostProvider);
  });

  tearDown(() => container.dispose());

  RuntimeSession? liveSession() => host.service.session('device');

  void setConnected(bool connected) {
    container.read(serialProvider.notifier).state = SerialProviderState(
      isConnected: connected,
      selectedPortName: connected ? 'COM3' : null,
    );
  }

  void startOp(String id) {
    container
        .read(runningOperationsProvider.notifier)
        .start(RunningOperation(id: id, label: 'op', icon: Icons.play_arrow));
  }

  void stopOp(String id) {
    container.read(runningOperationsProvider.notifier).stop(id);
  }

  void subscribe(String topic) {
    final bus = container.read(pluginEventBusProvider);
    final result = bus.subscribe(
      subscriptionId: 'test-sub',
      pluginId: 'test',
      sessionId: 'device',
      generation: 1,
      topicName: topic,
      pluginPermissions: {
        'runtime': ['inspect'],
      },
    );
    expect(result.isOk, isTrue, reason: 'failed to subscribe $topic');
  }

  test('connecting a port creates an available runtime session', () {
    expect(liveSession(), isNull);
    setConnected(true);
    expect(liveSession(), isNotNull);
    expect(liveSession()!.capability, RuntimeCapability.available);
    expect(liveSession()!.generation, 1);
  });

  test('running inspection reports the real backend', () {
    setConnected(true);
    expect(host.backend, isA<DeviceRuntimeBackend>());
    expect(host.backend, isNot(isNull));
  });

  test(
    'a code-exec transaction drives programState to running then finished',
    () {
      setConnected(true);
      expect(liveSession()!.programState, RuntimeProgramState.idle);

      startOp('code-exec');
      expect(liveSession()!.programState, RuntimeProgramState.running);

      stopOp('code-exec');
      expect(liveSession()!.programState, RuntimeProgramState.finished);
    },
  );

  test('an inspection transaction does not flag the program as running', () {
    setConnected(true);
    startOp(runtimeInspectionOperationId);
    expect(liveSession()!.programState, isNot(RuntimeProgramState.running));
  });

  test('reconnecting a different port restarts the backend generation', () {
    setConnected(true);
    expect(liveSession()!.generation, 1);

    container.read(serialProvider.notifier).state = const SerialProviderState(
      isConnected: true,
      selectedPortName: 'COM5',
    );
    expect(liveSession()!.generation, 2);
  });

  test('disconnecting ends the session so sessions reports empty', () {
    setConnected(true);
    expect(liveSession()!.generation, 1);
    setConnected(false);
    expect(liveSession(), isNull);
    expect(host.service.sessions, isEmpty);
  });

  test('reconnecting after a disconnect starts a fresh session', () {
    setConnected(true);
    expect(liveSession()!.generation, 1);
    setConnected(false);
    expect(liveSession(), isNull);
    setConnected(true);
    expect(liveSession()!.generation, 1);
  });

  test('code-exec completion announces runtime.variables.changed', () {
    setConnected(true);
    subscribe(RuntimeTopics.variablesChanged);
    delivered.clear();
    startOp('code-exec');
    stopOp('code-exec');
    expect(delivered, contains(RuntimeTopics.variablesChanged));
  });

  test('an inspection transaction does not announce variables.changed', () {
    setConnected(true);
    subscribe(RuntimeTopics.variablesChanged);
    delivered.clear();
    startOp(runtimeInspectionOperationId);
    stopOp(runtimeInspectionOperationId);
    expect(delivered, isNot(contains(RuntimeTopics.variablesChanged)));
  });

  test('disconnecting announces runtime.session.ended', () {
    setConnected(true);
    subscribe(RuntimeTopics.sessionEnded);
    delivered.clear();
    setConnected(false);
    expect(delivered, contains(RuntimeTopics.sessionEnded));
  });
}
