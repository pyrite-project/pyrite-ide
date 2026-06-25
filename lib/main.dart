import 'dart:async';
import 'dart:io';
import 'package:code_forge/code_forge.dart' show RustLib;
import 'package:flutter/material.dart';
import 'package:pyrite_ide/app/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/persistence/persistence_manager.dart';
import 'package:pyrite_ide/core/services/persistence/persistence_models.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/local_file_items_provider.dart';
import 'package:pyrite_ide/core/services/file/local_workspace_provider.dart';
import 'package:pyrite_ide/core/services/function_page.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/core/services/periodic_task/main.dart';
import 'package:pyrite_ide/features/window.dart';
import 'package:serious_python/serious_python.dart';

String? getPythonPath() {
  if (Platform.isAndroid) return "assets/android/python.zip";
  if (Platform.isWindows) return "assets/windows/python.zip";
  if (Platform.isLinux) return "assets/linux/python.zip";
  if (Platform.isMacOS) return "assets/macos/python.zip";
  return null;
}

late final PersistenceManager persistenceManager;
Timer? _saveTimer;
Timer? _debounceTimer;

void _applyData(PersistedData data) {
  switch (data.themeMode) {
    case 'light':
      container.read(themeMode.notifier).state = ThemeMode.light;
    case 'dark':
      container.read(themeMode.notifier).state = ThemeMode.dark;
    default:
      container.read(themeMode.notifier).state = ThemeMode.system;
  }

  if (data.themeColorValue != null) {
    container.read(themeColor.notifier).state = Color(data.themeColorValue!);
  }
  container.read(themeStyle.notifier).state = ThemeStyle.fromValue(
    data.themeStyle,
  );
  container.read(editorThemeKey.notifier).state = data.editorThemeKey;
  container.read(editorTextFontProvider.notifier).state = data.editorTextFont;
  container.read(editorFontSize.notifier).state = data.editorFontSize;
  container.read(editorWordWrap.notifier).state = data.editorWordWrap;
  container.read(editorLineNumber.notifier).state = data.editorLineNumber;
  container.read(useLsp.notifier).state = data.useLsp;
  container.read(lspWebScoketPath.notifier).state = data.lspWebSocketPath;
  container.read(disableWarning.notifier).state = data.disableWarning;
  container.read(disableError.notifier).state = data.disableError;
  container.read(desktopSelectedIndex.notifier).state =
      data.desktopSelectedIndex;
  container.read(mobileSelectedIndex.notifier).state = data.mobileSelectedIndex;
  container.read(tabletSelectedIndex.notifier).state = data.tabletSelectedIndex;
  container.read(functionPageShow.notifier).state = data.functionPageShow;
  container.read(consolePageShow.notifier).state = data.consolePageShow;
  container.read(expansionPageShow.notifier).state = data.expansionPageShow;
  container.read(enableSignalDetection.notifier).state =
      data.enableSignalDetection;
  container.read(uploadConfirmStyleProvider.notifier).state =
      data.uploadConfirmStyle;
  container.read(confirmShortcutProvider.notifier).state = data.confirmShortcut;
  container.read(cancelShortcutProvider.notifier).state = data.cancelShortcut;
}

void _triggerSave() {
  _debounceTimer?.cancel();
  _debounceTimer = Timer(const Duration(seconds: 1), () async {
    await persistenceManager.saveFromContainer(container);
  });
}

void _startAutoSave() {
  _saveTimer?.cancel();
  _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
    await persistenceManager.saveFromContainer(container);
  });
  container.read(tabbedViewControllerProvider.notifier).onUnsavedChange = () {
    _triggerSave();
  };
}

Future<void> _bootstrapPythonRuntime() async {
  try {
    await SeriousPython.run(
      "assets/python_runtime_boot.zip",
      appFileName: "boot.py",
    );
  } catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: "pyrite_ide",
        context: ErrorDescription("while bootstrapping the Python runtime"),
      ),
    );
  }
}

// PyriteIDE: Hello World.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  persistenceManager = PersistenceManager();
  final PersistedData data = await persistenceManager.loadAll();

  container = ProviderContainer();

  _applyData(data);

  if (data.workspacePath != null) {
    final dir = Directory(data.workspacePath!);
    if (await dir.exists()) {
      container.read(localWorkspaceProvider.notifier).setDirectory(dir);
      container.read(localFileItemsProvider.notifier).buildRootFileListItems();
    }
  }

  await RustLib.init();

  if (data.tabs.isNotEmpty) {
    await container
        .read(tabbedViewControllerProvider.notifier)
        .restoreTabs(data.tabs, data.selectedTabIndex);
  }

  await UseWindow().init();

  await _bootstrapPythonRuntime();
  // container.read(lspClientProvider);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: PeriodicTaskLifecycleObserver(child: const PyriteIDE()),
    ),
  );

  _startAutoSave();
}
