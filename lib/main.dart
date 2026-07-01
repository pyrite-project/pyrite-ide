import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:code_forge/code_forge.dart' show RustLib;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pyrite_ide/app/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/output/ide_output_log.dart';
import 'package:pyrite_ide/core/services/persistence/persistence_manager.dart';
import 'package:pyrite_ide/core/services/persistence/persistence_models.dart';
import 'package:pyrite_ide/core/services/persistence/plugin_persistence.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/local_file_items_provider.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/core/services/function_page.dart';
import 'package:pyrite_ide/core/services/serial/android_usb_serial_provider.dart';
import 'package:pyrite_ide/core/services/serial/desktop_usb_serial_provider.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/core/models/settings.dart';
import 'package:pyrite_ide/core/services/periodic_task/main.dart';
import 'package:pyrite_ide/core/sdk/plugin_manager_provider.dart';
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
Timer? _pluginSaveTimer;
final UseWindow appWindow = UseWindow();
DebugPrintCallback? _defaultDebugPrint;

void _installIdeOutputLogger() {
  if (_defaultDebugPrint != null) return;
  _defaultDebugPrint = debugPrint;
  IdeOutputLogNotifier.setDebugMirror(_defaultDebugPrint);
  debugPrint = (String? message, {int? wrapWidth}) {
    final text = message ?? 'null';
    container
        .read(ideOutputLogProvider.notifier)
        .add(IdeOutputSource.ide, text);
    _defaultDebugPrint?.call(message, wrapWidth: wrapWidth);
  };

  FlutterError.onError = (FlutterErrorDetails details) {
    final message = details.exceptionAsString();
    final stack = details.stack?.toString();
    container
        .read(ideOutputLogProvider.notifier)
        .add(IdeOutputSource.ide, '$message${stack == null ? '' : '\n$stack'}');
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    container
        .read(ideOutputLogProvider.notifier)
        .add(IdeOutputSource.ide, 'Unhandled exception: $error\n$stack');
    return false;
  };
}

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
  container.read(activePluginThemeId.notifier).state = data.activePluginThemeId;
  container.read(editorTextFontProvider.notifier).state = data.editorTextFont;
  container.read(editorFontSize.notifier).state = data.editorFontSize;
  container.read(editorWordWrap.notifier).state = data.editorWordWrap;
  container.read(editorLineNumber.notifier).state = data.editorLineNumber;
  container.read(editorCodeFolding.notifier).state = data.editorCodeFolding;
  container.read(editorGuideLines.notifier).state = data.editorGuideLines;
  container.read(editorLocalSuggestions.notifier).state = data.editorLocalSuggestions;
  container.read(editorKeyboardSuggestions.notifier).state = data.editorKeyboardSuggestions;
  container.read(editorUseSpaceAsTab.notifier).state = data.editorUseSpaceAsTab;
  container.read(editorTabSize.notifier).state = data.editorTabSize;
  container.read(editorGutterDivider.notifier).state = data.editorGutterDivider;
  container.read(useLsp.notifier).state = data.useLsp;
  container.read(lspType.notifier).state =
      LspType.fromJsonName(data.lspType) ?? LspType.webSocket;
  container.read(lspWebSocketPath.notifier).state = data.lspWebSocketPath;
  container.read(lspStdioExecutable.notifier).state = data.lspStdioExecutable;
  container.read(lspStdioArgs.notifier).state = data.lspStdioArgs;
  container.read(disableWarning.notifier).state = data.disableWarning;
  container.read(disableError.notifier).state = data.disableError;
  container.read(lspSemanticHighlighting.notifier).state = data.lspSemanticHighlighting;
  container.read(lspCodeCompletion.notifier).state = data.lspCodeCompletion;
  container.read(lspHoverInfo.notifier).state = data.lspHoverInfo;
  container.read(lspCodeAction.notifier).state = data.lspCodeAction;
  container.read(lspSignatureHelp.notifier).state = data.lspSignatureHelp;
  container.read(lspDocumentColor.notifier).state = data.lspDocumentColor;
  container.read(lspDocumentHighlight.notifier).state = data.lspDocumentHighlight;
  container.read(lspCodeFolding.notifier).state = data.lspCodeFolding;
  container.read(lspInlayHint.notifier).state = data.lspInlayHint;
  container.read(lspGoToDefinition.notifier).state = data.lspGoToDefinition;
  container.read(lspRename.notifier).state = data.lspRename;
  container.read(desktopSelectedIndex.notifier).state =
      data.desktopSelectedIndex;
  container.read(mobileSelectedIndex.notifier).state = data.mobileSelectedIndex;
  container.read(tabletSelectedIndex.notifier).state = data.tabletSelectedIndex;
  container.read(functionPageShow.notifier).state = data.functionPageShow;
  container.read(consolePageShow.notifier).state = data.consolePageShow;
  container.read(expansionPageShow.notifier).state = data.expansionPageShow;
  container.read(enableSignalDetection.notifier).state =
      data.enableSignalDetection;
  container.read(serialDefaultBaudRate.notifier).state = data.serialDefaultBaudRate;
  container.read(serialAutoReconnect.notifier).state = data.serialAutoReconnect;
  container.read(terminalFontFamily.notifier).state = data.terminalFontFamily;
  container.read(terminalFontSize.notifier).state = data.terminalFontSize;
  container.read(terminalLineHeight.notifier).state = data.terminalLineHeight;
  container.read(androidUsbSerialProvider.notifier).setBaudRate(data.serialDefaultBaudRate);
  container.read(androidUsbSerialProvider.notifier).setAutoReconnect(data.serialAutoReconnect);
  container.read(desktopUsbSerialProvider.notifier).setBaudRate(data.serialDefaultBaudRate);
  container.read(desktopUsbSerialProvider.notifier).setAutoReconnect(data.serialAutoReconnect);
  container.read(uploadConfirmStyleProvider.notifier).state =
      data.uploadConfirmStyle;
  container.read(confirmShortcutProvider.notifier).state = data.confirmShortcut;
  container.read(cancelShortcutProvider.notifier).state = data.cancelShortcut;
  container.read(webReplHost.notifier).state = data.webReplHost;
  container.read(webReplPort.notifier).state = data.webReplPort;
  container.read(webReplPassword.notifier).state = data.webReplPassword;
  container.read(microPythonStubsEnabled.notifier).state =
      data.microPythonStubsEnabled;
  container.read(microPythonStubsAutoDetectLayers.notifier).state =
      data.microPythonStubsAutoDetectLayers;
  container.read(microPythonStubsLayers.notifier).state =
      data.microPythonStubsLayers;
  container.read(microPythonStubsExtraPaths.notifier).state =
      data.microPythonStubsExtraPaths;
}

void _triggerSave() {
  _debounceTimer?.cancel();
  _debounceTimer = Timer(const Duration(seconds: 1), () async {
    await persistenceManager.saveFromContainer(container);
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
  _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
    await persistenceManager.saveFromContainer(container);
  });
  container.read(tabbedViewControllerProvider.notifier).onUnsavedChange = () {
    _triggerSave();
  };
  container.read(pluginManagerProvider.notifier).setOnChanged(() {
    _triggerPluginSave();
  });
}

// PyriteIDE: Hello World.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  persistenceManager = PersistenceManager();
  final PersistedData data = await persistenceManager.loadAll();

  final pluginPersistence = PluginPersistence();
  final persistedPlugins = await pluginPersistence.load();

  container = ProviderContainer();
  _installIdeOutputLogger();

  _applyData(data);

  if (persistedPlugins != null && persistedPlugins.isNotEmpty) {
    container
        .read(pluginManagerProvider.notifier)
        .loadPersisted(persistedPlugins);
  }

  // Auto-start plugins with autoStart: true
  container.read(pluginManagerProvider.notifier).autoStart();

  if (data.projectPath != null) {
    final dir = Directory(data.projectPath!);
    if (await dir.exists()) {
      container.read(fileProvider.notifier).setDirectory(dir);
      container.read(localFileItemsProvider.notifier).buildRootFileListItems();
    }
  }

  await RustLib.init();

  if (data.tabs.isNotEmpty) {
    await container
        .read(tabbedViewControllerProvider.notifier)
        .restoreTabs(data.tabs, data.selectedTabIndex);
  }

  appWindow.bind(container);
  appWindow.init();

  SeriousPython.run("assets/python_runtime_boot.zip", appFileName: "boot.py");
  // container.read(lspClientProvider);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: PeriodicTaskLifecycleObserver(child: const PyriteIDE()),
    ),
  );

  _startAutoSave();
}
