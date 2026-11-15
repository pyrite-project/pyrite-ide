import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/api/file.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/sdk/plugin_transport.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';

class _Transport implements PluginTransport {
  final StreamController<Uint8List> _messages =
      StreamController<Uint8List>.broadcast();
  final StreamController<PluginTransportState> _states =
      StreamController<PluginTransportState>.broadcast();
  final _responses = StreamController<Map<String, dynamic>>.broadcast();

  @override
  String get type => 'Fake';

  @override
  Stream<Uint8List> get messages => _messages.stream;

  @override
  Stream<PluginTransportState> get states => _states.stream;

  @override
  Future<void> start() async {
    _states.add(PluginTransportState.connecting);
    _states.add(PluginTransportState.ready);
  }

  @override
  Future<void> send(Uint8List message) async {
    final envelope = jsonDecode(utf8.decode(message)) as Map<String, dynamic>;
    switch (envelope['type']) {
      case IdeCommands.initialize:
        emit(SdkCommands.initialize, envelope, 1, {
          'protocolVersion': 1,
          'capabilities': ['sdk.v1'],
        });
      case IdeCommands.initialized:
        emit(SdkCommands.ready, envelope, 2, {
          'capabilities': ['sdk.v1'],
        });
      default:
        _responses.add(envelope);
    }
  }

  void emit(String type, Map<String, dynamic> req, int seq, Map payload) {
    _messages.add(
      Uint8List.fromList(
        utf8.encode(
          jsonEncode(
            makeEnvelope(
              type: type,
              pluginId: req['pluginId'] as String,
              sessionId: req['sessionId'] as String,
              generation: req['generation'] as int,
              replyTo: req['requestId'] as String,
              sequence: seq,
              payload: Map<String, dynamic>.from(payload),
            ),
          ),
        ),
      ),
    );
  }

  Stream<Map<String, dynamic>> get responses => _responses.stream;

  void inject(Map<String, dynamic> envelope) {
    _messages.add(Uint8List.fromList(utf8.encode(jsonEncode(envelope))));
  }

  @override
  Future<void> close() async {
    await _messages.close();
    await _states.close();
    await _responses.close();
  }
}

/// Stands in for the save path so the test can pick the outcome without
/// building a real read-only tab or driving a file conflict prompt.
class _StubFileNotifier extends FileNotifier {
  _StubFileNotifier(super.ref, {required this.result});

  final bool result;

  @override
  Future<bool> saveCurrentFile() async => result;
}

Future<({PluginRunManager manager, _Transport transport})> _start(
  ProviderContainer container,
) async {
  final transport = _Transport();
  final manager = PluginRunManager(
    transport: transport,
    assetsPath: '.',
    pluginId: 'file-test',
    pluginPermissions: const {
      'file': ['read', 'write'],
    },
    sessionId: 'session-1',
    generation: 1,
  );
  container.read(sdkFileProvider).bind(manager);
  await manager.connect();
  return (manager: manager, transport: transport);
}

Future<Map<String, dynamic>> _request(
  PluginRunManager manager,
  _Transport transport,
  String type,
) async {
  final envelope = makeEnvelope(
    type: type,
    payload: const {},
    pluginId: manager.pluginId,
    sessionId: manager.sessionId,
    generation: manager.generation,
    sequence: 100,
  );
  final response = transport.responses
      .firstWhere((e) => e['replyTo'] == envelope['requestId'])
      .timeout(const Duration(seconds: 5));
  transport.inject(envelope);
  return response;
}

void main() {
  Future<Map<String, dynamic>> runSave(bool result) async {
    final container = ProviderContainer(
      overrides: [
        fileProvider.overrideWith(
          (ref) => _StubFileNotifier(ref, result: result),
        ),
      ],
    );
    addTearDown(container.dispose);
    final started = await _start(container);
    addTearDown(started.manager.stop);
    return _request(
      started.manager,
      started.transport,
      SdkFileCommands.saveCurrentFile,
    );
  }

  test('save_current_file reports an error when nothing was written', () async {
    final response = await runSave(false);
    expect(response['type'], SdkCommands.responseError);
    expect(
      (response['payload'] as Map<String, dynamic>)['message'],
      isNotEmpty,
    );
  });

  test(
    'save_current_file reports success only after the write completes',
    () async {
      final response = await runSave(true);
      expect(response['type'], SdkCommands.responseOk);
    },
  );
}
