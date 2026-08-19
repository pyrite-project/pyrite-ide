import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:pyrite_ide/core/sdk/permission_log.dart';
import 'package:pyrite_ide/core/sdk/permissions.dart';
import 'package:pyrite_ide/core/sdk/plugin_metrics.dart';
import 'package:pyrite_ide/core/sdk/plugin_perf_budget.dart';
import 'package:pyrite_ide/core/sdk/plugin_transport.dart';
import 'package:pyrite_ide/core/sdk/protocol.dart';
import 'package:pyrite_ide/core/sdk/types.dart';

// ---------------------------------------------------------------------------
// SDK message type constants (Python <-> Dart)
// ---------------------------------------------------------------------------

abstract class IdeCommands {
  static const String initialize = 'ide.initialize';
  static const String initialized = 'ide.initialized';
  static const String eventEmit = 'ide.event.emit';
  static const String lifecycleHook = 'ide.lifecycle.hook';
  static const String viewAck = 'ide.view.ack';
  static const String viewNack = 'ide.view.nack';
  static const String viewResync = 'ide.view.resync';
  static const String viewEvent = 'ide.view.event';
  static const String viewContextMenuRequest = 'ide.view.contextMenu.request';
  static const String viewVisibilityChanged = 'ide.view.visibility.changed';
  static const String viewRouteSync = 'ide.view.route.sync';
  static const String envChanged = 'ide.env.changed';
  static const String commandExecute = 'ide.command.execute';
  static const String requestCancel = 'ide.request.cancel';
  static const String healthPing = 'ide.health.ping';
  static const String responsePath = 'ide.response.path';
  static const String responseOk = 'ide.response.ok';
  static const String responseError = 'ide.response.error';
}

abstract class SdkCommands {
  static const String initialize = 'sdk.initialize';
  static const String ready = 'sdk.ready';
  static const String outputAppend = 'sdk.output.append';
  static const String pathRequest = 'sdk.path.request';
  static const String eventsSubscribe = 'sdk.events.subscribe';
  static const String eventsUnsubscribe = 'sdk.events.unsubscribe';
  static const String viewOpen = 'sdk.view.open';
  static const String viewSnapshot = 'sdk.view.snapshot';
  static const String viewPatch = 'sdk.view.patch';
  static const String viewClose = 'sdk.view.close';
  static const String viewFocus = 'sdk.view.focus';
  static const String viewRoutePush = 'sdk.view.route.push';
  static const String viewRoutePop = 'sdk.view.route.pop';
  static const String viewRouteReplace = 'sdk.view.route.replace';
  static const String viewRouteGoto = 'sdk.view.route.goto';
  static const String viewComponentInvoke = 'sdk.view.component.invoke';
  static const String envGet = 'sdk.env.get';
  static const String configurationGet = 'sdk.configuration.get';
  static const String configurationSet = 'sdk.configuration.set';
  static const String configurationList = 'sdk.configuration.list';
  static const String healthPong = 'sdk.health.pong';
  static const String runtimeReportError = 'sdk.runtime.report_error';
  static const String responseOk = 'sdk.response.ok';
  static const String responseError = 'sdk.response.error';
}

// ---------------------------------------------------------------------------
// Envelope helpers
// ---------------------------------------------------------------------------

String _newId() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

Map<String, dynamic> _decodePluginEnvelope(Uint8List bytes) {
  final decoded = jsonDecode(utf8.decode(bytes));
  if (decoded is! Map) {
    throw const FormatException('Plugin envelope must be a JSON object');
  }
  return decoded.map((key, value) => MapEntry(key.toString(), value));
}

class _InboundPluginMessage {
  const _InboundPluginMessage({
    required this.envelope,
    required this.encodedBytes,
  });

  final Map<String, dynamic> envelope;
  final int encodedBytes;

  String get type => envelope['type']?.toString() ?? '';
  String? get requestId => envelope['requestId']?.toString();
}

Map<String, dynamic> makeEnvelope({
  required String type,
  Map<String, dynamic>? payload,
  dynamic data,
  String? replyTo,
  String? requestId,
  String pluginId = 'standalone',
  String sessionId = 'standalone',
  int generation = 1,
  int sequence = 1,
  int? deadline,
}) {
  return {
    'protocolVersion': PluginProtocol.version,
    'pluginId': pluginId,
    'sessionId': sessionId,
    'generation': generation,
    'requestId': requestId == null || requestId.isEmpty ? _newId() : requestId,
    'replyTo': replyTo,
    'sequence': sequence,
    'type': type,
    'payload': payload ?? {},
    'data': data,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
    'deadline': ?deadline,
  };
}

// ---------------------------------------------------------------------------
// Command handler type
// ---------------------------------------------------------------------------

typedef CommandHandler =
    void Function(
      Map<String, dynamic> envelope,
      void Function(Map<String, dynamic>) respond,
    );

// ---------------------------------------------------------------------------
// PluginRunManager
// ---------------------------------------------------------------------------

class PluginRunManager {
  PluginRunManager({
    required this.transport,
    required this.assetsPath,
    String? dataPath,
    String? cachePath,
    String? tempPath,
    this.pluginId = '',
    this.pluginType = 'ui',
    this.pluginPermissions = const {},
    this.permissionLog,
    this.onOutput,
    this.metrics,
    String? sessionId,
    this.generation = 1,
  }) : dataPath = dataPath ?? '$assetsPath/data',
       cachePath = cachePath ?? '$assetsPath/cache',
       tempPath = tempPath ?? Directory.systemTemp.path,
       sessionId = sessionId ?? _newId() {
    _messageSubscription = transport.messages.listen(
      _handleTransportMessage,
      onError: _handleTransportError,
    );
    _stateSubscription = transport.states.listen(
      _handleTransportState,
      onError: _handleTransportError,
    );
  }

  final PluginTransport transport;
  final String assetsPath;
  final String dataPath;
  final String cachePath;
  final String tempPath;
  final String pluginId;
  final String pluginType;
  final Map<String, List<String>> pluginPermissions;
  final PermissionLogService? permissionLog;
  final void Function(String message)? onOutput;
  PluginSessionMetrics? metrics;
  String get transportType => transport.type;
  late final StreamSubscription<Uint8List> _messageSubscription;
  late final StreamSubscription<PluginTransportState> _stateSubscription;
  PluginTransportState _transportState = PluginTransportState.closed;
  bool _connecting = false;
  final Map<String, dynamic> runtimeData = {};
  void Function()? onDataChanged;
  void Function(String scope, String path)? onPathRequest;

  final Map<String, CommandHandler> _handlers = {};
  final Map<String, Completer<Map<String, dynamic>>> _pendingReplies = {};
  final Map<String, DateTime> _pendingStartedAt = {};
  final LinkedHashSet<String> _cancelledRequests = LinkedHashSet();
  final ListQueue<_InboundPluginMessage> _controlQueue = ListQueue();
  final ListQueue<_InboundPluginMessage> _viewPatchQueue = ListQueue();
  Future<void> _decodeTail = Future<void>.value();
  bool _drainingInbound = false;
  final String sessionId;
  final int generation;
  int _outgoingSequence = 0;
  int _incomingSequence = 0;
  Completer<void>? _handshake;
  bool _protocolReady = false;
  final Set<String> negotiatedCapabilities = {};
  String? sdkVersion;

  int get controlQueueDepth => _controlQueue.length;
  int get viewPatchQueueDepth => _viewPatchQueue.length;

  String _requestId(Map<String, dynamic> envelope) =>
      (envelope['requestId'] ?? envelope['id']).toString();

  String? _replyTo(Map<String, dynamic> envelope) =>
      (envelope['replyTo'] ?? envelope['reply_to'])?.toString();

  void registerHandler(
    String type,
    CommandHandler handler, {
    String? requiredPermission,
    bool publiclyAccessible = false,
  }) {
    final required = requiredPermission ?? Permissions.getRequirement(type);
    final isPublic = publiclyAccessible || Permissions.isPublic(type);
    _handlers[type] = (envelope, respond) {
      if (!_matchesContext(envelope)) {
        _respondAccessError(
          envelope,
          respond,
          code: 'invalid_context',
          message: 'Envelope does not belong to this plugin session',
        );
        return;
      }

      final decision = !isPublic && required == null
          ? PermissionDecision.unknown
          : (isPublic || Permissions.check(pluginPermissions, required!))
          ? PermissionDecision.allowed
          : PermissionDecision.denied;
      if (type != SdkCommands.outputAppend) {
        permissionLog?.add(
          PermissionLogEntry(
            pluginId: pluginId,
            command: type,
            required: required ?? (isPublic ? 'public' : 'unknown'),
            decision: decision,
          ),
        );
      }
      if (decision != PermissionDecision.allowed) {
        final unknown = decision == PermissionDecision.unknown;
        _respondAccessError(
          envelope,
          respond,
          code: unknown ? 'unknown_command' : 'permission_denied',
          message: unknown
              ? 'Unknown SDK command: $type'
              : 'Permission denied: $required',
          required: required,
        );
        return;
      }
      handler(envelope, respond);
    };
  }

  bool _matchesContext(Map<String, dynamic> envelope) {
    final expectedPluginId = pluginId.isEmpty ? 'standalone' : pluginId;
    return envelope['pluginId'] == expectedPluginId &&
        envelope['sessionId'] == sessionId &&
        envelope['generation'] == generation;
  }

  void _respondAccessError(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond, {
    required String code,
    required String message,
    String? required,
  }) {
    respond(
      makeEnvelope(
        type: SdkCommands.responseError,
        payload: {
          'code': code,
          'message': message,
          'details': required == null ? null : {'required': required},
        },
        replyTo: _requestId(envelope),
      ),
    );
  }

  void unregisterHandler(String type) {
    _handlers.remove(type);
  }

  // -- Built-in handlers ----------------------------------------------------

  void _initBuiltinHandlers() {
    registerHandler(SdkCommands.outputAppend, _handleOutputAppend);
    registerHandler(SdkCommands.pathRequest, _handlePathRequest);
  }

  void _handlePathRequest(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final scope = payload['scope']?.toString() ?? 'assets';

    String resolvedPath;
    switch (scope) {
      case 'plugin':
      case 'assets':
        resolvedPath = assetsPath;
      case 'data':
        resolvedPath = dataPath;
      case 'cache':
        resolvedPath = cachePath;
      case 'temp':
        resolvedPath = tempPath;
      default:
        resolvedPath = assetsPath;
    }

    onOutput?.call(
      '[$pluginId] path request scope=$scope resolved=$resolvedPath',
    );

    respond(
      makeEnvelope(
        type: IdeCommands.responsePath,
        payload: {'scope': scope, 'path': resolvedPath, 'plugin_id': pluginId},
        replyTo: _requestId(envelope),
      ),
    );
  }

  // -- Connection ------------------------------------------------------------

  Future<void> connect({bool transportAlreadyStarted = false}) async {
    if (_stopped) return;
    if (_transportState == PluginTransportState.ready && _protocolReady) return;
    if (_connecting) {
      await Future.doWhile(() async {
        await Future.delayed(const Duration(milliseconds: 50));
        return _connecting;
      });
      if (_transportState == PluginTransportState.ready) return;
    }

    _connecting = true;
    try {
      _incomingSequence = 0;
      _outgoingSequence = 0;
      _initBuiltinHandlers();
      _handshake = null;
      _protocolReady = false;
      negotiatedCapabilities.clear();
      sdkVersion = null;
      if (!transportAlreadyStarted) await transport.start();
      _transportState = PluginTransportState.ready;
      _handshake = Completer<void>();
      onOutput?.call('[$pluginId] transport ready');
      sendJson(
        makeEnvelope(
          type: IdeCommands.initialize,
          pluginId: pluginId.isEmpty ? 'standalone' : pluginId,
          sessionId: sessionId,
          generation: generation,
          payload: {
            'protocolVersion': PluginProtocol.version,
            'pluginId': pluginId,
            'capabilities': ['sdk.v1'],
            'pluginContext': {
              'id': pluginId.isEmpty ? 'standalone' : pluginId,
              'session': sessionId,
              'generation': generation,
              'pluginDir': assetsPath,
              'dataDir': dataPath,
              'cacheDir': cachePath,
              'tempDir': tempPath,
              'capabilities': ['sdk.v1'],
            },
          },
        ),
      );
      await _handshake!.future.timeout(const Duration(seconds: 5));
    } on PluginProtocolException {
      await transport.close();
      rethrow;
    } on TimeoutException catch (error) {
      await transport.close();
      throw PluginProtocolException(
        'Plugin did not complete protocol v1 handshake: $error',
      );
    } finally {
      _connecting = false;
    }
  }

  Future<void> runOnce() async {
    await connect();
    await sendLifecycleHook(LifecycleHook.start.value);
    await stop();
  }

  void _handleTransportMessage(Uint8List bytes) {
    metrics?.recordReceived(bytes.length);
    if (bytes.length > PluginPerfBudget.maxMessageBytes) {
      metrics?.recordDrop();
      onOutput?.call(
        '[$pluginId/$sessionId] dropped oversized message '
        '(${bytes.length} bytes)',
      );
      return;
    }

    // Preserve wire order per plugin while moving expensive JSON parsing off
    // the Flutter UI isolate. Each PluginRunManager owns its own tail, so one
    // slow plugin cannot serialize decoding for another plugin session.
    _decodeTail = _decodeTail.then((_) => _decodeAndEnqueue(bytes)).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      metrics?.recordError('$error', traceback: '$stackTrace');
      onOutput?.call('[$pluginId/$sessionId] invalid plugin message: $error');
    });
  }

  Future<void> _decodeAndEnqueue(Uint8List bytes) async {
    if (_stopped) return;
    final envelope = bytes.length > PluginPerfBudget.maxInlineJsonBytes
        ? await Isolate.run(() => _decodePluginEnvelope(bytes))
        : _decodePluginEnvelope(bytes);
    final message = _InboundPluginMessage(
      envelope: envelope,
      encodedBytes: bytes.length,
    );
    if ((message.type == SdkCommands.viewSnapshot ||
            message.type == SdkCommands.viewPatch) &&
        message.encodedBytes > PluginPerfBudget.maxViewPayloadBytes) {
      metrics?.recordDrop();
      _rejectInbound(message, queue: 'view payload');
      return;
    }
    if (message.type == SdkCommands.viewPatch) {
      if (metrics?.eventDeliveryPaused == true) {
        metrics?.recordDrop();
        _rejectInbound(
          message,
          queue: 'view patch',
          code: 'delivery_paused',
          messageText:
              'View patch delivery is paused after repeated plugin failures',
        );
        return;
      }
      _enqueueViewPatch(message);
    } else {
      _enqueueControl(message);
    }
  }

  void _enqueueControl(_InboundPluginMessage message) {
    if (_controlQueue.length >= PluginPerfBudget.controlQueueCapacity) {
      metrics?.recordDrop();
      _rejectInbound(message, queue: 'control');
      return;
    }
    _controlQueue.addLast(message);
    metrics?.recordControlQueueDepth(_controlQueue.length);
    _drainInbound();
  }

  void _enqueueViewPatch(_InboundPluginMessage message) {
    while (_viewPatchQueue.length >= PluginPerfBudget.viewPatchQueueCapacity) {
      final dropped = _viewPatchQueue.removeFirst();
      metrics?.recordDrop();
      _rejectInbound(dropped, queue: 'view patch');
    }
    _viewPatchQueue.addLast(message);
    metrics?.recordPatchQueueDepth(_viewPatchQueue.length);
    _drainInbound();
  }

  void _rejectInbound(
    _InboundPluginMessage message, {
    required String queue,
    String code = 'backpressure',
    String? messageText,
  }) {
    final requestId = message.requestId;
    onOutput?.call(
      '[$pluginId/$sessionId] dropped ${message.type} because the $queue queue '
      'is full',
    );
    if (requestId == null ||
        requestId.isEmpty ||
        _transportState != PluginTransportState.ready) {
      return;
    }
    sendJson(
      makeEnvelope(
        type: SdkCommands.responseError,
        replyTo: requestId,
        payload: {
          'code': code,
          'message': messageText ?? 'The IDE $queue queue is full',
        },
      ),
    );
  }

  void _drainInbound() {
    if (_drainingInbound) return;
    _drainingInbound = true;
    scheduleMicrotask(_drainInboundBatch);
  }

  void _drainInboundBatch() {
    try {
      var processed = 0;
      while ((_controlQueue.isNotEmpty || _viewPatchQueue.isNotEmpty) &&
          processed < PluginPerfBudget.inboundDrainBatchSize) {
        final next = _removeNextInbound();
        _dispatchTransportMessage(next);
        processed += 1;
      }
    } finally {
      _drainingInbound = false;
      if ((_controlQueue.isNotEmpty || _viewPatchQueue.isNotEmpty) &&
          !_stopped) {
        Timer.run(_drainInbound);
      }
    }
  }

  _InboundPluginMessage _removeNextInbound() {
    if (_controlQueue.isEmpty) {
      final next = _viewPatchQueue.removeFirst();
      metrics?.recordPatchQueueDepth(_viewPatchQueue.length);
      return next;
    }
    if (_viewPatchQueue.isEmpty) {
      final next = _controlQueue.removeFirst();
      metrics?.recordControlQueueDepth(_controlQueue.length);
      return next;
    }

    final controlSequence = _queueSequence(_controlQueue.first);
    final patchSequence = _queueSequence(_viewPatchQueue.first);
    if (controlSequence < patchSequence) {
      final next = _controlQueue.removeFirst();
      metrics?.recordControlQueueDepth(_controlQueue.length);
      return next;
    }
    final next = _viewPatchQueue.removeFirst();
    metrics?.recordPatchQueueDepth(_viewPatchQueue.length);
    return next;
  }

  int _queueSequence(_InboundPluginMessage message) {
    final sequence = message.envelope['sequence'];
    return sequence is int ? sequence : -1;
  }

  void _dispatchTransportMessage(_InboundPluginMessage message) {
    final envelope = message.envelope;
    final encodedMessage = jsonEncode(envelope);
    try {
      PluginProtocol.validateIncoming(envelope);
      if (envelope['sessionId'] != sessionId ||
          envelope['generation'] != generation ||
          (pluginId.isNotEmpty && envelope['pluginId'] != pluginId)) {
        onOutput?.call(
          '[$pluginId/$sessionId] ignored stale or mismatched envelope',
        );
        return;
      }
      final incomingSequence = envelope['sequence'] as int;
      if (_incomingSequence != 0 && incomingSequence <= _incomingSequence) {
        throw PluginProtocolException(
          'Duplicate or out-of-order sequence: $incomingSequence',
        );
      }
      _incomingSequence = incomingSequence;
      envelope['id'] = envelope['requestId'];
      envelope['reply_to'] = envelope['replyTo'];
      envelope['version'] = '${envelope['protocolVersion']}.0';
    } on PluginProtocolException catch (error) {
      onOutput?.call('[$pluginId/$sessionId] protocol error: $error');
      metrics?.recordError('$error');
      if (!(_handshake?.isCompleted ?? true)) {
        _handshake!.completeError(error);
      }
      return;
    }
    final type = envelope['type']?.toString() ?? '';
    const preHandshakeTypes = {
      SdkCommands.initialize,
      SdkCommands.ready,
      SdkCommands.outputAppend,
      SdkCommands.responseError,
      SdkCommands.healthPong,
      SdkCommands.runtimeReportError,
    };
    if (!_protocolReady && !preHandshakeTypes.contains(type)) {
      final error = PluginProtocolException(
        'Business message before sdk.ready: $type',
      );
      onOutput?.call('[$pluginId/$sessionId] protocol error: $error');
      if (!(_handshake?.isCompleted ?? true)) {
        _handshake!.completeError(error);
      }
      return;
    }
    if (type == SdkCommands.runtimeReportError) {
      final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
      metrics?.recordError(
        payload['message']?.toString() ?? 'plugin error',
        traceback: payload['traceback']?.toString(),
      );
      onOutput?.call(
        '[$pluginId/$sessionId] reported error: '
        '${payload['message']}\n${payload['traceback'] ?? ''}',
      );
      return;
    }
    if (type != SdkCommands.outputAppend) {
      onOutput?.call('[$pluginId/$sessionId] <- $encodedMessage');
    }
    if (type == IdeCommands.responseError ||
        type == SdkCommands.responseError) {
      final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
      final details = payload['details']?.toString();
      metrics?.recordError(
        payload['message']?.toString() ?? 'response error',
        traceback: details,
      );
      if (details != null && details.isNotEmpty && details != 'null') {
        onOutput?.call('[$pluginId/$sessionId] error details:\n$details');
      }
    }

    if (type == SdkCommands.initialize) {
      final payload = envelope['payload'] as Map<String, dynamic>;
      if (payload['protocolVersion'] != PluginProtocol.version) {
        final error = PluginProtocolException(
          'SDK reported unsupported protocolVersion: '
          '${payload['protocolVersion']}',
        );
        if (!(_handshake?.isCompleted ?? true)) {
          _handshake!.completeError(error);
        }
        return;
      }
      final sdkCapabilities = (payload['capabilities'] as List? ?? const [])
          .map((value) => value.toString())
          .toSet();
      negotiatedCapabilities.addAll(sdkCapabilities.intersection({'sdk.v1'}));
      sdkVersion = payload['sdkVersion']?.toString();
      if (!negotiatedCapabilities.contains('sdk.v1')) {
        final error = const PluginProtocolException(
          'SDK does not support required capability sdk.v1',
        );
        if (!(_handshake?.isCompleted ?? true)) {
          _handshake!.completeError(error);
        }
        return;
      }
      sendJson(
        makeEnvelope(
          type: IdeCommands.initialized,
          pluginId: pluginId.isEmpty ? 'standalone' : pluginId,
          sessionId: sessionId,
          generation: generation,
          replyTo: _requestId(envelope),
          payload: {
            'protocolVersion': PluginProtocol.version,
            'capabilities': ['sdk.v1'],
          },
        ),
      );
      return;
    }
    if (type == SdkCommands.ready) {
      _protocolReady = true;
      metrics?.markActivated();
      if (!(_handshake?.isCompleted ?? true)) _handshake!.complete();
      return;
    }

    // Check if this is a reply to a pending request
    final replyTo = _replyTo(envelope);
    if (replyTo != null && _cancelledRequests.remove(replyTo)) {
      onOutput?.call(
        '[$pluginId/$sessionId] ignored reply for cancelled request $replyTo',
      );
      return;
    }
    if (replyTo != null && _pendingReplies.containsKey(replyTo)) {
      _pendingReplies.remove(replyTo)!.complete(envelope);
      return;
    }
    if (replyTo != null) {
      onOutput?.call(
        '[$pluginId/$sessionId] ignored unknown or duplicate replyTo=$replyTo',
      );
      return;
    }

    // Dispatch to registered handler
    final handler = _handlers[type];
    if (handler != null) {
      handler(envelope, sendJson);
      return;
    }
    if (type.startsWith('sdk.')) {
      permissionLog?.add(
        PermissionLogEntry(
          pluginId: pluginId,
          command: type,
          required: 'unknown',
          decision: PermissionDecision.unknown,
        ),
      );
      _respondAccessError(
        envelope,
        sendJson,
        code: 'unknown_command',
        message: 'Unknown SDK command: $type',
      );
    }
  }

  void _handleTransportError(Object error, [StackTrace? stackTrace]) {
    onOutput?.call('[$pluginId] transport error: $error');
    if (!(_handshake?.isCompleted ?? true)) {
      _handshake!.completeError(error, stackTrace);
    }
    _failAllPendingReplies(error);
  }

  void _handleTransportState(PluginTransportState state) {
    switch (state) {
      case PluginTransportState.connecting:
        if (_transportState != PluginTransportState.ready) {
          _transportState = PluginTransportState.connecting;
        }
        onOutput?.call('[$pluginId] transport connecting');
        return;
      case PluginTransportState.ready:
        _transportState = PluginTransportState.ready;
        onOutput?.call('[$pluginId] transport connected');
        return;
      case PluginTransportState.closing:
        _transportState = PluginTransportState.closing;
        onOutput?.call('[$pluginId] transport closing');
        return;
      case PluginTransportState.closed:
        _transportState = PluginTransportState.closed;
        onOutput?.call('[$pluginId] transport closed');
        if (!(_handshake?.isCompleted ?? true)) {
          _handshake!.completeError(
            const PluginProtocolException(
              'Transport closed before protocol handshake completed',
            ),
          );
        }
        _failAllPendingReplies('Plugin transport closed');
        return;
      case PluginTransportState.failed:
        _transportState = PluginTransportState.failed;
        onOutput?.call('[$pluginId] transport failed');
        return;
    }
  }

  void _failAllPendingReplies(dynamic error) {
    for (final completer in _pendingReplies.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pendingReplies.clear();
    _pendingStartedAt.clear();
  }

  void _clearInboundState() {
    _controlQueue.clear();
    _viewPatchQueue.clear();
    _cancelledRequests.clear();
    metrics?.recordControlQueueDepth(0);
    metrics?.recordPatchQueueDepth(0);
  }

  // -- Sending ---------------------------------------------------------------

  void send(String message) {
    if (_transportState != PluginTransportState.ready) {
      throw StateError('Plugin transport is not ready');
    }
    final outgoing = _prepareOutgoing(
      jsonDecode(message) as Map<String, dynamic>,
    );
    final outgoingMessage = jsonEncode(outgoing);
    if (!_isRoutineAck(outgoingMessage)) {
      onOutput?.call('[$pluginId/$sessionId] -> $outgoingMessage');
    }
    final bytes = utf8.encode(outgoingMessage);
    metrics?.recordSent(bytes.length);
    unawaited(_sendTransportMessage(outgoingMessage));
  }

  Future<void> _sendTransportMessage(String message) async {
    try {
      await transport.send(Uint8List.fromList(utf8.encode(message)));
    } catch (error, stackTrace) {
      _handleTransportError(error, stackTrace);
    }
  }

  Map<String, dynamic> _prepareOutgoing(Map<String, dynamic> envelope) {
    final normalized = Map<String, dynamic>.from(envelope);
    final requestId = _normalizeRequestId(
      normalized['requestId'] ?? normalized['id'],
    );
    final replyTo = normalized['replyTo'] ?? normalized['reply_to'];
    normalized
      ..remove('version')
      ..remove('id')
      ..remove('reply_to')
      ..['protocolVersion'] = PluginProtocol.version
      ..['pluginId'] = pluginId.isEmpty ? 'standalone' : pluginId
      ..['sessionId'] = sessionId
      ..['generation'] = generation
      ..['requestId'] = requestId.toString()
      ..['replyTo'] = replyTo
      ..['sequence'] = ++_outgoingSequence;
    return normalized;
  }

  String _normalizeRequestId(Object? value) {
    final candidate = value?.toString() ?? '';
    return candidate.isEmpty ? _newId() : candidate;
  }

  bool _isRoutineAck(String message) {
    try {
      final envelope = jsonDecode(message) as Map<String, dynamic>;
      return envelope['type'] == SdkCommands.responseOk &&
          envelope['payload'] is Map &&
          (envelope['payload'] as Map)['data'] == null;
    } catch (_) {
      return false;
    }
  }

  void _handleOutputAppend(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final stream = payload['stream']?.toString() ?? 'stdout';
    final text = payload['text']?.toString() ?? '';
    final sourcePluginId = payload['plugin_id']?.toString() ?? pluginId;
    if (text.isNotEmpty) {
      final encoded = utf8.encode(text);
      final limited = encoded.length <= PluginPerfBudget.maxLogBatchBytes
          ? text
          : utf8.decode(
              encoded.take(PluginPerfBudget.maxLogBatchBytes).toList(),
              allowMalformed: true,
            );
      if (limited.length != text.length) {
        metrics?.recordDrop();
        onOutput?.call(
          '[$sourcePluginId][$stream] log batch truncated at '
          '${PluginPerfBudget.maxLogBatchBytes} bytes',
        );
      }
      onOutput?.call('[$sourcePluginId][$stream] $limited');
    }
  }

  void sendJson(Map<String, dynamic> envelope) {
    send(jsonEncode(envelope));
  }

  Future<Map<String, dynamic>> sendAndWaitReply(
    Map<String, dynamic> envelope, {
    Duration timeout = PluginPerfBudget.rpcTimeout,
    bool connectIfNeeded = true,
  }) async {
    if (connectIfNeeded) {
      await connect();
    } else if (_transportState != PluginTransportState.ready) {
      throw StateError('Plugin transport is not ready');
    }
    final id = _normalizeRequestId(envelope['requestId'] ?? envelope['id']);
    envelope['requestId'] = id;
    envelope['deadline'] ??= DateTime.now().add(timeout).millisecondsSinceEpoch;
    final completer = Completer<Map<String, dynamic>>();
    _pendingReplies[id] = completer;
    _pendingStartedAt[id] = DateTime.now();
    try {
      send(jsonEncode(envelope));
    } catch (_) {
      _pendingReplies.remove(id);
      _pendingStartedAt.remove(id);
      rethrow;
    }
    try {
      final response = await completer.future.timeout(
        timeout,
        onTimeout: () {
          _pendingReplies.remove(id);
          _pendingStartedAt.remove(id);
          metrics?.recordTimeout();
          _notifyRequestCancelled(id);
          throw TimeoutException('Plugin request timed out', timeout);
        },
      );
      final started = _pendingStartedAt.remove(id);
      if (started != null) {
        metrics?.recordRpcLatency(DateTime.now().difference(started));
        metrics?.recordSuccess();
      }
      return response;
    } on TimeoutException {
      rethrow;
    } catch (error) {
      _pendingStartedAt.remove(id);
      metrics?.recordError('$error');
      rethrow;
    }
  }

  /// Cancels an in-flight request and notifies the plugin.
  bool cancelRequest(String requestId) {
    final completer = _pendingReplies.remove(requestId);
    _pendingStartedAt.remove(requestId);
    if (completer == null) return false;
    _cancelledRequests.add(requestId);
    _trimCancelledRequestHistory();
    metrics?.recordCancellation();
    if (!completer.isCompleted) {
      completer.completeError(
        TimeoutException('Plugin request cancelled', Duration.zero),
      );
    }
    _sendRequestCancellation(requestId);
    return true;
  }

  void _notifyRequestCancelled(String requestId) {
    _cancelledRequests.add(requestId);
    _trimCancelledRequestHistory();
    metrics?.recordCancellation();
    _sendRequestCancellation(requestId);
  }

  void _trimCancelledRequestHistory() {
    while (_cancelledRequests.length >
        PluginPerfBudget.cancelledRequestHistory) {
      _cancelledRequests.remove(_cancelledRequests.first);
    }
  }

  void _sendRequestCancellation(String requestId) {
    if (_transportState != PluginTransportState.ready) return;
    sendJson(
      makeEnvelope(
        type: IdeCommands.requestCancel,
        payload: {'requestId': requestId},
      ),
    );
  }

  // -- IDE -> SDK commands ---------------------------------------------------

  Future<void> sendLifecycleHook(
    String hook, {
    bool connectIfNeeded = true,
    bool waitForReply = false,
  }) async {
    if (connectIfNeeded) {
      await connect();
    } else if (_transportState != PluginTransportState.ready) {
      return;
    }
    final envelope = makeEnvelope(
      type: IdeCommands.lifecycleHook,
      payload: {'hook': hook},
    );
    if (!waitForReply) {
      sendJson(envelope);
      return;
    }
    final response = await sendAndWaitReply(envelope, connectIfNeeded: false);
    final responseType = response['type']?.toString() ?? '';
    if (responseType.endsWith('.error')) {
      final payload = response['payload'] as Map<String, dynamic>? ?? {};
      throw PluginProtocolException(
        payload['message']?.toString() ?? 'Plugin lifecycle hook failed: $hook',
      );
    }
  }

  /// Delivers a host event to the plugin.
  ///
  /// Fire-and-forget: events are one-directional and must not block the bus.
  /// Delivery is skipped unless the protocol handshake has completed.
  void sendEvent({
    required String subscriptionId,
    required String topic,
    required List<Map<String, dynamic>> payloads,
  }) {
    if (_stopped || _transportState != PluginTransportState.ready) return;
    sendJson(
      makeEnvelope(
        type: IdeCommands.eventEmit,
        payload: {
          'subscriptionId': subscriptionId,
          'topic': topic,
          'events': payloads,
        },
      ),
    );
  }

  /// Sends a view-protocol control frame (ack/nack/resync) to the plugin.
  ///
  /// Fire-and-forget, like [sendEvent]; skipped until the handshake completes.
  void sendViewFrame(String type, Map<String, dynamic> payload) {
    if (_stopped || _transportState != PluginTransportState.ready) return;
    sendJson(makeEnvelope(type: type, payload: payload));
  }

  Future<Duration> ping({
    Duration timeout = PluginPerfBudget.uiRpcTimeout,
  }) async {
    final started = DateTime.now();
    try {
      final response = await sendAndWaitReply(
        makeEnvelope(type: IdeCommands.healthPing),
        timeout: timeout,
      );
      if (response['type'] != SdkCommands.healthPong) {
        throw StateError('Unexpected health response: ${response['type']}');
      }
      final latency = DateTime.now().difference(started);
      metrics?.recordHealth(latency);
      return latency;
    } catch (error) {
      metrics?.recordHealthFailure(error);
      rethrow;
    }
  }

  // -- Cleanup ---------------------------------------------------------------

  bool _stopped = false;

  Future<void> stop() async {
    _stopped = true;
    metrics?.markStopping();
    onOutput?.call('[$pluginId] stopped');
    _failAllPendingReplies('PluginRunManager stopped');
    await transport.close();
    await _messageSubscription.cancel();
    await _stateSubscription.cancel();
    _clearInboundState();
    runtimeData.clear();
    _handlers.clear();
    metrics?.markStopped();
  }

  void dispose() {
    _failAllPendingReplies('PluginRunManager disposed');
    _clearInboundState();
    unawaited(transport.close());
    unawaited(_messageSubscription.cancel());
    unawaited(_stateSubscription.cancel());
  }
}
