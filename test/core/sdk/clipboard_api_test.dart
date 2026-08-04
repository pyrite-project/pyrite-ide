import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/api/clipboard_api.dart';
import 'package:pyrite_ide/core/sdk/permissions.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/sdk/plugin_transport.dart';

class _ClipboardTransport implements PluginTransport {
  final StreamController<Uint8List> _messages =
      StreamController<Uint8List>.broadcast();
  final StreamController<PluginTransportState> _states =
      StreamController<PluginTransportState>.broadcast();
  FutureOr<void> Function(Uint8List message)? onSend;
  bool _closed = false;

  @override
  String get type => 'Fake';

  @override
  Stream<Uint8List> get messages => _messages.stream;

  @override
  Stream<PluginTransportState> get states => _states.stream;

  @override
  Future<void> start() async {
    if (_closed) throw StateError('Clipboard transport is closed');
    _states.add(PluginTransportState.connecting);
    _states.add(PluginTransportState.ready);
  }

  @override
  Future<void> send(Uint8List message) async {
    if (_closed) throw StateError('Clipboard transport is closed');
    await onSend?.call(message);
  }

  void emit(Map<String, dynamic> envelope) {
    _messages.add(Uint8List.fromList(utf8.encode(jsonEncode(envelope))));
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _states.add(PluginTransportState.closing);
    _states.add(PluginTransportState.closed);
    await _messages.close();
    await _states.close();
  }
}

class _ClipboardHarness {
  _ClipboardHarness._(this.container);

  final ProviderContainer container;
  final StreamController<Map<String, dynamic>> _responses =
      StreamController<Map<String, dynamic>>.broadcast();

  late final PluginRunManager manager;
  late final _ClipboardTransport transport;
  int _sdkSequence = 2;

  static Future<_ClipboardHarness> start({
    Map<String, List<String>> permissions = const {
      'ui': ['view'],
    },
    String pluginId = 'clipboard-test',
    String assetsPath = '.',
  }) async {
    final harness = _ClipboardHarness._(ProviderContainer());
    harness.transport = _ClipboardTransport();
    harness.transport.onSend = (message) {
      final envelope = jsonDecode(utf8.decode(message)) as Map<String, dynamic>;
      switch (envelope['type']) {
        case IdeCommands.initialize:
          harness.transport.emit(
            makeEnvelope(
              type: SdkCommands.initialize,
              pluginId: envelope['pluginId'] as String,
              sessionId: envelope['sessionId'] as String,
              generation: envelope['generation'] as int,
              replyTo: envelope['requestId'] as String,
              sequence: 1,
              payload: {
                'protocolVersion': 1,
                'sdkVersion': 'fixture',
                'capabilities': ['sdk.v1'],
              },
            ),
          );
        case IdeCommands.initialized:
          harness.transport.emit(
            makeEnvelope(
              type: SdkCommands.ready,
              pluginId: envelope['pluginId'] as String,
              sessionId: envelope['sessionId'] as String,
              generation: envelope['generation'] as int,
              replyTo: envelope['requestId'] as String,
              sequence: 2,
              payload: {
                'capabilities': ['sdk.v1'],
              },
            ),
          );
        default:
          harness._responses.add(envelope);
      }
    };

    harness.manager = PluginRunManager(
      transport: harness.transport,
      assetsPath: assetsPath,
      pluginId: pluginId,
      pluginPermissions: permissions,
    );
    harness.container.read(sdkClipboardApiProvider).bind(harness.manager);

    await harness.manager.connect();
    return harness;
  }

  Future<Map<String, dynamic>> request(
    String type, {
    Map<String, dynamic> payload = const {},
  }) async {
    final envelope = makeEnvelope(
      type: type,
      payload: payload,
      pluginId: manager.pluginId,
      sessionId: manager.sessionId,
      generation: manager.generation,
      sequence: ++_sdkSequence,
    );
    final response = _responses.stream
        .firstWhere((item) => item['replyTo'] == envelope['requestId'])
        .timeout(const Duration(seconds: 5));
    transport.emit(envelope);
    return response;
  }

  Future<void> close() async {
    await manager.stop();
    await _responses.close();
    container.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('clipboard command requires the ui:view permission', () {
    expect(Permissions.getRequirement(SdkClipboardCommands.setText), 'ui:view');
  });

  test('sdk.clipboard.set_text copies text to the system clipboard', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });

    final harness = await _ClipboardHarness.start();
    addTearDown(harness.close);

    final response = await harness.request(
      SdkClipboardCommands.setText,
      payload: {'text': '42'},
    );

    expect(response['type'], SdkCommands.responseOk);
    expect(response['payload'], {'data': true});
    final copy = calls
        .where((call) => call.method == 'Clipboard.setData')
        .toList();
    expect(copy, hasLength(1));
    expect(copy.single.arguments, {'text': '42'});
  });

  test('clipboard set without ui:view permission is denied', () async {
    final harness = await _ClipboardHarness.start(permissions: const {});
    addTearDown(harness.close);

    final response = await harness.request(
      SdkClipboardCommands.setText,
      payload: {'text': 'secret'},
    );

    expect(response['type'], SdkCommands.responseError);
    expect(response['payload']['code'], 'permission_denied');
    expect(response['payload']['details'], {'required': 'ui:view'});
  });
}
