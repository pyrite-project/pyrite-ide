import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pyrite_ide/core/sdk/permission_log.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/sdk/plugin_transport.dart';
import 'package:pyrite_ide/core/sdk/python_bridge_plugin_transport.dart';
import 'package:pyrite_ide/core/sdk/python_runtime_boot.dart';
import 'package:pyrite_ide/core/sdk/types.dart';
import 'package:serious_python/serious_python.dart';

enum PluginSessionState { starting, ready, stopping, stopped, failed }

class PluginStartCancelledException implements Exception {
  const PluginStartCancelledException(this.pluginId);

  final String pluginId;

  @override
  String toString() => 'Plugin start cancelled: $pluginId';
}

class PluginSession {
  PluginSession({
    required this.plugin,
    required this.sessionId,
    required this.generation,
    required this.transport,
    required this.manager,
    required this.pluginDirectory,
    required this.dataDirectory,
    required this.cacheDirectory,
    required this.tempDirectory,
    required this.startedAt,
    required this.runOnce,
    required FutureOr<void> Function() onStopped,
  }) : _onStopped = onStopped;

  final Plugin plugin;
  String get pluginId => plugin.id;
  final String sessionId;
  final int generation;
  final PluginLaunchTransport transport;
  final PluginRunManager manager;
  final Directory pluginDirectory;
  final Directory dataDirectory;
  final Directory cacheDirectory;
  final Directory tempDirectory;
  final DateTime startedAt;
  final bool runOnce;
  final FutureOr<void> Function() _onStopped;

  PluginSessionState _state = PluginSessionState.starting;
  PluginSessionState get state => _state;

  Future<String?>? _programCompletion;
  Future<String?>? get programCompletion => _programCompletion;
  bool _programExited = false;
  bool get programExited => _programExited;
  bool _stoppedCallbackInvoked = false;
  Future<void>? _stopFuture;
}

typedef PythonRuntimeBootstrap = Future<void> Function();
typedef PythonRuntimeReset = Future<void> Function();
typedef PluginSupportDirectory = Future<Directory> Function();
typedef PluginLaunchTransportFactory =
    PluginLaunchTransport Function({
      required String pluginId,
      required String sessionId,
      required bool runOnce,
    });
typedef PythonPluginProgramRunner =
    Future<String?> Function(
      String appPath, {
      required List<String> modulePaths,
      required Map<String, String> environmentVariables,
      required bool sync,
    });

class PythonRuntimeHost {
  PythonRuntimeHost({
    PythonRuntimeBootstrap? bootstrapRuntime,
    PythonRuntimeReset? resetRuntime,
    PluginSupportDirectory? supportDirectory,
    PluginLaunchTransportFactory? transportFactory,
    PythonPluginProgramRunner? runProgram,
    String Function()? sessionIdFactory,
    DateTime Function()? clock,
    this.stopTimeout = const Duration(seconds: 2),
  }) : _bootstrapRuntime = bootstrapRuntime ?? _defaultBootstrapRuntime,
       _resetRuntime = resetRuntime ?? SeriousPython.resetRuntime,
       _supportDirectory =
           supportDirectory ?? (() => getApplicationSupportDirectory()),
       _transportFactory = transportFactory ?? _defaultTransportFactory,
       _runProgram = runProgram ?? _defaultRunProgram,
       _sessionIdFactory = sessionIdFactory ?? _newSessionId,
       _clock = clock ?? DateTime.now;

  static const Set<String> hostCapabilities = {'sdk.v1'};

  final PythonRuntimeBootstrap _bootstrapRuntime;
  final PythonRuntimeReset _resetRuntime;
  final PluginSupportDirectory _supportDirectory;
  final PluginLaunchTransportFactory _transportFactory;
  final PythonPluginProgramRunner _runProgram;
  final String Function() _sessionIdFactory;
  final DateTime Function() _clock;
  final Duration stopTimeout;

  final Map<String, PluginSession> _sessions = {};
  final Map<String, Future<PluginSession>> _starting = {};
  final Map<String, _PluginStartControl> _startControls = {};
  Future<void> _startupQueue = Future<void>.value();
  Future<void>? _runtimeStartFuture;
  Future<void>? _restartFuture;
  int _generation = 0;

  Map<String, PluginSession> get sessions => Map.unmodifiable(_sessions);
  int get generation => _generation;

  Future<void> start() async {
    final active = _runtimeStartFuture;
    if (active != null) return active;
    final future = _bootstrapRuntime();
    _runtimeStartFuture = future;
    try {
      await future;
    } catch (_) {
      if (identical(_runtimeStartFuture, future)) {
        _runtimeStartFuture = null;
      }
      rethrow;
    }
  }

  Future<PluginSession> startPlugin(
    Plugin plugin, {
    required void Function(PluginRunManager manager) configureManager,
    PermissionLogService? permissionLog,
    void Function(String message)? onOutput,
    FutureOr<void> Function()? onStopped,
    bool runOnce = false,
  }) async {
    while (true) {
      final restart = _restartFuture;
      if (restart == null) break;
      await restart;
    }

    final pending = _starting[plugin.id];
    if (pending != null) return pending;
    final active = _sessions[plugin.id];
    if (active != null) {
      if (active.state == PluginSessionState.failed ||
          active.state == PluginSessionState.stopping) {
        await _stopSession(
          active,
          sendDispose: active.state == PluginSessionState.stopping,
          finalState: PluginSessionState.stopped,
        );
        if (!active.programExited) {
          throw StateError(
            'Plugin ${plugin.id} still has a live Python target; '
            'restart the Python runtime before starting it again',
          );
        }
      } else if (active.state != PluginSessionState.stopped) {
        return active;
      }
      if (identical(_sessions[plugin.id], active)) {
        _sessions.remove(plugin.id);
      }
    }

    final control = _PluginStartControl();
    _startControls[plugin.id] = control;
    final future = _withStartupLock(
      () => _startPluginNow(
        plugin,
        control: control,
        configureManager: configureManager,
        permissionLog: permissionLog,
        onOutput: onOutput,
        onStopped: onStopped ?? () {},
        runOnce: runOnce,
      ),
    );
    _starting[plugin.id] = future;
    unawaited(
      future.then<void>(
        (_) => _finishStart(plugin.id, future, control),
        onError: (Object _, StackTrace _) {
          _finishStart(plugin.id, future, control);
        },
      ),
    );
    return future;
  }

  Future<void> runPluginOnce(
    Plugin plugin, {
    required void Function(PluginRunManager manager) configureManager,
    PermissionLogService? permissionLog,
    void Function(String message)? onOutput,
    FutureOr<void> Function()? onStopped,
  }) async {
    final session = await startPlugin(
      plugin,
      configureManager: configureManager,
      permissionLog: permissionLog,
      onOutput: onOutput,
      onStopped: onStopped,
      runOnce: true,
    );
    try {
      final result = await session.programCompletion;
      if (result != null) throw StateError(result);
    } finally {
      await _stopSession(session, sendDispose: false);
    }
  }

  Future<PluginSession> restartPlugin(
    Plugin plugin, {
    required void Function(PluginRunManager manager) configureManager,
    PermissionLogService? permissionLog,
    void Function(String message)? onOutput,
    FutureOr<void> Function()? onStopped,
  }) async {
    await stopPlugin(plugin.id);
    return startPlugin(
      plugin,
      configureManager: configureManager,
      permissionLog: permissionLog,
      onOutput: onOutput,
      onStopped: onStopped,
    );
  }

  Future<void> stopPlugin(String pluginId) async {
    _startControls[pluginId]?.cancelled = true;
    final current = _sessions[pluginId];
    if (current != null) await _stopSession(current);

    final pending = _starting[pluginId];
    if (pending == null) return;
    try {
      final session = await pending;
      await _stopSession(session);
    } on PluginStartCancelledException {
      // Cancellation is the requested result.
    } catch (_) {
      // Failed starts clean up their own session and transport.
    }
  }

  Future<void> stopAll() async {
    for (final control in _startControls.values) {
      control.cancelled = true;
    }
    await Future.wait(
      _sessions.values.toList(growable: false).map(_stopSession),
    );
    final pending = _starting.values.toList(growable: false);
    if (pending.isNotEmpty) {
      await Future.wait(
        pending.map((future) async {
          try {
            await future;
          } catch (_) {}
        }),
      );
    }
  }

  Future<void> restartRuntime() {
    final active = _restartFuture;
    if (active != null) return active;
    final future = _restartRuntimeNow();
    _restartFuture = future;
    return future.whenComplete(() {
      if (identical(_restartFuture, future)) _restartFuture = null;
    });
  }

  Future<void> _restartRuntimeNow() async {
    await stopAll();
    final unresolved = _sessions.values
        .where((session) => !session.programExited)
        .toList(growable: false);
    for (final session in unresolved) {
      session._state = PluginSessionState.stopped;
      session._programExited = true;
      if (identical(_sessions[session.pluginId], session)) {
        _sessions.remove(session.pluginId);
      }
      try {
        if (await session.tempDirectory.exists()) {
          await session.tempDirectory.delete(recursive: true);
        }
      } catch (_) {}
    }
    await _withStartupLock(() async {
      await _resetRuntime();
      _generation++;
    });
  }

  Future<PluginSession> _startPluginNow(
    Plugin plugin, {
    required _PluginStartControl control,
    required void Function(PluginRunManager manager) configureManager,
    required PermissionLogService? permissionLog,
    required void Function(String message)? onOutput,
    required FutureOr<void> Function() onStopped,
    required bool runOnce,
  }) async {
    PluginSession? session;
    try {
      _throwIfCancelled(plugin.id, control);
      await start();
      _throwIfCancelled(plugin.id, control);

      final support = await _supportDirectory();
      final pluginRoot = path.normalize(
        path.absolute(path.join(support.path, 'plugin')),
      );
      final pluginPath = path.normalize(
        path.absolute(path.join(pluginRoot, plugin.id)),
      );
      if (plugin.id.isEmpty ||
          path.isAbsolute(plugin.id) ||
          !path.equals(path.dirname(pluginPath), pluginRoot)) {
        throw FormatException('Invalid plugin ID: ${plugin.id}');
      }

      final pluginDirectory = Directory(pluginPath);
      if (!await pluginDirectory.exists()) {
        throw StateError('Plugin directory does not exist: $pluginPath');
      }
      final entryPoint = File(path.join(pluginPath, '__main__.py'));
      if (!await entryPoint.exists()) {
        throw StateError(
          'Plugin entry point does not exist: ${entryPoint.path}',
        );
      }
      final dataDirectory = await Directory(
        path.join(pluginPath, 'data'),
      ).create(recursive: true);
      final cacheDirectory = await Directory(
        path.join(pluginPath, 'cache'),
      ).create(recursive: true);
      _throwIfCancelled(plugin.id, control);

      final sessionId = _sessionIdFactory();
      final generation = ++_generation;
      final tempDirectory = await Directory(
        path.join(cacheDirectory.path, 'sessions', sessionId, 'tmp'),
      ).create(recursive: true);
      final transport = _transportFactory(
        pluginId: plugin.id,
        sessionId: sessionId,
        runOnce: runOnce,
      );
      final manager = PluginRunManager(
        transport: transport,
        assetsPath: pluginDirectory.absolute.path,
        dataPath: dataDirectory.absolute.path,
        cachePath: cacheDirectory.absolute.path,
        tempPath: tempDirectory.absolute.path,
        pluginId: plugin.id,
        pluginType: plugin.type.name,
        pluginPermissions: plugin.permissions,
        permissionLog: permissionLog,
        onOutput: onOutput,
        sessionId: sessionId,
        generation: generation,
      );
      configureManager(manager);
      session = PluginSession(
        plugin: plugin,
        sessionId: sessionId,
        generation: generation,
        transport: transport,
        manager: manager,
        pluginDirectory: pluginDirectory.absolute,
        dataDirectory: dataDirectory.absolute,
        cacheDirectory: cacheDirectory.absolute,
        tempDirectory: tempDirectory.absolute,
        startedAt: _clock(),
        runOnce: runOnce,
        onStopped: onStopped,
      );
      _sessions[plugin.id] = session;

      await transport.start();
      _throwIfCancelled(plugin.id, control);
      final capabilities = hostCapabilities.toList()..sort();
      final programCompletion = _runProgram(
        entryPoint.absolute.path,
        modulePaths: [
          path.join(pluginPath, '__pypackages__'),
          path.join(pluginPath, 'site-packages'),
          pluginPath,
        ].map(path.absolute).toList(growable: false),
        environmentVariables: {
          ...transport.startupEnvironment,
          'PYRITE_IDE_PLUGIN_ID': plugin.id,
          'PYRITE_IDE_PLUGIN_SESSION_ID': sessionId,
          'PYRITE_IDE_PLUGIN_GENERATION': '$generation',
          'PYRITE_IDE_PLUGIN_DIR': pluginDirectory.absolute.path,
          'PYRITE_IDE_PLUGIN_DATA_DIR': dataDirectory.absolute.path,
          'PYRITE_IDE_PLUGIN_CACHE_DIR': cacheDirectory.absolute.path,
          'PYRITE_IDE_PLUGIN_TEMP_DIR': tempDirectory.absolute.path,
          'PYRITE_IDE_PLUGIN_CAPABILITIES': jsonEncode(capabilities),
          'PYTHONUNBUFFERED': '1',
        },
        sync: true,
      );
      session._programCompletion = programCompletion;
      _observeProgram(session, programCompletion, onOutput);
      _throwIfCancelled(plugin.id, control);

      await manager.connect(transportAlreadyStarted: true);
      await manager.sendLifecycleHook(
        LifecycleHook.start.value,
        connectIfNeeded: false,
        waitForReply: true,
      );
      _throwIfCancelled(plugin.id, control);
      if (session.state == PluginSessionState.failed) {
        throw StateError('Plugin exited during startup: ${plugin.id}');
      }
      session._state = PluginSessionState.ready;
      return session;
    } catch (error, stackTrace) {
      if (session != null) {
        session._state = PluginSessionState.failed;
        await _stopSession(
          session,
          sendDispose: true,
          finalState: PluginSessionState.failed,
        );
      }
      if (control.cancelled && error is! PluginStartCancelledException) {
        Error.throwWithStackTrace(
          PluginStartCancelledException(plugin.id),
          stackTrace,
        );
      }
      rethrow;
    }
  }

  void _observeProgram(
    PluginSession session,
    Future<String?> completion,
    void Function(String message)? onOutput,
  ) {
    unawaited(
      completion.then<void>(
        (error) {
          session._programExited = true;
          if (!session.runOnce &&
              session.state != PluginSessionState.stopping &&
              session.state != PluginSessionState.stopped) {
            session._state = PluginSessionState.failed;
            onOutput?.call(
              error == null
                  ? '[${session.pluginId}] Python exited unexpectedly'
                  : '[${session.pluginId}] Python exited: $error',
            );
            unawaited(
              _stopSession(
                session,
                sendDispose: false,
                finalState: PluginSessionState.failed,
              ),
            );
          }
        },
        onError: (Object error, StackTrace _) {
          session._programExited = true;
          if (session.state != PluginSessionState.stopping &&
              session.state != PluginSessionState.stopped) {
            session._state = PluginSessionState.failed;
            onOutput?.call(
              '[${session.pluginId}] Python execution failed: $error',
            );
            unawaited(
              _stopSession(
                session,
                sendDispose: false,
                finalState: PluginSessionState.failed,
              ),
            );
          }
        },
      ),
    );
  }

  Future<void> _stopSession(
    PluginSession session, {
    bool sendDispose = true,
    PluginSessionState finalState = PluginSessionState.stopped,
  }) {
    final active = session._stopFuture;
    if (active != null) return active;
    final future = _stopSessionNow(
      session,
      sendDispose: sendDispose,
      finalState: finalState,
    );
    session._stopFuture = future;
    return future;
  }

  Future<void> _stopSessionNow(
    PluginSession session, {
    required bool sendDispose,
    required PluginSessionState finalState,
  }) async {
    if (session.state != PluginSessionState.failed) {
      session._state = PluginSessionState.stopping;
    }
    if (sendDispose) {
      try {
        await session.manager
            .sendLifecycleHook(
              LifecycleHook.dispose.value,
              connectIfNeeded: false,
              waitForReply: true,
            )
            .timeout(stopTimeout);
      } catch (_) {}
    }
    final completion = session.programCompletion;
    var programExited = completion == null || session._programExited;
    if (completion != null) {
      try {
        await completion.timeout(stopTimeout);
        programExited = true;
      } on TimeoutException {
        // Keep the session tracked until the daemon target really exits.
      } catch (_) {
        programExited = true;
      }
    }
    session._programExited = programExited;
    try {
      await session.manager.stop().timeout(stopTimeout);
    } catch (_) {
      await session.transport.close();
    }
    programExited = programExited || session._programExited;
    if (!session._stoppedCallbackInvoked) {
      session._stoppedCallbackInvoked = true;
      try {
        await session._onStopped();
      } catch (_) {}
    }
    if (programExited) {
      try {
        if (await session.tempDirectory.exists()) {
          await session.tempDirectory.delete(recursive: true);
        }
      } catch (_) {}
      session._state = finalState;
      if (identical(_sessions[session.pluginId], session)) {
        _sessions.remove(session.pluginId);
      }
    } else {
      session._state = PluginSessionState.failed;
      // A later completion callback may finish cleanup and remove it.
      session._stopFuture = null;
    }
  }

  void _throwIfCancelled(String pluginId, _PluginStartControl control) {
    if (control.cancelled) throw PluginStartCancelledException(pluginId);
  }

  void _finishStart(
    String pluginId,
    Future<PluginSession> future,
    _PluginStartControl control,
  ) {
    if (identical(_starting[pluginId], future)) _starting.remove(pluginId);
    if (identical(_startControls[pluginId], control)) {
      _startControls.remove(pluginId);
    }
  }

  Future<T> _withStartupLock<T>(Future<T> Function() action) {
    final next = _startupQueue.then((_) => action());
    _startupQueue = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return next;
  }

  static Future<void> _defaultBootstrapRuntime() async {
    final runtimeDirectory = await extractAssetZip(
      pythonRuntimeBootAsset,
      targetPath: pythonRuntimeBootCachePath,
      checkHash: true,
    );
    final error = await SeriousPython.runProgram(
      path.join(runtimeDirectory, 'boot.py'),
      sync: true,
    );
    if (error != null) throw StateError(error);
  }

  static PluginLaunchTransport _defaultTransportFactory({
    required String pluginId,
    required String sessionId,
    required bool runOnce,
  }) {
    final suffix = runOnce ? '.once' : '';
    return PythonBridgePluginTransport(
      channelLabel: 'pyrite.plugin.$pluginId.$sessionId$suffix',
    );
  }

  static Future<String?> _defaultRunProgram(
    String appPath, {
    required List<String> modulePaths,
    required Map<String, String> environmentVariables,
    required bool sync,
  }) {
    return SeriousPython.runProgram(
      appPath,
      modulePaths: modulePaths,
      environmentVariables: environmentVariables,
      sync: sync,
    );
  }

  static String _newSessionId() {
    final random = Random.secure();
    return List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }
}

class _PluginStartControl {
  bool cancelled = false;
}

final Provider<PythonRuntimeHost> pythonRuntimeHostProvider = Provider((ref) {
  final host = PythonRuntimeHost();
  ref.onDispose(() => unawaited(host.stopAll()));
  return host;
});
