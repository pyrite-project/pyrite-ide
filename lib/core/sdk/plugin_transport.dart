import 'dart:typed_data';

enum PluginTransportState { connecting, ready, closing, closed, failed }

abstract interface class PluginTransport {
  String get type;

  Stream<Uint8List> get messages;

  Stream<PluginTransportState> get states;

  Future<void> start();

  Future<void> send(Uint8List message);

  Future<void> close();
}

abstract interface class PluginLaunchTransport implements PluginTransport {
  Map<String, String> get startupEnvironment;
}
