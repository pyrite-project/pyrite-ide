import 'dart:async';
import 'dart:io';
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
// import 'package:serious_python/serious_python.dart';

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
    container.read(themeColor.notifier).state =
        Color(data.themeColorValue!);
  }
  container.read(editorTextFontProvider.notifier).state =
      data.editorTextFont;
  container.read(editorFontSize.notifier).state = data.editorFontSize;
  container.read(editorWordWrap.notifier).state = data.editorWordWrap;
  container.read(editorLineNumber.notifier).state = data.editorLineNumber;
  container.read(useLsp.notifier).state = data.useLsp;
  container.read(lspWebScoketPath.notifier).state = data.lspWebSocketPath;
  container.read(disableWarning.notifier).state = data.disableWarning;
  container.read(disableError.notifier).state = data.disableError;
  container.read(desktopSelectedIndex.notifier).state =
      data.desktopSelectedIndex;
  container.read(mobileSelectedIndex.notifier).state =
      data.mobileSelectedIndex;
  container.read(tabletSelectedIndex.notifier).state =
      data.tabletSelectedIndex;
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

  if (data.tabs.isNotEmpty) {
    await container
        .read(tabbedViewControllerProvider.notifier)
        .restoreTabs(data.tabs, data.selectedTabIndex);
  }

  UseWindow().init();

  // SeriousPython.run(getPythonPath()!);
  // container.read(lspClientProvider);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: PeriodicTaskLifecycleObserver(child: const PyriteIDE()),
    ),
  );

  _startAutoSave();
}
