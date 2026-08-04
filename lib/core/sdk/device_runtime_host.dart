import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/sdk/api/runtime_api.dart';
import 'package:pyrite_ide/core/sdk/device_runtime_backend.dart';
import 'package:pyrite_ide/core/sdk/plugin_event_bus_provider.dart';
import 'package:pyrite_ide/core/sdk/runtime_inspection.dart';
import 'package:pyrite_ide/core/models/board_manager.dart';
import 'package:pyrite_ide/core/services/serial/device_executor.dart';
import 'package:pyrite_ide/core/services/serial/serial_provider.dart';
import 'package:pyrite_ide/core/services/status_bar/running_operation_provider.dart';

/// Bridges the real serial connection to [RuntimeInspectionService], producing
/// runtime sessions and lifecycle events from connect/disconnect transitions.
///
/// A runtime session is keyed by the connected port; reconnecting the same port
/// bumps the session generation (invalidating prior object references), which
/// is the observable analogue of a hardware reset given the serial layer keeps
/// no generation of its own.
class DeviceRuntimeHost implements RuntimeHost {
  DeviceRuntimeHost(this._ref) {
    _service = RuntimeInspectionService(
      emit: (topic, payload) =>
          _ref.read(pluginEventBusProvider).emit(topic, payload),
    );
    _backend = DeviceRuntimeBackend(
      service: _service,
      runScript: _runScript,
      isBusy: _isBusy,
    );
    _subscription = _ref.listen<SerialProviderState>(
      serialProvider,
      (previous, next) => _onSerialChanged(previous, next),
      fireImmediately: true,
    );
    _runningSubscription = _ref.listen<List<RunningOperation>>(
      runningOperationsProvider,
      (previous, next) => _onRunningChanged(next),
      fireImmediately: true,
    );
  }

  final Ref _ref;
  late final RuntimeInspectionService _service;
  late final DeviceRuntimeBackend _backend;
  late final ProviderSubscription<SerialProviderState> _subscription;
  late final ProviderSubscription<List<RunningOperation>> _runningSubscription;

  static const String _sessionId = 'device';
  static const String _codeExecOperationId = 'code-exec';
  String? _connectedPort;
  bool _sessionCreated = false;
  bool _codeExecActive = false;

  @override
  RuntimeInspectionService get service => _service;

  @override
  RuntimeBackend get backend => _backend;

  /// Runs one inspection script through the shared REPL transaction machinery
  /// under its own running-operation id, so the busy gate never flags its own
  /// query as a device-busy state.
  Future<String> _runScript(String script) => runPythonOnDevice(
    _ref,
    script,
    timeout: const Duration(seconds: 15),
    runningOperationId: runtimeInspectionOperationId,
  );

  /// True while any serial transaction other than inspection is active. The
  /// gate is consulted before any byte reaches the port, so inspection never
  /// interrupts a running program or a file transfer.
  bool _isBusy() => _ref
      .read(runningOperationsProvider)
      .any((op) => op.id != runtimeInspectionOperationId);

  void _onRunningChanged(List<RunningOperation> ops) {
    if (!_sessionCreated) return;
    final busy = ops.any((op) => op.id != runtimeInspectionOperationId);
    _service.setProgramState(
      _sessionId,
      busy ? RuntimeProgramState.running : RuntimeProgramState.finished,
    );
    final codeExecActive = ops.any((op) => op.id == _codeExecOperationId);
    if (_codeExecActive && !codeExecActive) {
      // A code-exec just completed; the device's variables may have changed,
      // so prompt plugins to refresh without polling.
      _service.notifyVariablesChanged(_sessionId);
    }
    _codeExecActive = codeExecActive;
  }

  void _onSerialChanged(
    SerialProviderState? previous,
    SerialProviderState next,
  ) {
    if (next.isConnected) {
      final port = next.selectedPortName;
      if (!_sessionCreated) {
        _service.createSession(_sessionId);
        _sessionCreated = true;
        _connectedPort = port;
      } else if (_connectedPort != null && port != _connectedPort) {
        // A different port took over the session: treat as a backend restart.
        _service.restartBackend(_sessionId);
        _connectedPort = port;
      }
    } else if (_sessionCreated && (previous?.isConnected ?? false)) {
      // Disconnect ends the session entirely so `sdk.runtime.sessions` reports
      // empty and the plugin can show its disconnected placeholder. A later
      // reconnect starts a fresh session at a new generation.
      _service.endSession(_sessionId);
      _sessionCreated = false;
      _codeExecActive = false;
      _connectedPort = null;
    }
  }

  void dispose() {
    _subscription.close();
    _runningSubscription.close();
    _service.clear();
  }
}

final Provider<DeviceRuntimeHost> deviceRuntimeHostProvider = Provider((ref) {
  final host = DeviceRuntimeHost(ref);
  ref.onDispose(host.dispose);
  return host;
});
