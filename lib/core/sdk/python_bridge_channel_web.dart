import 'dart:typed_data';

import 'package:pyrite_ide/core/sdk/python_bridge_plugin_transport.dart';

Never _unavailable() => throw StateError(
      'The Python bridge channel is not available in the web build.',
    );

/// Web stub: the Python runtime (and therefore the bridge channel) is not
/// available in the web build, so this channel can never be constructed.
class SeriousPythonBridgeChannel implements PluginPythonBridgeChannel {
  SeriousPythonBridgeChannel() {
    _unavailable();
  }

  @override
  int get port => _unavailable();

  @override
  Stream<Uint8List> get messages => _unavailable();

  @override
  bool send(Uint8List message) => _unavailable();

  @override
  void signalDartSession(String channelLabel) => _unavailable();

  @override
  void close() => _unavailable();
}

/// Placeholder token; never used because channels cannot be created.
String pythonBridgeSessionToken() => '0';
