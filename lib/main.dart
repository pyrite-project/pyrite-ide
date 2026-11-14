import 'dart:async';
import 'dart:io';

import 'package:code_forge/code_forge.dart' show RustLib;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:git2dart/git2dart.dart';
import 'package:pyrite_ide/app/app.dart';
import 'package:pyrite_ide/core/flutter/error_log_dedupe.dart';
import 'package:pyrite_ide/core/flutter/pyrite_widgets_binding.dart';
import 'package:pyrite_ide/core/sdk/environment_notifier_provider.dart';
import 'package:pyrite_ide/core/sdk/environment_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/python_runtime_host.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/editor/editor_split.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/board_backend.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/core/services/file/local_tree.dart';
import 'package:pyrite_ide/core/services/git/git_debug_log.dart';
import 'package:pyrite_ide/core/services/logging/app_log.dart';
import 'package:pyrite_ide/core/services/output/ide_output_log.dart';
import 'package:pyrite_ide/core/services/periodic_task/periodic_task.dart';
import 'package:pyrite_ide/core/services/persistence/persistence_manager.dart';
import 'package:pyrite_ide/core/services/persistence/persistence_models.dart';
import 'package:pyrite_ide/core/services/persistence/plugin_persistence.dart';
import 'package:pyrite_ide/core/services/serial/serial_provider.dart';
import 'package:pyrite_ide/features/function_page/console_tabs.dart';
import 'package:pyrite_ide/features/window.dart';
import 'package:video_player_media_kit/video_player_media_kit.dart';

String? getPythonPath() {
  if (Platform.isAndroid) return "assets/android/python.zip";
  if (Platform.isWindows) return "assets/windows/python.zip";
  if (Platform.isLinux) return "assets/linux/python.zip";
  if (Platform.isMacOS) return "assets/macos/python.zip";
  return null;
}

late final PersistenceManager persistenceManager;

/// Port the previous session was talking to.
///
/// Kept here rather than as a provider: nothing renders it, and the only use is
/// reconnecting once the serial layer is ready. Attempting that reconnect is
/// opt-in through the saved auto-reconnect switch, so a user who does not want
/// the IDE claiming a port on launch is not surprised by it.
String _lastActivePortPath = '';

/// Reopens the port the previous session used, once the app is running.
///
/// Deferred to a post-frame callback because the device-scoped caches it
/// clears (board tree, status panel) are provider-owned and must not be mutated
/// while the first frame is still being built.
Future<void> _resumeLastSerialPort() async {
  final path = _lastActivePortPath;
  if (path.isEmpty) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (container.read(serialProvider).isConnected) return;
    unawaited(container.read(serialProvider.notifier).connectPort(path));
  });
}

Timer? _saveTimer;
Timer? _debounceTimer;
Timer? _pluginSaveTimer;
bool _persistDirty = true;
bool _persistSaveInFlight = false;
final UseWindow appWindow = UseWindow();
DebugPrintCallback? _defaultDebugPrint;

void _appendIdeOutputLater(String text) {
  Future<void>.delayed(Duration.zero, () {
    container
        .read(ideOutputLogProvider.notifier)
        .add(IdeOutputSource.ide, text);
  });
}

/// Folds the same error when it is reported again and again, frame after frame.
///
/// Some framework failures (a semantics assertion, for instance) fire twice per
/// frame, so writing each stack trace turns the output panel into an unreadable
/// wall and hides every other message. The first report is kept verbatim and
/// the rest are tallied into a single line once the flood stops; nothing is
/// hidden, only repeated less often.
final ErrorLogDedupe _errorLogDedupe = ErrorLogDedupe(
  emitSummary: (text) {
    _appendIdeOutputLater(text);
    GitDebugLog.log(text);
  },
);

void _installIdeOutputLogger() {
  if (_defaultDebugPrint != null) return;
  _defaultDebugPrint = debugPrint;
  IdeOutputLogNotifier.setDebugMirror(_defaultDebugPrint);
  debugPrint = (String? message, {int? wrapWidth}) {
    final text = message ?? 'null';
    _appendIdeOutputLater(text);
    _defaultDebugPrint?.call(message, wrapWidth: wrapWidth);
  };

  FlutterError.onError = (FlutterErrorDetails details) {
    final message = details.exceptionAsString();
    // Matched on the message alone: the stack of a repeated framework error is
    // identical, and the message is what the tally line shows to the reader.
    if (!_errorLogDedupe.admit(signature: message)) return;
    final stack = details.stack?.toString();
    // Goes to the log file as well as the output panel: a framework error is
    // the most common "it broke and I have no idea why" report, and the panel
    // is gone after a restart.
    AppLog.e(
      'flutter',
      'uncaught FlutterError '
          'library=${details.library ?? '-'} '
          'context=${details.context?.toString() ?? '-'}',
      error: details.exception,
      stack: details.stack,
    );
    GitDebugLog.log(
      'FlutterError library=${details.library ?? ''} '
      'context=${details.context?.toString() ?? ''}',
      error: details.exception,
      stackTrace: details.stack,
    );
    _appendIdeOutputLater('$message${stack == null ? '' : '\n$stack'}');
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    // Frame-after-frame repeats of the same failure are tallied into one line
    // by the dedupe gate; the first report still reaches the log file.
    if (!_errorLogDedupe.admit(signature: 'uncaught|$error')) return true;
    AppLog.e(
      'uncaught',
      'unhandled async error type=${error.runtimeType}',
      error: error,
      stack: stack,
    );
    GitDebugLog.log(
      'PlatformDispatcher.onError',
      error: error,
      stackTrace: stack,
    );
    _appendIdeOutputLater('Unhandled exception: $error\n$stack');
    // Returning true marks the error handled so a single uncaught async
    // exception cannot terminate the whole IDE in release; the log and the
    // output panel above keep it diagnosable.
    return true;
  };
}

void _applyData(PersistedData data) {
  persistenceManager.applyTo(container, data);
  _lastActivePortPath = data.serialActivePortPath;
  // Reconnect last session's port only when the user asked for automatic
  // reconnection; claiming a port uninvited would also fight any other tool
  // the user has open on it.
  if (data.serialAutoReconnect && _lastActivePortPath.isNotEmpty) {
    unawaited(_resumeLastSerialPort());
  }
}

// Starts dirty so the first periodic tick persists the freshly restored
// state once, keeping a crash-recovery snapshot without steady-state writes.
Future<void> _savePersistedDataNow() async {
  if (_persistSaveInFlight) return;
  _persistSaveInFlight = true;
  try {
    await persistenceManager.saveFromContainer(container);
    _persistDirty = false;
  } finally {
    _persistSaveInFlight = false;
  }
}

void _triggerSave() {
  _persistDirty = true;
  _debounceTimer?.cancel();
  _debounceTimer = Timer(const Duration(seconds: 1), () {
    unawaited(_savePersistedDataNow());
  });
}

void _triggerPluginSave() {
  _pluginSaveTimer?.cancel();
  _pluginSaveTimer = Timer(const Duration(seconds: 1), () async {
    await container.read(pluginManagerProvider.notifier).persist();
  });
}

void _startAutoSave() {
  _saveTimer?.cancel();
  _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
    if (!_persistDirty) return;
    unawaited(_savePersistedDataNow());
  });
  container.read(tabbedViewControllerProvider.notifier).onUnsavedChange =
      _triggerSave;
  container
      .read(pluginManagerProvider.notifier)
      .setOnChanged(_triggerPluginSave);
  for (final provider in persistedSettingProviders) {
    _settingsSubscriptions.add(
      container.listen<Object?>(provider, (_, _) => _triggerSave()),
    );
  }
  _watchEditorArea();
}

/// Saves the session whenever what it records about the editor area changes.
///
/// Tabs join and leave groups through their own controllers -- the close
/// button, a drag, the SDK -- so the layout state alone would miss most of it.
/// [EditorLayoutNotifier.changes] reports every change in any group, and a
/// save is only scheduled when the persisted shape actually differs, so a
/// title refresh or re-selecting the selected tab writes nothing.
void _watchEditorArea() {
  var last = persistedEditorAreaKey(container);
  container.read(editorLayoutProvider.notifier).changes.addListener(() {
    final next = persistedEditorAreaKey(container);
    if (next == last) return;
    last = next;
    _triggerSave();
  });
}

/// Moves console surfaces out of the editor area when the window narrows to
/// the mobile layout.
///
/// Grouping is a desktop and tablet feature: on mobile the terminal lives in
/// its bottom popup, so a surface dragged into an editor group has to return
/// to the panel for the popup to show it.
void _gatherConsoleOnMobileLayout() {
  final environment = container.read(environmentNotifierProvider);
  var layoutMode = environment.snapshot.layoutMode;
  environment.addListener(() {
    final next = environment.snapshot.layoutMode;
    if (next == layoutMode) return;
    layoutMode = next;
    if (next == LayoutMode.mobile) evacuateConsoleTabsToPanel(container);
  });
}

/// Retained so the settings subscriptions outlive [_startAutoSave]'s scope.
final List<ProviderSubscription<Object?>> _settingsSubscriptions = [];

Future<void> _startRuntimeAndPlugins() async {
  final runtimeHost = container.read(pythonRuntimeHostProvider);
  try {
    await runtimeHost.start();
  } catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'pyrite_ide',
        context: ErrorDescription('while bootstrapping the Python runtime'),
      ),
    );
    // The editor remains usable when the optional Python runtime is not
    // available. Plugin activation is intentionally skipped for this launch.
    return;
  }

  try {
    await container.read(pluginManagerProvider.notifier).autoStart();
  } catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'pyrite_ide',
        context: ErrorDescription('while activating startup plugins'),
      ),
    );
  }
}

// PyriteIDE: Hello World.
void main() async {
  final bootCycle = Stopwatch()..start();
  GitDebugLog.startSession();
  GitDebugLog.log('main start');
  PyriteWidgetsBinding.ensureInitialized();

  // Wait for Material Icons font to be fully loaded before first frame.
  // This prevents the "tofu" (question mark box) issue on desktop platforms.
  await Future.delayed(const Duration(milliseconds: 50));
  VideoPlayerMediaKit.ensureInitialized(windows: true, linux: true);
  GitDebugLog.log('WidgetsFlutterBinding initialized');
  await GitDebugLog.timeAsync(
    'git2dart PlatformSpecific.initialize',
    PlatformSpecific.initialize,
  );

  persistenceManager = PersistenceManager();
  final PersistedData data = await persistenceManager.loadAll();

  final pluginPersistence = PluginPersistence();
  List<PluginPersistedData>? persistedPlugins;
  var pluginMetadataLoaded = true;
  try {
    persistedPlugins = await pluginPersistence.load();
  } catch (error, stackTrace) {
    pluginMetadataLoaded = false;
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'pyrite_ide',
        context: ErrorDescription('while loading plugin metadata'),
      ),
    );
  }

  container = ProviderContainer();
  _installIdeOutputLogger();
  GitDebugLog.log('ProviderContainer and global error logging installed');

  // One banner per launch: a report that says "it is slow to start" or "the
  // board reconnected by itself" has nothing to correlate otherwise, and a run
  // that ends without an error still leaves evidence it happened.
  AppLog.session('lifecycle', {
    'os': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    'dart': Platform.version.split(' ').first,
    'mode': kReleaseMode
        ? 'release'
        : kProfileMode
        ? 'profile'
        : 'debug',
    'locale': Platform.localeName,
    'cpus': Platform.numberOfProcessors,
    'plugins': persistedPlugins?.length ?? 0,
    'pluginMetadata': pluginMetadataLoaded ? 'ok' : 'failed',
    'bootMs': bootCycle.elapsedMilliseconds,
  });

  _applyData(data);

  final pluginManager = container.read(pluginManagerProvider.notifier);
  if (pluginMetadataLoaded) {
    if (persistedPlugins != null && persistedPlugins.isNotEmpty) {
      pluginManager.loadPersisted(persistedPlugins);
    }
    await pluginManager.applyPendingChanges();
  } else {
    pluginManager.markMetadataUnavailable();
  }

  if (data.projectPath != null) {
    final dir = Directory(data.projectPath!);
    if (await dir.exists()) {
      container.read(fileProvider.notifier).setDirectory(dir);
      container.read(localFileItemsProvider.notifier).buildRootFileListItems();
    }
  }

  await RustLib.init();
  await PlatformSpecific.initialize();

  // The tree is what carries more than one group. Without it the flat list is
  // the only reliable source: restoring the groups alone would drop every
  // group past the first, since the tree is what builds their controllers.
  if (data.tabLayout != null && data.tabGroups.isNotEmpty) {
    // A session saved with a split editor area: every group comes back, and the
    // tree puts them where the user left them.
    await container
        .read(tabbedViewControllerProvider.notifier)
        .restoreEditorGroups(
          data.tabGroups,
          data.tabLayout,
          primaryIndex: data.tabPrimaryGroupIndex,
        );
  } else if (data.tabs.isNotEmpty) {
    await container
        .read(tabbedViewControllerProvider.notifier)
        .restoreTabs(
          data.tabs,
          data.selectedTabIndex,
          selectedTabPath: data.selectedTabPath,
        );
  }

  // The board mirror only ever holds scratch copies of board files. Anything
  // no restored tab points at was written by an earlier session, and deleting
  // it here keeps the directory from growing with every download.
  unawaited(
    pruneBoardMirrorDirectory(
      keepRelativePaths: {
        for (final tab in data.tabs)
          if (tab.boardFilePath != null &&
              tab.boardFilePath!.isNotEmpty &&
              tab.isBoardFile)
            boardMirrorRelativePath(tab.boardFilePath!),
      },
    ).then(
      (removed) {
        if (removed > 0) {
          GitDebugLog.log('pruned $removed stale board mirror entries');
        }
      },
      onError: (Object error) {
        GitDebugLog.log('board mirror prune failed', error: error);
      },
    ),
  );

  appWindow.bind(container);
  appWindow.init();

  GitDebugLog.log('runApp start');
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: PeriodicTaskLifecycleObserver(child: const PyriteIDE()),
    ),
  );

  _startAutoSave();
  _gatherConsoleOnMobileLayout();

  // Let Flutter paint the first frame before native CPython initialization.
  // Startup plugins still wait for the runtime snapshot inside the helper.
  unawaited(_startRuntimeAndPlugins());
}
