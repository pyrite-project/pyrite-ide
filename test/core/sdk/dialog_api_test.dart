import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/api/dialog.dart';
import 'package:pyrite_ide/core/sdk/permissions.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/sdk/plugin_transport.dart';

class _DialogTransport implements PluginTransport {
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
    if (_closed) throw StateError('Dialog transport is closed');
    _states.add(PluginTransportState.connecting);
    _states.add(PluginTransportState.ready);
  }

  @override
  Future<void> send(Uint8List message) async {
    if (_closed) throw StateError('Dialog transport is closed');
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

class _FakeDialogFilePicker implements SdkDialogFilePicker {
  String? folderResult;
  List<String?>? filesResult;
  Object? error;
  String? title;
  String? initialDirectory;
  bool? allowMultiple;

  @override
  Future<String?> pickFolder({
    required String title,
    required String? initialDirectory,
  }) async {
    this.title = title;
    this.initialDirectory = initialDirectory;
    if (error case final error?) throw error;
    return folderResult;
  }

  @override
  Future<List<String?>?> pickFiles({
    required String title,
    required String? initialDirectory,
    required bool allowMultiple,
  }) async {
    this.title = title;
    this.initialDirectory = initialDirectory;
    this.allowMultiple = allowMultiple;
    if (error case final error?) throw error;
    return filesResult;
  }
}

class _DialogHarness {
  _DialogHarness._(this.container, this.picker);

  final ProviderContainer container;
  final _FakeDialogFilePicker picker;
  final StreamController<Map<String, dynamic>> _responses =
      StreamController<Map<String, dynamic>>.broadcast();

  late final PluginRunManager manager;
  late final _DialogTransport transport;
  int _sdkSequence = 2;

  static Future<_DialogHarness> start({
    Map<String, List<String>> permissions = const {
      'dialog': ['show'],
    },
  }) async {
    final picker = _FakeDialogFilePicker();
    final container = ProviderContainer(
      overrides: [sdkDialogFilePickerProvider.overrideWithValue(picker)],
    );
    final harness = _DialogHarness._(container, picker);
    harness.transport = _DialogTransport();
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
      assetsPath: '.',
      pluginId: 'dialog-test',
      pluginPermissions: permissions,
    );
    harness.container.read(sdkDialogProvider).bind(harness.manager);
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

void _expectOk(Map<String, dynamic> response, dynamic data) {
  expect(response['type'], SdkCommands.responseOk);
  expect(response['payload'], {'data': data});
}

void main() {
  test('dialog commands require dialog:show permission', () {
    expect(
      Permissions.getRequirement(SdkDialogCommands.openFolder),
      'dialog:show',
    );
    expect(
      Permissions.getRequirement(SdkDialogCommands.openFile),
      'dialog:show',
    );
    expect(
      Permissions.getRequirement(SdkDialogCommands.openFiles),
      'dialog:show',
    );
  });

  test('open file responds with null when selection is cancelled', () async {
    final harness = await _DialogHarness.start();
    addTearDown(harness.close);

    final response = await harness.request(
      SdkDialogCommands.openFile,
      payload: {'initial_directory': '/workspace'},
    );

    _expectOk(response, null);
    expect(harness.picker.title, '选择文件');
    expect(harness.picker.initialDirectory, '/workspace');
    expect(harness.picker.allowMultiple, isFalse);
  });

  test('open files returns non-null paths and uses its own title', () async {
    final harness = await _DialogHarness.start();
    addTearDown(harness.close);
    harness.picker.filesResult = ['/one.py', null, '/two.py'];

    final response = await harness.request(SdkDialogCommands.openFiles);

    _expectOk(response, ['/one.py', '/two.py']);
    expect(harness.picker.title, '选择多个文件');
    expect(harness.picker.allowMultiple, isTrue);
  });

  test('open files responds with null when selection is cancelled', () async {
    final harness = await _DialogHarness.start();
    addTearDown(harness.close);

    final response = await harness.request(SdkDialogCommands.openFiles);

    _expectOk(response, null);
    expect(harness.picker.allowMultiple, isTrue);
  });

  test('open folder preserves custom options and responds on cancel', () async {
    final harness = await _DialogHarness.start();
    addTearDown(harness.close);

    final response = await harness.request(
      SdkDialogCommands.openFolder,
      payload: {'title': 'Choose workspace', 'initialDirectory': '/projects'},
    );

    _expectOk(response, null);
    expect(harness.picker.title, 'Choose workspace');
    expect(harness.picker.initialDirectory, '/projects');
  });

  test('file picker failures return an SDK error response', () async {
    final harness = await _DialogHarness.start();
    addTearDown(harness.close);
    harness.picker.error = StateError('picker unavailable');

    final response = await harness.request(SdkDialogCommands.openFiles);

    expect(response['type'], SdkCommands.responseError);
    expect(response['payload']['message'], contains('picker unavailable'));
  });
}
