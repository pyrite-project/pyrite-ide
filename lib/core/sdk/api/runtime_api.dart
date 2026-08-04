import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/sdk/device_runtime_host.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/sdk/runtime_inspection.dart';

abstract class SdkRuntimeCommands {
  static const String sessions = 'sdk.runtime.sessions';
  static const String state = 'sdk.runtime.state';
  static const String scopes = 'sdk.runtime.scopes';
  static const String variables = 'sdk.runtime.variables';
  static const String children = 'sdk.runtime.children';
  static const String objectInfo = 'sdk.runtime.object_info';
}

/// A page of runtime data: scopes, variables, or children.
class RuntimePage {
  const RuntimePage({required this.items, this.total, this.start = 0});
  final List<Map<String, dynamic>> items;
  final int? total;
  final int start;

  Map<String, dynamic> toJson() => {
    'items': items,
    'total': ?total,
    'start': start,
  };
}

/// Reads runtime state from the real device backend.
///
/// Every method returns null when inspection is not possible (no session, or
/// the backend reports capability unavailable) so the API reports a distinct
/// `unavailable` error instead of interrupting a running program.
abstract class RuntimeBackend {
  /// Scopes (e.g. globals/locals) for a session, or null when unavailable.
  Future<RuntimePage?> scopes(String sessionId);

  /// Variables in a scope, paged.
  Future<RuntimePage?> variables(
    String sessionId,
    String scopeId, {
    int start,
    int count,
  });

  /// Children of a referenced object, paged.
  Future<RuntimePage?> children(String reference, {int start, int count});

  /// Detailed info for a referenced object.
  Future<Map<String, dynamic>?> objectInfo(String reference);
}

/// Host access for the runtime API: the inspection service (session/reference
/// bookkeeping) plus the device backend that serves the actual data.
abstract class RuntimeHost {
  RuntimeInspectionService get service;
  RuntimeBackend get backend;
}

/// Exposes runtime inspection to a plugin. All commands require
/// `runtime:inspect`. Inspection never sends CTRL-C; when the backend can't
/// serve a query it returns `unavailable`.
class SdkRuntime {
  SdkRuntime(this.ref);

  final Ref ref;

  RuntimeHost get _host => ref.read(runtimeHostProvider);

  void bind(PluginRunManager manager) {
    for (final command in const [
      SdkRuntimeCommands.sessions,
      SdkRuntimeCommands.state,
      SdkRuntimeCommands.scopes,
      SdkRuntimeCommands.variables,
      SdkRuntimeCommands.children,
      SdkRuntimeCommands.objectInfo,
    ]) {
      manager.registerHandler(
        command,
        (envelope, respond) => _dispatch(command, envelope, respond),
        requiredPermission: 'runtime:inspect',
      );
    }
  }

  Future<void> _dispatch(
    String command,
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    switch (command) {
      case SdkRuntimeCommands.sessions:
        _handleSessions(envelope, respond);
      case SdkRuntimeCommands.state:
        _handleState(envelope, respond);
      case SdkRuntimeCommands.scopes:
        await _handleScopes(envelope, respond);
      case SdkRuntimeCommands.variables:
        await _handleVariables(envelope, respond);
      case SdkRuntimeCommands.children:
        await _handleChildren(envelope, respond);
      case SdkRuntimeCommands.objectInfo:
        await _handleObjectInfo(envelope, respond);
    }
  }

  void _handleSessions(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    _ok(envelope, respond, {
      'sessions': [
        for (final session in _host.service.sessions) session.toJson(),
      ],
    });
  }

  void _handleState(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final sessionId = _sessionId(envelope);
    final session = sessionId == null
        ? _host.service.sessions.firstOrNull
        : _host.service.session(sessionId);
    if (session == null) {
      _error(envelope, respond, 'no_session', 'No runtime session');
      return;
    }
    _ok(envelope, respond, session.toJson());
  }

  Future<void> _handleScopes(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final sessionId = _sessionId(envelope);
    if (sessionId == null) {
      _error(envelope, respond, 'invalid_request', 'Missing sessionId');
      return;
    }
    final session = _host.service.session(sessionId);
    if (session == null) {
      _error(envelope, respond, 'no_session', 'No such runtime session');
      return;
    }
    if (session.capability == RuntimeCapability.unavailable) {
      _unavailable(envelope, respond);
      return;
    }
    final page = await _host.backend.scopes(sessionId);
    if (page == null) {
      _unavailable(envelope, respond);
      return;
    }
    _ok(envelope, respond, page.toJson());
  }

  Future<void> _handleVariables(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final sessionId = payload['sessionId']?.toString();
    final scopeId = payload['scopeId']?.toString();
    if (sessionId == null || scopeId == null) {
      _error(envelope, respond, 'invalid_request', 'Missing sessionId/scopeId');
      return;
    }
    final session = _host.service.session(sessionId);
    if (session == null) {
      _error(envelope, respond, 'no_session', 'No such runtime session');
      return;
    }
    if (session.capability == RuntimeCapability.unavailable) {
      _unavailable(envelope, respond);
      return;
    }
    final page = await _host.backend.variables(
      sessionId,
      scopeId,
      start: _start(payload),
      count: _count(payload),
    );
    if (page == null) {
      _unavailable(envelope, respond);
      return;
    }
    _ok(envelope, respond, page.toJson());
  }

  Future<void> _handleChildren(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final reference = payload['reference']?.toString();
    if (reference == null || reference.isEmpty) {
      _error(envelope, respond, 'invalid_request', 'Missing reference');
      return;
    }
    if (!_checkReference(envelope, respond, reference)) return;
    final page = await _host.backend.children(
      reference,
      start: _start(payload),
      count: _count(payload),
    );
    if (page == null) {
      _unavailable(envelope, respond);
      return;
    }
    _ok(envelope, respond, page.toJson());
  }

  Future<void> _handleObjectInfo(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final reference = payload['reference']?.toString();
    if (reference == null || reference.isEmpty) {
      _error(envelope, respond, 'invalid_request', 'Missing reference');
      return;
    }
    if (!_checkReference(envelope, respond, reference)) return;
    final info = await _host.backend.objectInfo(reference);
    if (info == null) {
      _unavailable(envelope, respond);
      return;
    }
    _ok(envelope, respond, info);
  }

  /// Validates a reference token, responding with a stale error when it belongs
  /// to a previous generation. Returns false when a response was already sent.
  bool _checkReference(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
    String reference,
  ) {
    switch (_host.service.validate(reference)) {
      case ReferenceStatus.valid:
        return true;
      case ReferenceStatus.stale:
        _error(
          envelope,
          respond,
          'stale_reference',
          'Reference belongs to a previous runtime generation',
        );
        return false;
      case ReferenceStatus.malformed:
        _error(envelope, respond, 'invalid_request', 'Malformed reference');
        return false;
    }
  }

  String? _sessionId(Map<String, dynamic> envelope) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final id = payload['sessionId']?.toString();
    return (id == null || id.isEmpty) ? null : id;
  }

  int _start(Map<String, dynamic> payload) {
    final start = payload['start'];
    return start is int && start >= 0 ? start : 0;
  }

  int _count(Map<String, dynamic> payload) {
    final count = payload['count'];
    return count is int ? count : 0;
  }

  void _unavailable(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    _error(
      envelope,
      respond,
      'unavailable',
      'Runtime inspection is unavailable for this backend',
    );
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
    String message,
  ) {
    respond(
      makeEnvelope(
        type: SdkCommands.responseError,
        payload: {'code': code, 'message': message, 'details': null},
        replyTo: (envelope['requestId'] ?? envelope['id']).toString(),
      ),
    );
  }
}

final Provider<SdkRuntime> sdkRuntimeProvider = Provider(SdkRuntime.new);

/// Resolves runtime state against the real device by default; tests override
/// this to inject a fake backend.
final Provider<RuntimeHost> runtimeHostProvider = Provider<RuntimeHost>(
  (ref) => ref.read(deviceRuntimeHostProvider),
);
