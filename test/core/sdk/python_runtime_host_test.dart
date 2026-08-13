import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/sdk/plugin_transport.dart';
import 'package:pyrite_ide/core/sdk/protocol.dart';
import 'package:pyrite_ide/core/sdk/python_runtime_host.dart';
import 'package:pyrite_ide/core/sdk/types.dart';

class _FakeLaunchTransport implements PluginLaunchTransport {
  _FakeLaunchTransport({
    required this.pluginId,
    required this.sessionId,
    required this.runOnce,
    required this.programCompletion,
    this.initializeDelay = Duration.zero,
    this.onInitializeStarted,
    this.onInitializeFinished,
    this.failStart = false,
    this.completeOnDispose = true,
    this.lifecycleStartGate,
    this.lifecycleDisposeGate,
  });

  final String pluginId;
  final String sessionId;
  final bool runOnce;
  final Completer<String?> programCompletion;
  final Duration initializeDelay;
  final void Function()? onInitializeStarted;
  final void Function()? onInitializeFinished;
  final bool failStart;
  final bool completeOnDispose;
  final Completer<void>? lifecycleStartGate;
  final Completer<void>? lifecycleDisposeGate;
  final StreamController<Uint8List> _messages =
      StreamController<Uint8List>.broadcast();
  final StreamController<PluginTransportState> _states =
      StreamController<PluginTransportState>.broadcast();
  int _sequence = 0;
  bool closed = false;
  int startCalls = 0;

  @override
  String get type => 'FakeLaunch';

  @override
  Map<String, String> get startupEnvironment => {'FAKE_PORT': sessionId};

  @override
  Stream<Uint8List> get messages => _messages.stream;

  @override
  Stream<PluginTransportState> get states => _states.stream;

  @override
  Future<void> start() async {
    startCalls++;
    if (failStart) throw StateError('transport start failed');
    if (closed) throw StateError('transport is closed');
    _states.add(PluginTransportState.connecting);
    _states.add(PluginTransportState.ready);
  }

  @override
  Future<void> send(Uint8List message) async {
    final envelope = jsonDecode(utf8.decode(message)) as Map<String, dynamic>;
    switch (envelope['type']) {
      case IdeCommands.initialize:
        onInitializeStarted?.call();
        if (initializeDelay > Duration.zero) {
          await Future<void>.delayed(initializeDelay);
        }
        _emit(
          makeEnvelope(
            type: SdkCommands.initialize,
            pluginId: pluginId,
            sessionId: sessionId,
            generation: envelope['generation'] as int,
            sequence: ++_sequence,
            replyTo: envelope['requestId'] as String,
            payload: {
              'protocolVersion': 1,
              'sdkVersion': 'runtime-host-test',
              'capabilities': ['sdk.v1'],
            },
          ),
        );
        onInitializeFinished?.call();
      case IdeCommands.initialized:
        _emit(
          makeEnvelope(
            type: SdkCommands.ready,
            pluginId: pluginId,
            sessionId: sessionId,
            generation: envelope['generation'] as int,
            sequence: ++_sequence,
            replyTo: envelope['requestId'] as String,
            payload: {
              'capabilities': ['sdk.v1'],
            },
          ),
        );
      case IdeCommands.lifecycleHook:
        final payload = envelope['payload'] as Map<String, dynamic>;
        final hook = payload['hook'];
        if (hook == LifecycleHook.start.value) {
          await lifecycleStartGate?.future;
        } else if (hook == LifecycleHook.dispose.value) {
          await lifecycleDisposeGate?.future;
        }
        _emit(
          makeEnvelope(
            type: SdkCommands.responseOk,
            pluginId: pluginId,
            sessionId: sessionId,
            generation: envelope['generation'] as int,
            sequence: ++_sequence,
            replyTo: envelope['requestId'] as String,
            payload: {'data': null},
          ),
        );
        if (((completeOnDispose && hook == LifecycleHook.dispose.value) ||
                (runOnce && hook == LifecycleHook.start.value)) &&
            !programCompletion.isCompleted) {
          programCompletion.complete(null);
        }
    }
  }

  void _emit(Map<String, dynamic> envelope) {
    if (closed) return;
    _messages.add(Uint8List.fromList(utf8.encode(jsonEncode(envelope))));
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    _states.add(PluginTransportState.closing);
    _states.add(PluginTransportState.closed);
    await _messages.close();
    await _states.close();
  }
}

class _RuntimeFixture {
  _RuntimeFixture(this.root);

  final Directory root;
  final Map<String, _FakeLaunchTransport> transports = {};
  final Map<String, Completer<String?>> completions = {};
  final List<String> programStarts = [];
  final List<Map<String, String>> environments = [];
  int bootstrapCalls = 0;
  int resetCalls = 0;
  final List<Completer<void>> resetGates = [];
  int sessionSequence = 0;
  int activeInitializations = 0;
  int maxActiveInitializations = 0;
  Duration initializeDelay = Duration.zero;
  String? failTransportFor;
  bool completeOnDispose = true;
  Completer<void>? lifecycleStartGate;
  Completer<void>? lifecycleDisposeGate;

  Future<void> createPlugins(Iterable<String> ids) async {
    for (final id in ids) {
      final directory = await Directory(
        path.join(root.path, 'plugin', id),
      ).create(recursive: true);
      await File(path.join(directory.path, '__main__.py')).writeAsString('#');
    }
  }

  PythonRuntimeHost createHost({PluginSupportDirectory? supportDirectory}) {
    return PythonRuntimeHost(
      bootstrapRuntime: () async => bootstrapCalls++,
      resetRuntime: () async {
        resetCalls++;
        if (resetGates.isNotEmpty) {
          await resetGates.removeAt(0).future;
        }
      },
      supportDirectory: supportDirectory ?? () async => root,
      sessionIdFactory: () => 'session-${++sessionSequence}',
      stopTimeout: const Duration(milliseconds: 100),
      transportFactory:
          ({required pluginId, required sessionId, required runOnce}) {
            final completion = Completer<String?>();
            completions[pluginId] = completion;
            final transport = _FakeLaunchTransport(
              pluginId: pluginId,
              sessionId: sessionId,
              runOnce: runOnce,
              programCompletion: completion,
              initializeDelay: initializeDelay,
              failStart: failTransportFor == pluginId,
              completeOnDispose: completeOnDispose,
              lifecycleStartGate: lifecycleStartGate,
              lifecycleDisposeGate: lifecycleDisposeGate,
              onInitializeStarted: () {
                activeInitializations++;
                if (activeInitializations > maxActiveInitializations) {
                  maxActiveInitializations = activeInitializations;
                }
              },
              onInitializeFinished: () => activeInitializations--,
            );
            transports[pluginId] = transport;
            return transport;
          },
      runProgram:
          (
            appPath, {
            required modulePaths,
            required environmentVariables,
            required sync,
          }) {
            final pluginId = environmentVariables['PYRITE_IDE_PLUGIN_ID']!;
            programStarts.add(pluginId);
            environments.add(Map<String, String>.from(environmentVariables));
            expect(sync, isTrue);
            expect(path.isAbsolute(appPath), isTrue);
            expect(modulePaths.every(path.isAbsolute), isTrue);
            return completions[pluginId]!.future;
          },
    );
  }
}

const _permissions = {
  'ui': ['view'],
};

Plugin _plugin(String id, {PluginType type = PluginType.ui}) => Plugin(
  id: id,
  name: id,
  type: type,
  status: PluginStatus.usable,
  permissions: _permissions,
);

Future<void> _pumpUntil(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 1));
  while (!predicate() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await pumpEventQueue();
  }
}

void main() {
  late Directory root;
  late String originalDirectory;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('pyrite-runtime-host-');
    originalDirectory = Directory.current.path;
  });

  tearDown(() async {
    Directory.current = originalDirectory;
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'five plugin initializations are serialized with isolated contexts',
    () async {
      final fixture = _RuntimeFixture(root)
        ..initializeDelay = const Duration(milliseconds: 5);
      final ids = List.generate(5, (index) => 'plugin-$index');
      await fixture.createPlugins(ids);
      final host = fixture.createHost();
      Directory.current = root.path;
      final workingDirectory = Directory.current.path;

      final sessions = await Future.wait(
        ids.map(
          (id) => host.startPlugin(_plugin(id), configureManager: (_) {}),
        ),
      );

      expect(fixture.bootstrapCalls, 1);
      expect(fixture.programStarts, ids);
      expect(fixture.maxActiveInitializations, 1);
      expect(Directory.current.path, workingDirectory);
      expect(
        sessions.map((session) => session.state),
        everyElement(PluginSessionState.ready),
      );
      for (var index = 0; index < ids.length; index++) {
        final environment = fixture.environments[index];
        final session = sessions[index];
        expect(environment['PYRITE_IDE_PLUGIN_ID'], ids[index]);
        expect(environment['PYRITE_IDE_PLUGIN_SESSION_ID'], session.sessionId);
        expect(
          environment['PYRITE_IDE_PLUGIN_GENERATION'],
          '${session.generation}',
        );
        expect(
          environment['PYRITE_IDE_PLUGIN_DIR'],
          session.pluginDirectory.path,
        );
        expect(
          environment['PYRITE_IDE_PLUGIN_DATA_DIR'],
          session.dataDirectory.path,
        );
        expect(
          environment['PYRITE_IDE_PLUGIN_CACHE_DIR'],
          session.cacheDirectory.path,
        );
        expect(
          environment['PYRITE_IDE_PLUGIN_TEMP_DIR'],
          session.tempDirectory.path,
        );
        expect(jsonDecode(environment['PYRITE_IDE_PLUGIN_CAPABILITIES']!), [
          'sdk.v1',
        ]);
      }

      await host.stopPlugin(ids[2]);
      expect(fixture.transports[ids[2]]!.closed, isTrue);
      expect(sessions[2].tempDirectory.existsSync(), isFalse);
      expect(sessions[0].tempDirectory.existsSync(), isTrue);
      expect(fixture.transports[ids[0]]!.closed, isFalse);
      expect(fixture.transports[ids[4]]!.closed, isFalse);
      await host.stopAll();
    },
  );

  test('pending replacement is launched with the original plugin ID', () async {
    const pluginId = 'replacement';
    final fixture = _RuntimeFixture(root);
    await fixture.createPlugins([pluginId]);
    final replacement = await Directory(
      path.join(root.path, 'plugin_updates', 'new', pluginId),
    ).create(recursive: true);
    final entryPoint = File(path.join(replacement.path, '__main__.py'));
    await entryPoint.writeAsString('# replacement');
    final marker = File(
      path.join(
        root.path,
        'plugin_updates',
        'pending_deletions',
        '$pluginId.json',
      ),
    );
    await marker.parent.create(recursive: true);
    await marker.writeAsString('{}');
    final host = fixture.createHost();

    final session = await host.startPlugin(
      _plugin(pluginId),
      configureManager: (_) {},
    );

    expect(session.pluginId, pluginId);
    expect(session.pluginDirectory.path, replacement.path);
    expect(
      fixture.environments.single['PYRITE_IDE_PLUGIN_DIR'],
      replacement.path,
    );
    await host.stopPlugin(pluginId);
  });

  test(
    'duplicate start returns one session and launches Python once',
    () async {
      final fixture = _RuntimeFixture(root);
      await fixture.createPlugins(['duplicate']);
      final host = fixture.createHost();

      final sessions = await Future.wait([
        host.startPlugin(_plugin('duplicate'), configureManager: (_) {}),
        host.startPlugin(_plugin('duplicate'), configureManager: (_) {}),
      ]);

      expect(identical(sessions[0], sessions[1]), isTrue);
      expect(fixture.programStarts, ['duplicate']);
      expect(fixture.transports['duplicate']!.startCalls, 1);
      await host.stopAll();
    },
  );

  test('startup cancellation prevents the program from launching', () async {
    final fixture = _RuntimeFixture(root);
    await fixture.createPlugins(['cancelled']);
    final directoryGate = Completer<Directory>();
    final host = fixture.createHost(
      supportDirectory: () => directoryGate.future,
    );

    final start = host.startPlugin(
      _plugin('cancelled'),
      configureManager: (_) {},
    );
    final stop = host.stopPlugin('cancelled');
    directoryGate.complete(root);

    await expectLater(start, throwsA(isA<PluginStartCancelledException>()));
    await stop;
    expect(fixture.programStarts, isEmpty);
    expect(host.sessions, isEmpty);
  });

  test(
    'failed startup cleans the transport and allows a later retry',
    () async {
      final fixture = _RuntimeFixture(root)..failTransportFor = 'retry';
      await fixture.createPlugins(['retry']);
      final host = fixture.createHost();

      await expectLater(
        host.startPlugin(_plugin('retry'), configureManager: (_) {}),
        throwsA(anyOf(isA<StateError>(), isA<PluginProtocolException>())),
      );
      expect(host.sessions, isEmpty);
      expect(fixture.transports['retry']!.closed, isTrue);

      fixture.failTransportFor = null;
      final session = await host.startPlugin(
        _plugin('retry'),
        configureManager: (_) {},
      );
      expect(session.state, PluginSessionState.ready);
      await host.stopAll();
    },
  );

  test('runtime restart stops sessions and advances generation', () async {
    final fixture = _RuntimeFixture(root);
    await fixture.createPlugins(['restart']);
    final host = fixture.createHost();
    final first = await host.startPlugin(
      _plugin('restart'),
      configureManager: (_) {},
    );

    await host.restartRuntime();

    expect(fixture.resetCalls, 1);
    expect(host.sessions, isEmpty);
    expect(fixture.transports['restart']!.closed, isTrue);
    final second = await host.startPlugin(
      _plugin('restart'),
      configureManager: (_) {},
    );
    expect(second.generation, greaterThan(first.generation));
    expect(second.sessionId, isNot(first.sessionId));
    await host.stopAll();
  });

  test('plugin start waits across chained runtime restarts', () async {
    final firstReset = Completer<void>();
    final secondReset = Completer<void>();
    final fixture = _RuntimeFixture(root)
      ..resetGates.addAll([firstReset, secondReset]);
    await fixture.createPlugins(['restart-chain']);
    final host = fixture.createHost();

    final firstRestart = host.restartRuntime();
    final secondRestart = firstRestart.then((_) => host.restartRuntime());
    final start = host.startPlugin(
      _plugin('restart-chain'),
      configureManager: (_) {},
    );

    await _pumpUntil(() => fixture.resetCalls == 1);
    firstReset.complete();
    await _pumpUntil(() => fixture.resetCalls == 2);
    expect(fixture.programStarts, isEmpty);

    secondReset.complete();
    await secondRestart;
    final session = await start;
    expect(session.state, PluginSessionState.ready);
    expect(fixture.resetCalls, 2);
    await host.stopAll();
  });

  test('runtime reset recovers an unresolved Python target', () async {
    final fixture = _RuntimeFixture(root)..completeOnDispose = false;
    await fixture.createPlugins(['stuck']);
    final host = fixture.createHost();
    await host.startPlugin(_plugin('stuck'), configureManager: (_) {});

    await host.restartRuntime();

    expect(fixture.resetCalls, 1);
    expect(host.sessions, isEmpty);
    fixture.completions['stuck']!.complete(null);
  });

  test('a failed session with a live target rejects duplicate start', () async {
    final fixture = _RuntimeFixture(root)..completeOnDispose = false;
    await fixture.createPlugins(['live-failure']);
    final host = fixture.createHost();
    final first = await host.startPlugin(
      _plugin('live-failure'),
      configureManager: (_) {},
    );

    await host.stopPlugin('live-failure');
    expect(first.state, PluginSessionState.failed);
    expect(first.programExited, isFalse);
    await expectLater(
      host.startPlugin(_plugin('live-failure'), configureManager: (_) {}),
      throwsStateError,
    );
    expect(fixture.programStarts, ['live-failure']);

    fixture.completions['live-failure']!.complete(null);
    await _pumpUntil(() => host.sessions.isEmpty);
    expect(host.sessions, isEmpty);
  });

  test('start and dispose wait for lifecycle hook replies', () async {
    final fixture = _RuntimeFixture(root)
      ..lifecycleStartGate = Completer<void>()
      ..lifecycleDisposeGate = Completer<void>();
    await fixture.createPlugins(['lifecycle-gates']);
    final host = fixture.createHost();

    final start = host.startPlugin(
      _plugin('lifecycle-gates'),
      configureManager: (_) {},
    );
    var startCompleted = false;
    unawaited(start.then<void>((_) => startCompleted = true));
    await pumpEventQueue();
    expect(startCompleted, isFalse);
    fixture.lifecycleStartGate!.complete();
    final session = await start;
    expect(session.state, PluginSessionState.ready);

    final stop = host.stopPlugin('lifecycle-gates');
    var stopCompleted = false;
    unawaited(stop.then<void>((_) => stopCompleted = true));
    await pumpEventQueue();
    expect(stopCompleted, isFalse);
    expect(fixture.transports['lifecycle-gates']!.closed, isFalse);
    fixture.lifecycleDisposeGate!.complete();
    await stop;
    expect(fixture.transports['lifecycle-gates']!.closed, isTrue);
  });

  test('unexpected program exit removes the failed session', () async {
    final fixture = _RuntimeFixture(root);
    await fixture.createPlugins(['exited']);
    final host = fixture.createHost();
    await host.startPlugin(_plugin('exited'), configureManager: (_) {});

    fixture.completions['exited']!.complete(null);
    await _pumpUntil(() => host.sessions.isEmpty);

    expect(host.sessions, isEmpty);
    expect(fixture.transports['exited']!.closed, isTrue);
  });

  test('run-once waits for completion and removes the session', () async {
    final fixture = _RuntimeFixture(root);
    await fixture.createPlugins(['data']);
    final host = fixture.createHost();
    var stopped = 0;

    await host.runPluginOnce(
      _plugin('data', type: PluginType.data),
      configureManager: (_) {},
      onStopped: () => stopped++,
    );

    expect(host.sessions, isEmpty);
    expect(fixture.transports['data']!.closed, isTrue);
    expect(stopped, 1);
  });
}
