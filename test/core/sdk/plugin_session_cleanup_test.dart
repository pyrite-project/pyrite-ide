import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/sdk/api/editor.dart';
import 'package:pyrite_ide/core/sdk/editor_key_capture.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_transport.dart';
import 'package:pyrite_ide/core/sdk/python_runtime_host.dart';
import 'package:pyrite_ide/core/sdk/types.dart';
import 'package:pyrite_ide/core/sdk/view_model_store.dart';
import 'package:pyrite_ide/core/sdk/view_route_stack.dart';

const _pluginId = 'cleanup-plugin';
const _viewId = 'cleanup-plugin.main';

const _plugin = Plugin(
  id: _pluginId,
  name: 'Cleanup Plugin',
  version: '1.0.0',
  type: PluginType.service,
  status: PluginStatus.usable,
  declaredPermissions: {
    'editor': ['keys'],
  },
  permissions: {
    'editor': ['keys'],
  },
  platforms: ['linux'],
  manifest: PluginManifestV2(
    id: _pluginId,
    name: 'Cleanup Plugin',
    version: '1.0.0',
    type: PluginType.service,
    permissions: ['editor.keys'],
    platforms: ['linux'],
  ),
);

/// Transport that answers the protocol handshake and records every frame.
///
/// The plugin side never emits a capture request on its own in these tests:
/// the harness injects it, which is what the real SDK would do.
class _ScriptedTransport implements PluginLaunchTransport {
  _ScriptedTransport({required this.pluginId, required this.sessionId});

  final String pluginId;
  final String sessionId;
  final Completer<String?> programCompletion = Completer<String?>();
  final StreamController<Uint8List> _messages =
      StreamController<Uint8List>.broadcast();
  final StreamController<PluginTransportState> _states =
      StreamController<PluginTransportState>.broadcast();
  final List<Map<String, dynamic>> sent = <Map<String, dynamic>>[];
  bool _closed = false;

  @override
  String get type => 'Scripted';

  @override
  Map<String, String> get startupEnvironment => const {};

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
    final envelope = jsonDecode(utf8.decode(message)) as Map<String, dynamic>;
    sent.add(envelope);
    switch (envelope['type']) {
      case IdeCommands.initialize:
        _reply(SdkCommands.initialize, envelope, {
          'protocolVersion': 1,
          'sdkVersion': 'fixture',
          'capabilities': ['sdk.v1'],
        });
      case IdeCommands.initialized:
        _reply(SdkCommands.ready, envelope, {
          'capabilities': ['sdk.v1'],
        });
      case IdeCommands.lifecycleHook:
        _reply(SdkCommands.responseOk, envelope, {'data': null});
        final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
        if (payload['hook'] == LifecycleHook.dispose.value &&
            !programCompletion.isCompleted) {
          programCompletion.complete(null);
        }
    }
  }

  void _reply(
    String type,
    Map<String, dynamic> request,
    Map<String, dynamic> payload,
  ) {
    inject(
      makeEnvelope(
        type: type,
        pluginId: request['pluginId'] as String,
        sessionId: request['sessionId'] as String,
        generation: request['generation'] as int,
        replyTo: request['requestId'] as String,
        sequence: ++_sequence,
        payload: payload,
      ),
    );
  }

  void inject(Map<String, dynamic> envelope) {
    if (_closed) return;
    _messages.add(Uint8List.fromList(utf8.encode(jsonEncode(envelope))));
  }

  /// Simulates the plugin process dying without a graceful stop.
  void crash(String reason) {
    if (!programCompletion.isCompleted) programCompletion.complete(reason);
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

class _HostFixture {
  _HostFixture(this.root);

  final Directory root;
  final Map<String, _ScriptedTransport> transports = {};
  late final PythonRuntimeHost host;
  int _sessionSequence = 0;

  static Future<_HostFixture> create(Directory root) async {
    final directory = await Directory(
      path.join(root.path, 'plugin', _pluginId),
    ).create(recursive: true);
    await File(path.join(directory.path, '__main__.py')).writeAsString('#');
    final fixture = _HostFixture(root);
    fixture.host = PythonRuntimeHost(
      bootstrapRuntime: () async {},
      resetRuntime: () async {},
      supportDirectory: () async => root,
      sessionIdFactory: () => 'session-${++fixture._sessionSequence}',
      stopTimeout: const Duration(milliseconds: 200),
      transportFactory:
          ({required pluginId, required sessionId, required runOnce}) {
            final transport = _ScriptedTransport(
              pluginId: pluginId,
              sessionId: sessionId,
            );
            fixture.transports[pluginId] = transport;
            return transport;
          },
      runProgram:
          (
            appPath, {
            required modulePaths,
            required environmentVariables,
            required sync,
          }) {
            final id = environmentVariables['PYRITE_IDE_PLUGIN_ID']!;
            return fixture.transports[id]!.programCompletion.future;
          },
    );
    return fixture;
  }
}

int _sequence = 100;

Future<Map<String, dynamic>> _request(
  PluginRunManager manager,
  _ScriptedTransport transport,
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
  transport.inject(envelope);
  for (var i = 0; i < 200; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final match = transport.sent
        .where((item) => item['replyTo'] == envelope['requestId'])
        .firstOrNull;
    if (match != null) return match;
  }
  throw StateError('No response for $type');
}

Future<void> _pumpUntil(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!predicate() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await pumpEventQueue();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'captures and releases are scoped to the session that bound the API',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final transportA = _ScriptedTransport(
        pluginId: 'plugin-a',
        sessionId: 'session-a',
      );
      final transportB = _ScriptedTransport(
        pluginId: 'plugin-b',
        sessionId: 'session-b',
      );
      final managerA = PluginRunManager(
        transport: transportA,
        assetsPath: '.',
        pluginId: 'plugin-a',
        pluginPermissions: const {
          'editor': ['keys'],
        },
        sessionId: 'session-a',
      );
      final managerB = PluginRunManager(
        transport: transportB,
        assetsPath: '.',
        pluginId: 'plugin-b',
        pluginPermissions: const {
          'editor': ['keys'],
        },
        sessionId: 'session-b',
      );
      final editor = container.read(sdkEditorProvider);
      editor.bind(managerA);
      editor.bind(managerB);
      await managerA.connect();
      await managerB.connect();
      addTearDown(() async {
        await managerA.stop();
        await managerB.stop();
      });

      final registry = container.read(editorKeyCaptureProvider);

      await _request(
        managerA,
        transportA,
        SdkEditorCommands.captureKeys,
        payload: {
          'keys': ['tab'],
        },
      );
      await _request(
        managerB,
        transportB,
        SdkEditorCommands.captureKeys,
        payload: {
          'keys': ['escape'],
        },
      );

      expect(registry.ownerOf('tab')?.sessionId, 'session-a');
      expect(registry.ownerOf('escape')?.sessionId, 'session-b');

      // Releasing through plugin A must not touch plugin B's capture.
      await _request(managerA, transportA, SdkEditorCommands.releaseKeys);
      expect(registry.ownerOf('tab'), isNull);
      expect(registry.ownerOf('escape')?.sessionId, 'session-b');
    },
  );

  test(
    'stopping a plugin releases its session captures and route stacks',
    () async {
      final root = await Directory.systemTemp.createTemp('pyrite-cleanup-');
      addTearDown(() => root.delete(recursive: true));
      final fixture = await _HostFixture.create(root);
      final container = ProviderContainer(
        overrides: [
          pluginRunManagerProvider.overrideWith(
            (ref) => PluginRunManagerNotifier(ref, runtimeHost: fixture.host),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(pluginRunManagerProvider.notifier);
      await notifier.start(_plugin);
      final manager = container.read(pluginRunManagerProvider)[_plugin];
      expect(manager, isNotNull);

      final transport = fixture.transports[_pluginId]!;
      await _request(
        manager!,
        transport,
        SdkEditorCommands.captureKeys,
        payload: {
          'keys': ['tab'],
        },
      );
      final registry = container.read(editorKeyCaptureProvider);
      expect(registry.ownerOf('tab')?.sessionId, manager.sessionId);

      final instance = ViewInstanceId(
        pluginId: _pluginId,
        sessionId: manager.sessionId,
        viewId: _viewId,
        instanceId: 'main',
      );
      final stacks = container.read(viewRouteStacksProvider);
      stacks.push(instance, 'details');
      expect(stacks.length, 1);

      await notifier.stop(_plugin);

      await _pumpUntil(() => !registry.hasCaptures);
      expect(registry.hasCaptures, isFalse);
      expect(stacks.length, 0);
    },
  );

  test(
    'a crashed plugin releases its session captures and route stacks',
    () async {
      final root = await Directory.systemTemp.createTemp('pyrite-cleanup-');
      addTearDown(() => root.delete(recursive: true));
      final fixture = await _HostFixture.create(root);
      final container = ProviderContainer(
        overrides: [
          pluginRunManagerProvider.overrideWith(
            (ref) => PluginRunManagerNotifier(ref, runtimeHost: fixture.host),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(pluginRunManagerProvider.notifier);
      await notifier.start(_plugin);
      final manager = container.read(pluginRunManagerProvider)[_plugin]!;
      final transport = fixture.transports[_pluginId]!;

      final registry = container.read(editorKeyCaptureProvider);
      final stacks = container.read(viewRouteStacksProvider);
      await _request(
        manager,
        transport,
        SdkEditorCommands.captureKeys,
        payload: {
          'keys': ['tab'],
        },
      );
      final instance = ViewInstanceId(
        pluginId: _pluginId,
        sessionId: manager.sessionId,
        viewId: _viewId,
        instanceId: 'main',
      );
      stacks.push(instance, 'details');
      expect(registry.hasCaptures, isTrue);
      expect(stacks.length, 1);

      transport.crash('process exited');

      await _pumpUntil(() => !registry.hasCaptures && stacks.length == 0);
      expect(registry.hasCaptures, isFalse);
      expect(stacks.length, 0);
    },
  );

  test('restarting a plugin drops the stopped session route stack', () async {
    final root = await Directory.systemTemp.createTemp('pyrite-cleanup-');
    addTearDown(() => root.delete(recursive: true));
    final fixture = await _HostFixture.create(root);
    final container = ProviderContainer(
      overrides: [
        pluginRunManagerProvider.overrideWith(
          (ref) => PluginRunManagerNotifier(ref, runtimeHost: fixture.host),
        ),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(pluginRunManagerProvider.notifier);
    await notifier.start(_plugin);
    final first = container.read(pluginRunManagerProvider)[_plugin]!;
    final stacks = container.read(viewRouteStacksProvider);
    stacks.push(
      ViewInstanceId(
        pluginId: _pluginId,
        sessionId: first.sessionId,
        viewId: _viewId,
        instanceId: 'main',
      ),
      'details',
    );
    expect(stacks.length, 1);

    await notifier.restart(_plugin);

    final second = container.read(pluginRunManagerProvider)[_plugin]!;
    expect(second.sessionId, isNot(first.sessionId));
    stacks.push(
      ViewInstanceId(
        pluginId: _pluginId,
        sessionId: second.sessionId,
        viewId: _viewId,
        instanceId: 'main',
      ),
      'details',
    );
    expect(stacks.length, 1);

    await notifier.stop(_plugin);
  });
}
