import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/api/editor.dart';
import 'package:pyrite_ide/core/sdk/editor_key_capture.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/sdk/plugin_transport.dart';

class _KeyTransport implements PluginTransport {
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
    _states.add(PluginTransportState.connecting);
    _states.add(PluginTransportState.ready);
  }

  @override
  Future<void> send(Uint8List message) async {
    if (_closed) throw StateError('Transport is closed');
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

class _KeyHarness {
  final ProviderContainer container = ProviderContainer();
  final StreamController<Map<String, dynamic>> responses =
      StreamController<Map<String, dynamic>>.broadcast();
  final List<Map<String, dynamic>> frames = <Map<String, dynamic>>[];

  late final PluginRunManager manager;
  late final _KeyTransport transport;
  int _sequence = 2;

  EditorKeyCaptureRegistry get registry =>
      container.read(editorKeyCaptureProvider);

  static Future<_KeyHarness> start({
    Map<String, List<String>> permissions = const {
      'editor': ['read', 'write', 'keys'],
    },
  }) async {
    final harness = _KeyHarness();
    harness.transport = _KeyTransport();
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
        case editorKeyEventCommand:
          // Stand in for the plugin: it always consumes the key.
          harness.frames.add(envelope);
          harness.transport.emit(
            makeEnvelope(
              type: SdkCommands.responseOk,
              pluginId: envelope['pluginId'] as String,
              sessionId: envelope['sessionId'] as String,
              generation: envelope['generation'] as int,
              replyTo: envelope['requestId'] as String,
              sequence: envelope['sequence'] as int,
              payload: {
                'data': {'handled': true},
              },
            ),
          );
        default:
          harness.responses.add(envelope);
      }
    };

    harness.manager = PluginRunManager(
      transport: harness.transport,
      assetsPath: '.',
      pluginId: 'fim-completion',
      pluginPermissions: permissions,
    );
    harness.container.read(sdkEditorProvider).bind(harness.manager);
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
      sequence: ++_sequence,
    );
    final response = responses.stream
        .firstWhere((item) => item['replyTo'] == envelope['requestId'])
        .timeout(const Duration(seconds: 5));
    transport.emit(envelope);
    return response;
  }

  Future<void> dispose() async {
    await manager.stop();
    container.dispose();
    await responses.close();
  }
}

KeyDownEvent _keyDown(LogicalKeyboardKey key) => KeyDownEvent(
  physicalKey: PhysicalKeyboardKey(0x0007002b),
  logicalKey: key,
  character: null,
  timeStamp: Duration.zero,
);

void main() {
  // `interceptKeyEvent` reads the live modifier state off HardwareKeyboard.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('key labels normalize to the plugin-facing capture names', () {
    expect(normalizeEditorKeyName('Tab'), 'tab');
    expect(normalizeEditorKeyName('Escape'), 'escape');
    expect(normalizeEditorKeyName('Arrow Down'), 'arrowDown');
    expect(normalizeEditorKeyName('Numpad 1'), 'numpad1');
    expect(normalizeEditorKeyName('A'), 'a');
    expect(editorKeyEventName(_keyDown(LogicalKeyboardKey.tab)), 'tab');
  });

  test('capture and release move keys between plugin and editor', () async {
    final harness = await _KeyHarness.start();
    addTearDown(harness.dispose);

    expect(harness.registry.hasCaptures, isFalse);
    expect(harness.registry.ownerOf('tab'), isNull);

    final captured = await harness.request(
      SdkEditorCommands.captureKeys,
      payload: {
        'keys': ['tab', 'escape'],
      },
    );
    expect(captured['type'], SdkCommands.responseOk);
    expect(harness.registry.hasCaptures, isTrue);
    expect(harness.registry.ownerOf('Tab')?.pluginId, 'fim-completion');
    expect(
      harness.registry.isCaptured(_keyDown(LogicalKeyboardKey.tab)),
      isTrue,
    );
    expect(
      harness.registry.isCaptured(_keyDown(LogicalKeyboardKey.enter)),
      isFalse,
    );

    await harness.request(
      SdkEditorCommands.releaseKeys,
      payload: {
        'keys': ['tab'],
      },
    );
    expect(harness.registry.ownerOf('tab'), isNull);
    expect(harness.registry.ownerOf('escape'), isNotNull);

    await harness.request(SdkEditorCommands.releaseKeys);
    expect(harness.registry.hasCaptures, isFalse);
  });

  test('a captured key is forwarded to the owning plugin', () async {
    final harness = await _KeyHarness.start();
    addTearDown(harness.dispose);

    await harness.request(
      SdkEditorCommands.captureKeys,
      payload: {
        'keys': ['tab'],
      },
    );

    expect(
      harness.registry.interceptKeyEvent(_keyDown(LogicalKeyboardKey.tab)),
      isTrue,
    );
    expect(
      harness.registry.interceptKeyEvent(_keyDown(LogicalKeyboardKey.enter)),
      isFalse,
    );

    await pumpEventQueue();
    expect(harness.frames.single['type'], editorKeyEventCommand);
    expect((harness.frames.single['payload'] as Map)['key'], 'tab');
    expect((harness.frames.single['payload'] as Map)['isDown'], isTrue);
  });

  test('stopping a plugin hands every key back', () async {
    final harness = await _KeyHarness.start();
    addTearDown(harness.dispose);

    await harness.request(
      SdkEditorCommands.captureKeys,
      payload: {
        'keys': ['tab'],
      },
    );
    expect(harness.registry.hasCaptures, isTrue);

    harness.registry.releasePlugin('fim-completion');
    expect(harness.registry.hasCaptures, isFalse);
    expect(
      harness.registry.interceptKeyEvent(_keyDown(LogicalKeyboardKey.tab)),
      isFalse,
    );
  });

  test('capturing keys needs the editor.keys permission', () async {
    final harness = await _KeyHarness.start(
      permissions: const {
        'editor': ['read', 'write'],
      },
    );
    addTearDown(harness.dispose);

    final denied = await harness.request(
      SdkEditorCommands.captureKeys,
      payload: {
        'keys': ['tab'],
      },
    );
    expect(denied['type'], SdkCommands.responseError);
    expect(
      (denied['payload'] as Map<String, dynamic>)['code'],
      'permission_denied',
    );
    expect(harness.registry.hasCaptures, isFalse);
  });
}
