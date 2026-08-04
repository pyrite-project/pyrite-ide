import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/models/board_manager.dart';
import 'package:pyrite_ide/core/sdk/api/document_api.dart';
import 'package:pyrite_ide/core/sdk/api/runtime_api.dart';
import 'package:pyrite_ide/core/sdk/context_key_service.dart';
import 'package:pyrite_ide/core/sdk/document_service.dart';
import 'package:pyrite_ide/core/sdk/plugin_event_bus_provider.dart';
import 'package:pyrite_ide/core/sdk/runtime_inspection.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/core/services/serial/serial_provider.dart';

/// Pushes live IDE state into [ContextKeyService] so Manifest `when` expressions
/// re-evaluate as the editor, runtime, device, workspace and focused view change.
class ContextKeyHost {
  ContextKeyHost(this._ref) {
    _keys = _ref.read(contextKeyServiceProvider);
    // Defer side effects: Riverpod forbids mutating other providers while this
    // provider is still initializing.
    scheduleMicrotask(_bootstrap);
  }

  final Ref _ref;
  late final ContextKeyService _keys;
  ProviderSubscription<SerialProviderState>? _serialSub;
  ProviderSubscription<dynamic>? _workspaceSub;
  void Function()? _removeBusListener;
  var _disposed = false;
  var _bootstrapped = false;

  void _bootstrap() {
    if (_disposed || _bootstrapped) return;
    _bootstrapped = true;
    _keys.setValues({
      'editor.hasDocument': false,
      'editor.language': '',
      'runtime.language': '',
      'runtime.state': RuntimeProgramState.idle.name,
      'device.connected': false,
      'workspace.opened': false,
      'plugin.enabled': true,
      'view.active': '',
    });

    _serialSub = _ref.listen<SerialProviderState>(
      serialProvider,
      (_, next) => _onSerial(next),
      fireImmediately: true,
    );
    _workspaceSub = _ref.listen(
      fileProvider,
      (_, next) => _keys.setValue('workspace.opened', next != null),
      fireImmediately: true,
    );
    // Ensure document and runtime hosts are alive before reading them.
    _ref.read(documentHostProvider);
    _ref.read(runtimeHostProvider);
    _removeBusListener = _ref
        .read(pluginEventBusProvider)
        .addEmitListener(_onBusEvent);
    _syncEditorFromRegistry();
    _syncRuntimeState();
  }

  /// Updates `view.active` when the focused plugin view changes.
  void setActiveView(String? viewId) {
    if (_disposed) return;
    _keys.setValue('view.active', viewId ?? '');
  }

  /// Updates `plugin.enabled` for expressions that gate on a global flag.
  ///
  /// Per-plugin enablement is still enforced by menu/command services against
  /// [PluginStatus]; this key only covers Manifest `when` clauses.
  void setPluginEnabled(bool enabled) {
    if (_disposed) return;
    _keys.setValue('plugin.enabled', enabled);
  }

  void _onSerial(SerialProviderState next) {
    _keys.setValues({
      'device.connected': next.isConnected,
      'runtime.language': next.isConnected ? 'python' : '',
    });
    _syncRuntimeState();
  }

  void _syncEditorFromRegistry() {
    if (_disposed) return;
    final active = _ref.read(documentHostProvider).registry.active;
    _keys.setValues({
      'editor.hasDocument': active != null,
      'editor.language': active?.languageId ?? '',
    });
  }

  void _syncRuntimeState() {
    if (_disposed) return;
    final sessions = _ref.read(runtimeHostProvider).service.sessions.toList();
    final state = sessions.isEmpty
        ? RuntimeProgramState.idle.name
        : sessions.first.programState.name;
    _keys.setValue('runtime.state', state);
  }

  void _onBusEvent(String topic, Map<String, dynamic> payload) {
    // Bus emit listeners run synchronously inside emit(), which callers fire
    // during widget build/dispose (e.g. PluginViewHost emits view.closed from
    // dispose/didUpdateWidget). Mutating context keys there would notify the
    // ChangeNotifierProvider mid-build and trip Riverpod's "modified a provider
    // while building" assertion, so defer the mirror to a microtask — the same
    // reason _bootstrap defers its initial writes.
    scheduleMicrotask(() => _dispatchBusEvent(topic, payload));
  }

  void _dispatchBusEvent(String topic, Map<String, dynamic> payload) {
    if (_disposed) return;
    switch (topic) {
      case DocumentTopics.activeChanged:
      case DocumentTopics.opened:
      case DocumentTopics.closed:
        _syncEditorFromRegistry();
      case RuntimeTopics.sessionCreated:
      case RuntimeTopics.sessionEnded:
      case RuntimeTopics.sessionStateChanged:
      case RuntimeTopics.programStarted:
      case RuntimeTopics.programPaused:
      case RuntimeTopics.programResumed:
      case RuntimeTopics.programFinished:
      case RuntimeTopics.backendRestarted:
        _syncRuntimeState();
      case 'view.focused':
        final viewId = payload['viewId']?.toString();
        if (viewId != null) setActiveView(viewId);
      case 'view.closed':
        final closed = payload['viewId']?.toString();
        if (closed != null && _keys.value('view.active') == closed) {
          setActiveView(null);
        }
    }
  }

  void dispose() {
    _disposed = true;
    _serialSub?.close();
    _workspaceSub?.close();
    _removeBusListener?.call();
  }
}

final Provider<ContextKeyHost> contextKeyHostProvider = Provider((ref) {
  final host = ContextKeyHost(ref);
  ref.onDispose(host.dispose);
  return host;
});
