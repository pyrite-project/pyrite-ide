import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/sdk/component_method_registry.dart';
import 'package:pyrite_ide/core/sdk/plugin_perf_budget.dart';
import 'package:pyrite_ide/core/sdk/view_model_store.dart';
import 'package:pyrite_ide/core/sdk/view_model_store_provider.dart';
import 'package:pyrite_ide/core/sdk/view_route_stack.dart';

/// Wires the native view snapshot/patch protocol to a plugin session.
///
/// The plugin sends `sdk.view.open/snapshot/patch/close`; the IDE applies each
/// against the shared [ViewModelStore] and replies with `ide.view.ack` on
/// success or `ide.view.nack` + `ide.view.resync` when a patch can't apply
/// (revision gap, missing snapshot, or a rolled-back invalid operation).
class SdkView {
  SdkView(this.ref);

  final Ref ref;

  ViewModelStore get _store => ref.read(viewModelStoreProvider);

  ViewRouteStacks get _routes => ref.read(viewRouteStacksProvider);

  void bind(PluginRunManager manager) {
    manager.registerHandler(
      SdkCommands.viewOpen,
      (envelope, respond) => _handleOpen(manager, envelope, respond),
    );
    manager.registerHandler(
      SdkCommands.viewSnapshot,
      (envelope, respond) => _handleSnapshot(manager, envelope, respond),
    );
    manager.registerHandler(
      SdkCommands.viewPatch,
      (envelope, respond) => _handlePatch(manager, envelope, respond),
    );
    manager.registerHandler(
      SdkCommands.viewClose,
      (envelope, respond) => _handleClose(manager, envelope, respond),
    );
    manager.registerHandler(
      SdkCommands.viewRoutePush,
      (envelope, respond) => _handleRoute(manager, envelope, respond, _push),
    );
    manager.registerHandler(
      SdkCommands.viewRoutePop,
      (envelope, respond) => _handleRoutePop(manager, envelope, respond),
    );
    manager.registerHandler(
      SdkCommands.viewRouteReplace,
      (envelope, respond) => _handleRoute(manager, envelope, respond, _replace),
    );
    manager.registerHandler(
      SdkCommands.viewRouteGoto,
      (envelope, respond) => _handleRoute(manager, envelope, respond, _goto),
    );
    manager.registerHandler(
      SdkCommands.viewComponentInvoke,
      (envelope, respond) => _handleComponentInvoke(manager, envelope, respond),
    );
  }

  Future<void> _handleComponentInvoke(
    PluginRunManager manager,
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final instance = _instanceId(manager, payload);
    final componentId = payload['componentId']?.toString();
    final method = payload['method']?.toString();
    if (instance == null ||
        componentId == null ||
        componentId.isEmpty ||
        method == null ||
        method.isEmpty) {
      _error(
        envelope,
        respond,
        'invalid_request',
        'Missing viewId/instanceId/componentId/method',
      );
      return;
    }
    final rawArguments = payload['arguments'];
    if (rawArguments != null && rawArguments is! Map) {
      _error(
        envelope,
        respond,
        'invalid_arguments',
        'Component arguments must be an object',
      );
      return;
    }
    final arguments = rawArguments is Map
        ? rawArguments.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};
    try {
      final result = await ref
          .read(componentMethodRegistryProvider)
          .invoke(instance, componentId, method, arguments);
      _ok(envelope, respond, result);
    } on ComponentMethodException catch (error) {
      _error(
        envelope,
        respond,
        error.code,
        error.message,
        details: error.details,
      );
    } catch (error) {
      _error(
        envelope,
        respond,
        'operation_failed',
        'Component operation failed: $error',
      );
    }
  }

  ViewInstanceId? _instanceId(
    PluginRunManager manager,
    Map<String, dynamic> payload,
  ) {
    final viewId = payload['viewId']?.toString();
    final instanceId = payload['instanceId']?.toString();
    if (viewId == null || viewId.isEmpty) return null;
    if (instanceId == null || instanceId.isEmpty) return null;
    return ViewInstanceId(
      pluginId: manager.pluginId,
      sessionId: manager.sessionId,
      viewId: viewId,
      instanceId: instanceId,
    );
  }

  void _handleOpen(
    PluginRunManager manager,
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final instance = _instanceId(manager, payload);
    if (instance == null) {
      _error(envelope, respond, 'invalid_request', 'Missing viewId/instanceId');
      return;
    }
    // Open registers an empty, loading instance until the first snapshot.
    _store.installSnapshot(instance: instance, revision: 0, nodes: const []);
    _store.setState(instance, ViewState.loading);
    _ok(envelope, respond, {'instance': instance.toJson()});
  }

  void _handleSnapshot(
    PluginRunManager manager,
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final instance = _instanceId(manager, payload);
    if (instance == null) {
      _error(envelope, respond, 'invalid_request', 'Missing viewId/instanceId');
      return;
    }
    final revision = payload['revision'];
    if (revision is! int) {
      _error(envelope, respond, 'invalid_request', 'Missing revision');
      return;
    }
    final rawNodes = payload['nodes'];
    if (rawNodes is List &&
        rawNodes.length > PluginPerfBudget.maxSnapshotNodes) {
      manager.metrics?.recordDrop();
      _error(
        envelope,
        respond,
        'payload_too_large',
        'A view snapshot may contain at most '
            '${PluginPerfBudget.maxSnapshotNodes} nodes',
      );
      return;
    }
    if (_payloadBytes(payload) > PluginPerfBudget.maxViewPayloadBytes) {
      manager.metrics?.recordDrop();
      _error(
        envelope,
        respond,
        'payload_too_large',
        'View snapshot exceeds ${PluginPerfBudget.maxViewPayloadBytes} bytes',
      );
      return;
    }
    final nodes = rawNodes is List
        ? [
            for (final n in rawNodes)
              if (n is Map) n.map((k, v) => MapEntry(k.toString(), v)),
          ]
        : <Map<String, dynamic>>[];
    _store.installSnapshot(
      instance: instance,
      revision: revision,
      nodes: nodes,
    );
    _ok(envelope, respond, {
      'instance': instance.toJson(),
      'revision': revision,
    });
  }

  void _handlePatch(
    PluginRunManager manager,
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final instance = _instanceId(manager, payload);
    if (instance == null) {
      _error(envelope, respond, 'invalid_request', 'Missing viewId/instanceId');
      return;
    }
    final baseRevision = payload['baseRevision'];
    final nextRevision = payload['revision'];
    if (baseRevision is! int || nextRevision is! int) {
      _error(envelope, respond, 'invalid_request', 'Missing revisions');
      return;
    }
    final List<PatchOp> ops;
    try {
      final rawOps = payload['ops'];
      if (rawOps is List && rawOps.length > PluginPerfBudget.maxPatchOps) {
        manager.metrics?.recordDrop();
        _error(
          envelope,
          respond,
          'payload_too_large',
          'A view patch may contain at most '
              '${PluginPerfBudget.maxPatchOps} operations',
        );
        return;
      }
      if (_payloadBytes(payload) > PluginPerfBudget.maxViewPayloadBytes) {
        manager.metrics?.recordDrop();
        _error(
          envelope,
          respond,
          'payload_too_large',
          'View patch exceeds ${PluginPerfBudget.maxViewPayloadBytes} bytes',
        );
        return;
      }
      ops = rawOps is List
          ? [
              for (final o in rawOps)
                if (o is Map)
                  PatchOp.fromJson(o.map((k, v) => MapEntry(k.toString(), v))),
            ]
          : const [];
    } on ViewProtocolException catch (e) {
      _error(envelope, respond, 'invalid_request', e.message);
      return;
    }

    final result = _store.applyPatch(
      instance: instance,
      baseRevision: baseRevision,
      nextRevision: nextRevision,
      ops: ops,
    );

    if (result.isOk) {
      manager.metrics?.recordViewPatch();
      // Acknowledge the applied revision so the plugin can release its
      // in-flight patch and flush any merged updates.
      manager.sendViewFrame(IdeCommands.viewAck, {
        'instance': instance.toJson(),
        'revision': result.revision,
      });
      _ok(envelope, respond, {'revision': result.revision});
      return;
    }

    // Nack tells the plugin the patch was dropped; for recoverable failures we
    // also ask for a fresh snapshot so the model can re-converge.
    manager.sendViewFrame(IdeCommands.viewNack, {
      'instance': instance.toJson(),
      'reason': result.rejection?.name,
      'message': result.message,
    });
    if (result.rejection == PatchRejection.revisionGap ||
        result.rejection == PatchRejection.noSnapshot) {
      final current = _store.model(instance)?.revision;
      manager.sendViewFrame(IdeCommands.viewResync, {
        'instance': instance.toJson(),
        'revision': current,
      });
      manager.metrics?.recordViewResync();
    }
    _error(
      envelope,
      respond,
      result.rejection?.name ?? 'patch_rejected',
      result.message ?? 'Patch rejected',
    );
  }

  int _payloadBytes(Map<String, dynamic> payload) =>
      utf8.encode(jsonEncode(payload)).length;

  /// Delivers a component event (button press, row select, debounced text
  /// change…) to the plugin that owns [instance].
  ///
  /// Fire-and-forget: the host has already updated its local input state, so a
  /// slow plugin can never stall the UI.
  void sendComponentEvent(
    PluginRunManager manager,
    ViewInstanceId instance,
    String componentId,
    String event,
    Map<String, dynamic> payload,
  ) {
    manager.sendViewFrame(IdeCommands.viewEvent, {
      'instance': instance.toJson(),
      'componentId': componentId,
      'event': event,
      'payload': payload,
    });
  }

  /// Requests a row-specific menu from the plugin. Unlike ordinary component
  /// events this is request/response because the menu provider may be dynamic.
  Future<Map<String, dynamic>?> requestContextMenu(
    PluginRunManager manager,
    ViewInstanceId instance,
    String componentId,
    String targetId,
    String targetType,
  ) async {
    try {
      final response = await manager.sendAndWaitReply(
        makeEnvelope(
          type: IdeCommands.viewContextMenuRequest,
          payload: {
            'instance': instance.toJson(),
            'componentId': componentId,
            'targetId': targetId,
            'targetType': targetType,
          },
        ),
        connectIfNeeded: false,
      );
      if (response['type']?.toString().endsWith('.error') == true) return null;
      final payload = response['payload'];
      final data = payload is Map ? payload['data'] : null;
      return data is Map
          ? data.map((key, value) => MapEntry(key.toString(), value))
          : null;
    } on Object {
      return null;
    }
  }

  /// Reports whether a concrete view instance is currently mounted.
  ///
  /// This is fire-and-forget like component events. Plugins use it to suspend
  /// debounced, non-critical refreshes while a sidebar or tab is hidden.
  void sendVisibilityChanged(
    PluginRunManager manager,
    ViewInstanceId instance,
    bool visible,
  ) {
    manager.sendViewFrame(IdeCommands.viewVisibilityChanged, {
      'instance': instance.toJson(),
      'visible': visible,
    });
  }

  // -- Per-instance routing --------------------------------------------------

  ViewRouteEntry _push(
    ViewInstanceId instance,
    String route,
    Map<String, dynamic> params,
  ) => _routes.push(instance, route, params);

  ViewRouteEntry _replace(
    ViewInstanceId instance,
    String route,
    Map<String, dynamic> params,
  ) => _routes.replace(instance, route, params);

  ViewRouteEntry _goto(
    ViewInstanceId instance,
    String route,
    Map<String, dynamic> params,
  ) => _routes.goto(instance, route, params);

  Map<String, dynamic>? _routeParams(Map<String, dynamic> payload) {
    final raw = payload['params'];
    return raw is Map ? raw.map((k, v) => MapEntry(k.toString(), v)) : null;
  }

  /// Handles push/replace/goto, which all take a target route and differ only
  /// in how they reshape the stack.
  void _handleRoute(
    PluginRunManager manager,
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
    ViewRouteEntry Function(ViewInstanceId, String, Map<String, dynamic>) apply,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final instance = _instanceId(manager, payload);
    if (instance == null) {
      _error(envelope, respond, 'invalid_request', 'Missing viewId/instanceId');
      return;
    }
    final route = payload['route']?.toString();
    if (route == null || route.isEmpty) {
      _error(envelope, respond, 'invalid_request', 'Missing route');
      return;
    }
    final entry = apply(instance, route, _routeParams(payload) ?? const {});
    _syncRoute(manager, instance, entry);
    _ok(envelope, respond, {
      'instance': instance.toJson(),
      'route': entry.route,
      'params': entry.params,
      'stack': _routes.routesOf(instance),
    });
  }

  void _handleRoutePop(
    PluginRunManager manager,
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final instance = _instanceId(manager, payload);
    if (instance == null) {
      _error(envelope, respond, 'invalid_request', 'Missing viewId/instanceId');
      return;
    }
    // Popping the root is normal plugin behaviour (a view with no history), so
    // it reports popped:false rather than failing the request.
    final popped = _routes.pop(instance);
    final entry = _routes.current(instance);
    if (popped) _syncRoute(manager, instance, entry);
    _ok(envelope, respond, {
      'instance': instance.toJson(),
      'popped': popped,
      'route': entry.route,
      'params': entry.params,
      'stack': _routes.routesOf(instance),
    });
  }

  void _syncRoute(
    PluginRunManager manager,
    ViewInstanceId instance,
    ViewRouteEntry entry,
  ) {
    manager.sendViewFrame(IdeCommands.viewRouteSync, {
      'instance': instance.toJson(),
      'route': entry.route,
      'params': entry.params,
      'stack': _routes.routesOf(instance),
    });
  }

  void _handleClose(
    PluginRunManager manager,
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final instance = _instanceId(manager, payload);
    if (instance == null) {
      _error(envelope, respond, 'invalid_request', 'Missing viewId/instanceId');
      return;
    }
    _store.close(instance);
    // History dies with the instance; a reopened view starts at its root rather
    // than resuming a flow the user can no longer see.
    _routes.clear(instance);
    _ok(envelope, respond, {'instance': instance.toJson()});
  }

  void _ok(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
    dynamic data,
  ) {
    respond(
      makeEnvelope(
        type: SdkCommands.responseOk,
        payload: {'data': data},
        replyTo: (envelope['requestId'] ?? envelope['id']).toString(),
      ),
    );
  }

  void _error(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
    String code,
    String message, {
    Map<String, dynamic>? details,
  }) {
    respond(
      makeEnvelope(
        type: SdkCommands.responseError,
        payload: {'code': code, 'message': message, 'details': details},
        replyTo: (envelope['requestId'] ?? envelope['id']).toString(),
      ),
    );
  }
}

final Provider<SdkView> sdkViewProvider = Provider(SdkView.new);
