import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/api/persistence.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/sdk/plugin_transport.dart';

class _PersistenceTransport implements PluginTransport {
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
    if (_closed) throw StateError('Persistence transport is closed');
    _states.add(PluginTransportState.connecting);
    _states.add(PluginTransportState.ready);
  }

  @override
  Future<void> send(Uint8List message) async {
    if (_closed) throw StateError('Persistence transport is closed');
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

class _PersistenceHarness {
  _PersistenceHarness._(this.container, this.root);

  final ProviderContainer container;
  final Directory root;
  final StreamController<Map<String, dynamic>> _responses =
      StreamController<Map<String, dynamic>>.broadcast();

  late final PluginRunManager manager;
  late final _PersistenceTransport transport;
  int _sequence = 2;

  String get dataPath => manager.dataPath;

  static Future<_PersistenceHarness> start() async {
    final root = await Directory.systemTemp.createTemp(
      'pyrite-persistence-test-',
    );
    final container = ProviderContainer();
    final harness = _PersistenceHarness._(container, root);
    harness.transport = _PersistenceTransport();
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
      assetsPath: '${root.path}/plugin',
      pluginId: 'persistence-test',
      pluginPermissions: const {
        'persistence': ['read', 'write'],
      },
    );
    harness.container.read(sdkPersistenceProvider).bind(harness.manager);

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
    final response = _responses.stream
        .firstWhere((item) => item['replyTo'] == envelope['requestId'])
        .timeout(const Duration(seconds: 5));
    transport.emit(envelope);
    return response;
  }

  Future<Map<String, dynamic>> set(String group, String key, dynamic value) {
    return request(
      SdkPersistenceCommands.set,
      payload: {'group': group, 'key': key, 'value': value},
    );
  }

  Future<Map<String, dynamic>> get(String group, String key) {
    return request(
      SdkPersistenceCommands.get,
      payload: {'group': group, 'key': key},
    );
  }

  Future<Map<String, dynamic>> delete(String group, String key) {
    return request(
      SdkPersistenceCommands.delete,
      payload: {'group': group, 'key': key},
    );
  }

  Future<Map<String, dynamic>> listGroups() {
    return request(SdkPersistenceCommands.listGroups);
  }

  Future<Map<String, dynamic>> listKeys(String group) {
    return request(SdkPersistenceCommands.listKeys, payload: {'group': group});
  }

  Future<Map<String, dynamic>> clear(String group) {
    return request(SdkPersistenceCommands.clear, payload: {'group': group});
  }

  Future<void> close() async {
    await manager.stop();
    await _responses.close();
    container.dispose();
    await root.delete(recursive: true);
  }
}

void _expectRejected(Map<String, dynamic> response, String field) {
  expect(response['type'], SdkCommands.responseError, reason: '$response');
  expect(response['payload']['message'], contains(field), reason: '$response');
}

void main() {
  late _PersistenceHarness harness;

  setUp(() async {
    harness = await _PersistenceHarness.start();
  });

  tearDown(() async {
    await harness.close();
  });

  test('every entry point rejects unsafe group names', () async {
    const unsafeGroups = <String>[
      '',
      '.',
      '..',
      '...',
      '../escape',
      'group/../../escape',
      'group/child',
      r'group\child',
      '/absolute',
      r'C:\absolute',
      r'\\server\share',
    ];

    for (final group in unsafeGroups) {
      _expectRejected(await harness.set(group, 'key', 1), 'group');
      _expectRejected(await harness.get(group, 'key'), 'group');
      _expectRejected(await harness.delete(group, 'key'), 'group');
      _expectRejected(await harness.listKeys(group), 'group');
      _expectRejected(await harness.clear(group), 'group');
    }

    expect(await Directory(harness.dataPath).exists(), isFalse);
  });

  test('get, set, and delete reject unsafe keys', () async {
    const unsafeKeys = <String>[
      '',
      '.',
      '..',
      '...',
      '../escape',
      'nested/key',
      r'nested\key',
      '/absolute',
      r'C:\absolute',
    ];

    for (final key in unsafeKeys) {
      _expectRejected(await harness.set('safe', key, 1), 'key');
      _expectRejected(await harness.get('safe', key), 'key');
      _expectRejected(await harness.delete('safe', key), 'key');
    }

    expect(await Directory('${harness.dataPath}/safe').exists(), isFalse);
  });

  test('clear cannot delete a directory outside the data path', () async {
    final outside = Directory('${harness.root.path}/outside');
    await outside.create(recursive: true);
    final keep = File('${outside.path}/keep.txt');
    await keep.writeAsString('keep');

    // dataPath is <root>/plugin/data, so this group resolves to <root>/outside.
    final response = await harness.clear('../../outside');

    _expectRejected(response, 'group');
    expect(await keep.exists(), isTrue);
    expect(await outside.exists(), isTrue);
  });

  test(
    'get, set, and delete cannot touch a file outside the data path',
    () async {
      final outside = File('${harness.root.path}/escape.json');
      await outside.writeAsString(jsonEncode('untouched'));

      // <data>/group/../../../escape.json resolves to <root>/escape.json.
      const key = '../../../escape';
      _expectRejected(await harness.set('group', key, 'written'), 'key');
      _expectRejected(await harness.get('group', key), 'key');
      _expectRejected(await harness.delete('group', key), 'key');

      expect(await outside.readAsString(), jsonEncode('untouched'));
      expect(await Directory('${harness.dataPath}/group').exists(), isFalse);
    },
  );

  test(
    'single-segment names with dots, dashes, and underscores work',
    () async {
      const group = 'my_group-1.2';
      const key = 'state.v2-final_1';
      const value = {'counter': 3, 'label': 'ok'};

      final setResponse = await harness.set(group, key, value);
      expect(
        setResponse['type'],
        SdkCommands.responseOk,
        reason: '$setResponse',
      );

      final file = File('${harness.dataPath}/$group/$key.json');
      expect(await file.exists(), isTrue);
      expect(jsonDecode(await file.readAsString()), value);

      final getResponse = await harness.get(group, key);
      expect(
        getResponse['type'],
        SdkCommands.responseOk,
        reason: '$getResponse',
      );
      expect(getResponse['payload'], {'data': value});

      final groups = await harness.listGroups();
      expect(groups['type'], SdkCommands.responseOk, reason: '$groups');
      expect(groups['payload']['data'], contains(group));

      final keys = await harness.listKeys(group);
      expect(keys['type'], SdkCommands.responseOk, reason: '$keys');
      expect(keys['payload']['data'], contains(key));

      final deleteResponse = await harness.delete(group, key);
      expect(
        deleteResponse['type'],
        SdkCommands.responseOk,
        reason: '$deleteResponse',
      );
      expect(deleteResponse['payload'], {'data': true});
      expect(await file.exists(), isFalse);

      final missing = await harness.get(group, key);
      expect(missing['payload'], {'data': null});
    },
  );

  test('clear removes only the addressed group', () async {
    await harness.set('keep', 'k', 1);
    await harness.set('drop', 'k', 1);

    final response = await harness.clear('drop');

    expect(response['type'], SdkCommands.responseOk, reason: '$response');
    expect(await Directory('${harness.dataPath}/drop').exists(), isFalse);
    expect(await File('${harness.dataPath}/keep/k.json').exists(), isTrue);
  });

  test(
    'list_groups reports only directories directly under the data path',
    () async {
      await harness.set('alpha', 'k', 1);
      await harness.set('beta.v1', 'k', 1);
      await File('${harness.dataPath}/stray.json').writeAsString('{}');

      final groups = await harness.listGroups();

      expect(groups['type'], SdkCommands.responseOk, reason: '$groups');
      expect(groups['payload']['data'], containsAll(['alpha', 'beta.v1']));
      expect(groups['payload']['data'], isNot(contains('stray.json')));
    },
  );
}
