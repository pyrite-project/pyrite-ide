import 'dart:async';
import 'dart:typed_data';

import 'package:pyrite_ide/core/sdk/plugin_transport.dart';
import 'package:serious_python/bridge.dart';

abstract interface class PluginPythonBridgeChannel {
  int get port;

  Stream<Uint8List> get messages;

  bool send(Uint8List message);

  void signalDartSession(String channelLabel);

  void close();
}

class SeriousPythonBridgeChannel implements PluginPythonBridgeChannel {
  SeriousPythonBridgeChannel() : _bridge = PythonBridge();

  final PythonBridge _bridge;

  @override
  int get port => _bridge.port;

  @override
  Stream<Uint8List> get messages => _bridge.messages;

  @override
  bool send(Uint8List message) => _bridge.send(message);

  @override
  void signalDartSession(String channelLabel) {
    DartBridge.instance.signalDartSession({channelLabel: port});
  }

  @override
  void close() => _bridge.close();
}

class PythonBridgePluginTransport implements PluginLaunchTransport {
  static const portEnvironmentVariable = 'PYRITE_IDE_PLUGIN_BRIDGE_PORT';
  static const channelLabelEnvironmentVariable =
      'PYRITE_IDE_PLUGIN_BRIDGE_LABEL';
  static const dartSessionTokenEnvironmentVariable =
      'PYRITE_IDE_DART_SESSION_TOKEN';

  PythonBridgePluginTransport({
    required this.channelLabel,
    PluginPythonBridgeChannel? channel,
    this.sendTimeout = const Duration(seconds: 5),
    this.retryInterval = const Duration(milliseconds: 25),
  }) : _channel = channel ?? SeriousPythonBridgeChannel() {
    if (channelLabel.isEmpty) {
      throw ArgumentError.value(
        channelLabel,
        'channelLabel',
        'must not be empty',
      );
    }
    if (sendTimeout <= Duration.zero) {
      throw ArgumentError.value(sendTimeout, 'sendTimeout', 'must be positive');
    }
    if (retryInterval <= Duration.zero) {
      throw ArgumentError.value(
        retryInterval,
        'retryInterval',
        'must be positive',
      );
    }
  }

  final String channelLabel;
  final Duration sendTimeout;
  final Duration retryInterval;
  final PluginPythonBridgeChannel _channel;
  final StreamController<Uint8List> _messages =
      StreamController<Uint8List>.broadcast();
  final StreamController<PluginTransportState> _states =
      StreamController<PluginTransportState>.broadcast();

  StreamSubscription<Uint8List>? _subscription;
  PluginTransportState _state = PluginTransportState.closed;
  Future<void>? _closeFuture;
  bool _closed = false;

  @override
  String get type => 'PythonBridge';

  int get port => _channel.port;

  @override
  Map<String, String> get startupEnvironment => {
    portEnvironmentVariable: '$port',
    channelLabelEnvironmentVariable: channelLabel,
    dartSessionTokenEnvironmentVariable: '${DartBridge.dartSessionToken}',
  };

  @override
  Stream<Uint8List> get messages => _messages.stream;

  @override
  Stream<PluginTransportState> get states => _states.stream;

  @override
  Future<void> start() async {
    if (_closed) throw StateError('PythonBridgePluginTransport is closed');
    if (_state == PluginTransportState.ready) return;

    _emitState(PluginTransportState.connecting);
    _subscription ??= _channel.messages.listen(
      _handleMessage,
      onError: _handleError,
      onDone: _handleDone,
      cancelOnError: false,
    );
    _channel.signalDartSession(channelLabel);
    _emitState(PluginTransportState.ready);
  }

  void _handleMessage(Uint8List message) {
    if (!_messages.isClosed) _messages.add(message);
  }

  void _handleError(Object error, StackTrace stackTrace) {
    if (!_messages.isClosed) _messages.addError(error, stackTrace);
    _emitState(PluginTransportState.failed);
  }

  void _handleDone() {
    if (_state != PluginTransportState.closing) {
      _emitState(PluginTransportState.closed);
    }
  }

  void _emitState(PluginTransportState state) {
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }

  @override
  Future<void> send(Uint8List message) async {
    if (_closed) throw StateError('PythonBridgePluginTransport is closed');
    if (_state != PluginTransportState.ready) {
      throw StateError('PythonBridgePluginTransport is not ready');
    }

    final stopwatch = Stopwatch()..start();
    while (!_closed) {
      try {
        if (_channel.send(message)) return;
      } catch (error, stackTrace) {
        _handleError(error, stackTrace);
        rethrow;
      }
      if (stopwatch.elapsed >= sendTimeout) {
        final error = TimeoutException(
          'Python bridge handler for $channelLabel was not ready',
          sendTimeout,
        );
        _handleError(error, StackTrace.current);
        throw error;
      }
      await Future<void>.delayed(retryInterval);
    }
    throw StateError('PythonBridgePluginTransport is closed');
  }

  @override
  Future<void> close() {
    final activeClose = _closeFuture;
    if (activeClose != null) return activeClose;
    if (_closed) return Future<void>.value();

    final future = _close();
    _closeFuture = future;
    return future;
  }

  Future<void> _close() async {
    _closed = true;
    _emitState(PluginTransportState.closing);
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    _channel.close();
    _emitState(PluginTransportState.closed);
    await _messages.close();
    await _states.close();
  }
}
