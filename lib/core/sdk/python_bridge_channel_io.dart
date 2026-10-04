import 'dart:typed_data';

import 'package:pyrite_ide/core/sdk/python_bridge_plugin_transport.dart';
import 'package:serious_python/bridge.dart';

/// Native bridge channel backed by `serious_python`'s DartBridge.
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

/// Session token shared with the Python side through the environment.
String pythonBridgeSessionToken() => '${DartBridge.dartSessionToken}';
