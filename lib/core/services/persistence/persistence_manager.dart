import 'dart:convert';

import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart' show Color, ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/models/pane_edge.dart';
import 'package:pyrite_ide/core/models/settings.dart';
import 'package:pyrite_ide/core/models/terminal_appearance.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/data_registry.dart';
import 'package:pyrite_ide/core/services/editor/editor_split.dart';
import 'package:pyrite_ide/core/services/editor/outline_tab.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/core/services/file/file_transfer_mode_provider.dart';
import 'package:pyrite_ide/core/services/function_page.dart';
import 'package:pyrite_ide/core/services/persistence/app_persistence.dart';
import 'package:pyrite_ide/core/services/persistence/data_contributions_persistence.dart';
import 'package:pyrite_ide/core/services/persistence/editor/tabs_persistence.dart';
import 'package:pyrite_ide/core/services/persistence/file/project_persistence.dart';
import 'package:pyrite_ide/core/services/persistence/function_page_persistence.dart';
import 'package:pyrite_ide/core/services/persistence/persistence_models.dart';
import 'package:pyrite_ide/core/services/persistence/settings_persistence.dart';
import 'package:pyrite_ide/core/services/serial/hardware_reset_provider.dart';
import 'package:pyrite_ide/core/services/serial/repl_mode_provider.dart';
import 'package:pyrite_ide/core/services/serial/serial_provider.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/core/services/window_placement.dart';
import 'package:tabbed_view/tabbed_view.dart'
    show TabData, TabbedViewController;

/// The project directory recorded in settings.
final ProviderListenable<String?> persistedProjectPathProvider = fileProvider
    .select((directory) => directory?.path);

/// The serial port recorded in settings.
///
/// The selector keeps live connection state out of the comparison: the port
/// list is rescanned on a timer every few seconds and replacing it must not
/// look like a settings change that schedules another save.
final ProviderListenable<String?> persistedSerialPortProvider = serialProvider
    .select((state) => state.selectedPortName);

/// Every provider [PersistenceManager.saveFromContainer] reads for a setting.
///
/// The open tabs and their layout are persisted too, but they change through
/// their own controllers and have dedicated change watchers; they are
/// deliberately absent here. `main` subscribes to this list to dirty the
/// session whenever a setting changes, so a setting the save path writes but
/// this list omits would only reach disk if some unrelated change happened to
/// dirty the session first.
final List<ProviderListenable<Object?>> persistedSettingProviders = [
  themeMode,
  themeStyle,
  themeColor,
  editorThemeKey,
  activePluginThemeId,
  welcomeCompletedProvider,
  activeLocaleProvider,
  alwaysOnTopProvider,
  windowPlacementProvider,
  editorTextFontProvider,
  editorFontSize,
  editorWordWrap,
  editorLineNumber,
  editorCodeFolding,
  editorGuideLines,
  editorLocalSuggestions,
  editorKeyboardSuggestions,
  editorUseSpaceAsTab,
  editorTabSize,
  editorGutterDivider,
  editorSmoothCursor,
  editorMinimap,
  editorFormatOnSave,
  useLsp,
  lspType,
  lspWebSocketPath,
  lspStdioExecutable,
  lspStdioArgs,
  lspVirtualEnvironment,
  lspBasedPyrightTypeCheckingMode,
  disableWarning,
  disableError,
  lspSemanticHighlighting,
  lspCodeCompletion,
  lspHoverInfo,
  lspCodeAction,
  lspSignatureHelp,
  lspDocumentColor,
  lspDocumentHighlight,
  lspCodeFolding,
  lspShowInlayHints,
  lspGoToDefinition,
  lspRename,
  lspAlwaysStart,
  chineseToUnicodeConversion,
  enableSignalDetection,
  ensureBoardFilesystemOnConnect,
  deviceRunChdirToScriptDir,
  serialDefaultBaudRate,
  serialAutoReconnect,
  persistedSerialPortProvider,
  terminalFontFamily,
  terminalFontSize,
  terminalLineHeight,
  terminalLigatures,
  terminalAppearance,
  terminalMinimumContrast,
  terminalCustomForeground,
  terminalCustomBackground,
  terminalCustomPalette,
  useMaterialContextMenu,
  uploadConfirmStyleProvider,
  fileSortModeProvider,
  confirmShortcutProvider,
  cancelShortcutProvider,
  webReplHost,
  webReplPort,
  webReplPassword,
  microPythonStubsEnabled,
  microPythonStubsAutoDetectLayers,
  microPythonStubsLayers,
  microPythonStubsExtraPaths,
  replModeProvider,
  fileTransferModeProvider,
  hardwareResetStrategyProvider,
  desktopSelectedIndex,
  mobileSelectedIndex,
  tabletSelectedIndex,
  functionPageShow,
  consolePageShow,
  consoleDockSideProvider,
  persistedProjectPathProvider,
  dataContributionsProvider,
];

class PersistenceManager {
  PersistenceManager({
    AppPersistence? appPersistence,
    DataContributionsPersistence? dataContributionsPersistence,
    SettingsPersistence? settingsPersistence,
    FunctionPagePersistence? functionPagePersistence,
    ProjectPersistence? projectPersistence,
    TabsPersistence? tabsPersistence,
  }) : appPersistence = appPersistence ?? AppPersistence(),
       dataContributionsPersistence =
           dataContributionsPersistence ?? DataContributionsPersistence(),
       settingsPersistence = settingsPersistence ?? SettingsPersistence(),
       functionPagePersistence =
           functionPagePersistence ?? FunctionPagePersistence(),
       projectPersistence = projectPersistence ?? ProjectPersistence(),
       tabsPersistence = tabsPersistence ?? TabsPersistence();

  final AppPersistence appPersistence;
  final DataContributionsPersistence dataContributionsPersistence;
  final SettingsPersistence settingsPersistence;
  final FunctionPagePersistence functionPagePersistence;
  final ProjectPersistence projectPersistence;
  final TabsPersistence tabsPersistence;

  Future<PersistedData> loadAll() async {
    final app = await appPersistence.load();
    final settings = await settingsPersistence.load();
    final functionPage = await functionPagePersistence.load();
    final project = await projectPersistence.load();
    final tabsData = await tabsPersistence.load();
    final dataContributions = await dataContributionsPersistence.load();

    return PersistedData(
      themeMode: app?.themeMode ?? 'system',
      themeStyle: app?.themeStyle ?? 'standard',
      themeColorValue: app?.themeColorValue,
      editorThemeKey: app?.editorThemeKey ?? 'atom-one',
      activePluginThemeId: app?.activePluginThemeId,
      welcomeCompleted: app?.welcomeCompleted ?? false,
      activeLocale: app?.activeLocale ?? defaultLocale,
      alwaysOnTop: app?.alwaysOnTop ?? false,
      windowPlacement: app?.windowPlacement,
      editorTextFont: settings?.editorTextFont ?? 'JetBrains Mono',
      editorFontSize: settings?.editorFontSize ?? 15,
      editorWordWrap: settings?.editorWordWrap ?? false,
      editorLineNumber: settings?.editorLineNumber ?? true,
      editorCodeFolding: settings?.editorCodeFolding ?? true,
      editorGuideLines: settings?.editorGuideLines ?? true,
      editorLocalSuggestions: settings?.editorLocalSuggestions ?? false,
      editorKeyboardSuggestions: settings?.editorKeyboardSuggestions ?? true,
      editorUseSpaceAsTab: settings?.editorUseSpaceAsTab ?? true,
      editorTabSize: settings?.editorTabSize ?? 4,
      editorGutterDivider: settings?.editorGutterDivider ?? false,
      editorSmoothCursor: settings?.editorSmoothCursor ?? false,
      editorMinimap: settings?.editorMinimap ?? true,
      editorFormatOnSave: settings?.editorFormatOnSave ?? false,
      useLsp: settings?.useLsp ?? true,
      lspType: settings?.lspType ?? 'web_socket',
      lspWebSocketPath: settings?.lspWebSocketPath ?? '127.0.0.1:2026',
      lspStdioExecutable: settings?.lspStdioExecutable ?? '',
      lspStdioArgs: settings?.lspStdioArgs ?? '',
      lspVirtualEnvironment: settings?.lspVirtualEnvironment ?? '',
      lspBasedPyrightTypeCheckingMode:
          settings?.lspBasedPyrightTypeCheckingMode ?? 'standard',
      disableWarning: settings?.disableWarning ?? false,
      disableError: settings?.disableError ?? false,
      lspSemanticHighlighting: settings?.lspSemanticHighlighting ?? true,
      lspCodeCompletion: settings?.lspCodeCompletion ?? true,
      lspHoverInfo: settings?.lspHoverInfo ?? true,
      lspCodeAction: settings?.lspCodeAction ?? true,
      lspSignatureHelp: settings?.lspSignatureHelp ?? true,
      lspDocumentColor: settings?.lspDocumentColor ?? true,
      lspDocumentHighlight: settings?.lspDocumentHighlight ?? true,
      lspCodeFolding: settings?.lspCodeFolding ?? true,
      lspShowInlayHints: settings?.lspShowInlayHints ?? true,
      lspGoToDefinition: settings?.lspGoToDefinition ?? true,
      lspRename: settings?.lspRename ?? true,
      lspAlwaysStart: settings?.lspAlwaysStart ?? false,
      desktopSelectedIndex: functionPage?.desktopSelectedIndex ?? 0,
      mobileSelectedIndex: functionPage?.mobileSelectedIndex ?? 0,
      tabletSelectedIndex: functionPage?.tabletSelectedIndex ?? 0,
      functionPageShow: functionPage?.functionPageShow ?? true,
      consolePageShow: functionPage?.consolePageShow ?? true,
      consoleDockSide: functionPage?.consoleDockSide ?? 'bottom',
      projectPath: project?.projectPath,
      tabs: tabsData?.tabs ?? [],
      tabGroups: tabsData?.groups ?? const [],
      tabLayout: tabsData?.layout,
      tabPrimaryGroupIndex: tabsData?.primaryGroupIndex ?? 0,
      selectedTabIndex: tabsData?.selectedTabIndex ?? 0,
      selectedTabPath: tabsData?.selectedTabPath,
      chineseToUnicodeConversion: settings?.chineseToUnicodeConversion ?? true,
      enableSignalDetection: settings?.enableSignalDetection ?? true,
      ensureBoardFilesystemOnConnect:
          settings?.ensureBoardFilesystemOnConnect ?? false,
      deviceRunChdirToScriptDir: settings?.deviceRunChdirToScriptDir ?? false,
      serialDefaultBaudRate: settings?.serialDefaultBaudRate ?? 115200,
      serialAutoReconnect: settings?.serialAutoReconnect ?? false,
      serialActivePortPath: settings?.serialActivePortPath ?? '',
      terminalFontFamily:
          settings?.terminalFontFamily ?? 'JetBrains Maple Mono',
      terminalFontSize: settings?.terminalFontSize ?? 13,
      terminalLineHeight: settings?.terminalLineHeight ?? 1.2,
      terminalLigatures: settings?.terminalLigatures ?? true,
      terminalAppearance: settings?.terminalAppearance ?? 'dark',
      terminalMinimumContrast: settings?.terminalMinimumContrast ?? false,
      terminalCustomForeground:
          settings?.terminalCustomForeground ??
          kDefaultTerminalCustomForeground,
      terminalCustomBackground:
          settings?.terminalCustomBackground ??
          kDefaultTerminalCustomBackground,
      terminalCustomPalette:
          settings?.terminalCustomPalette ?? kDefaultTerminalCustomPalette,
      useMaterialContextMenu: settings?.useMaterialContextMenu ?? false,
      uploadConfirmStyle: settings?.uploadConfirmStyle ?? 'toolbar',
      fileSortMode: settings?.fileSortMode ?? 'name',
      confirmShortcut: settings?.confirmShortcut ?? 'Ctrl+Enter',
      cancelShortcut: settings?.cancelShortcut ?? 'Esc',
      webReplHost: settings?.webReplHost ?? '',
      webReplPort: settings?.webReplPort ?? 8266,
      webReplPassword: settings?.webReplPassword ?? '',
      microPythonStubsEnabled: settings?.microPythonStubsEnabled ?? false,
      microPythonStubsAutoDetectLayers:
          settings?.microPythonStubsAutoDetectLayers ?? false,
      microPythonStubsLayers: settings?.microPythonStubsLayers ?? const [],
      microPythonStubsExtraPaths:
          settings?.microPythonStubsExtraPaths ?? const [],
      replMode: settings?.replMode ?? 'rawRepl',
      fileTransferMode: settings?.fileTransferMode ?? 'streaming',
      hardwareResetStrategy: settings?.hardwareResetStrategy ?? 'disabled',
      dataContributions: dataContributions ?? const [],
    );
  }

  /// Applies the settings a previous session left behind to [container].
  ///
  /// Taking the container as a parameter keeps the restore path testable
  /// without the app's global container; production passes that container.
  void applyTo(ProviderContainer container, PersistedData data) {
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
    container.read(activePluginThemeId.notifier).state =
        data.activePluginThemeId;
    container.read(welcomeCompletedProvider.notifier).state =
        data.welcomeCompleted;
    container.read(activeLocaleProvider.notifier).state = data.activeLocale;
    container.read(alwaysOnTopProvider.notifier).state = data.alwaysOnTop;
    container.read(windowPlacementProvider.notifier).state =
        data.windowPlacement;
    container.read(editorTextFontProvider.notifier).state = data.editorTextFont;
    container.read(editorFontSize.notifier).state = data.editorFontSize;
    container.read(editorWordWrap.notifier).state = data.editorWordWrap;
    container.read(editorLineNumber.notifier).state = data.editorLineNumber;
    container.read(editorCodeFolding.notifier).state = data.editorCodeFolding;
    container.read(editorGuideLines.notifier).state = data.editorGuideLines;
    container.read(editorLocalSuggestions.notifier).state =
        data.editorLocalSuggestions;
    container.read(editorKeyboardSuggestions.notifier).state =
        data.editorKeyboardSuggestions;
    container.read(editorUseSpaceAsTab.notifier).state =
        data.editorUseSpaceAsTab;
    container.read(editorTabSize.notifier).state = data.editorTabSize;
    container.read(editorGutterDivider.notifier).state =
        data.editorGutterDivider;
    container.read(editorSmoothCursor.notifier).state = data.editorSmoothCursor;
    container.read(editorMinimap.notifier).state = data.editorMinimap;
    container.read(editorFormatOnSave.notifier).state = data.editorFormatOnSave;
    container.read(useLsp.notifier).state = data.useLsp;
    container.read(lspType.notifier).state =
        LspType.fromJsonName(data.lspType) ?? LspType.webSocket;
    container.read(lspWebSocketPath.notifier).state = data.lspWebSocketPath;
    container.read(lspStdioExecutable.notifier).state = data.lspStdioExecutable;
    container.read(lspStdioArgs.notifier).state = data.lspStdioArgs;
    container.read(lspVirtualEnvironment.notifier).state =
        data.lspVirtualEnvironment;
    container.read(lspBasedPyrightTypeCheckingMode.notifier).state =
        BasedPyrightTypeCheckingMode.fromJsonName(
          data.lspBasedPyrightTypeCheckingMode,
        ) ??
        BasedPyrightTypeCheckingMode.standard;
    container.read(disableWarning.notifier).state = data.disableWarning;
    container.read(disableError.notifier).state = data.disableError;
    container.read(lspSemanticHighlighting.notifier).state =
        data.lspSemanticHighlighting;
    container.read(lspCodeCompletion.notifier).state = data.lspCodeCompletion;
    container.read(lspHoverInfo.notifier).state = data.lspHoverInfo;
    container.read(lspCodeAction.notifier).state = data.lspCodeAction;
    container.read(lspSignatureHelp.notifier).state = data.lspSignatureHelp;
    container.read(lspDocumentColor.notifier).state = data.lspDocumentColor;
    container.read(lspDocumentHighlight.notifier).state =
        data.lspDocumentHighlight;
    container.read(lspCodeFolding.notifier).state = data.lspCodeFolding;
    container.read(lspShowInlayHints.notifier).state = data.lspShowInlayHints;
    container.read(lspGoToDefinition.notifier).state = data.lspGoToDefinition;
    container.read(lspRename.notifier).state = data.lspRename;
    container.read(lspAlwaysStart.notifier).state = data.lspAlwaysStart;
    container.read(chineseToUnicodeConversion.notifier).state =
        data.chineseToUnicodeConversion;
    container.read(desktopSelectedIndex.notifier).state =
        data.desktopSelectedIndex;
    container.read(mobileSelectedIndex.notifier).state =
        data.mobileSelectedIndex;
    container.read(tabletSelectedIndex.notifier).state =
        data.tabletSelectedIndex;
    container.read(functionPageShow.notifier).state = data.functionPageShow;
    container.read(consolePageShow.notifier).state = data.consolePageShow;
    container.read(consoleDockSideProvider.notifier).state =
        PaneEdge.values.asNameMap()[data.consoleDockSide] ?? PaneEdge.bottom;
    container.read(enableSignalDetection.notifier).state =
        data.enableSignalDetection;
    container.read(ensureBoardFilesystemOnConnect.notifier).state =
        data.ensureBoardFilesystemOnConnect;
    container.read(deviceRunChdirToScriptDir.notifier).state =
        data.deviceRunChdirToScriptDir;
    container.read(serialDefaultBaudRate.notifier).state =
        data.serialDefaultBaudRate;
    container.read(serialAutoReconnect.notifier).state =
        data.serialAutoReconnect;
    container.read(replModeProvider.notifier).state =
        ReplMode.values.asNameMap()[data.replMode] ?? ReplMode.rawRepl;
    container.read(fileTransferModeProvider.notifier).state =
        FileTransferMode.values.asNameMap()[data.fileTransferMode] ??
        FileTransferMode.chunked;
    container.read(hardwareResetStrategyProvider.notifier).state =
        HardwareResetStrategy.values.asNameMap()[data.hardwareResetStrategy] ??
        HardwareResetStrategy.disabled;
    container.read(terminalFontFamily.notifier).state = data.terminalFontFamily;
    container.read(terminalFontSize.notifier).state = data.terminalFontSize;
    container.read(terminalLineHeight.notifier).state = data.terminalLineHeight;
    container.read(terminalLigatures.notifier).state = data.terminalLigatures;
    container.read(terminalAppearance.notifier).state =
        TerminalAppearance.values.asNameMap()[data.terminalAppearance] ??
        TerminalAppearance.dark;
    container.read(terminalMinimumContrast.notifier).state =
        data.terminalMinimumContrast;
    container.read(terminalCustomForeground.notifier).state =
        data.terminalCustomForeground;
    container.read(terminalCustomBackground.notifier).state =
        data.terminalCustomBackground;
    container
        .read(terminalCustomPalette.notifier)
        .state = data.terminalCustomPalette.length == 16
        ? data.terminalCustomPalette
        : kDefaultTerminalCustomPalette;
    container.read(useMaterialContextMenu.notifier).state =
        data.useMaterialContextMenu;
    container
        .read(serialProvider.notifier)
        .setBaudRate(data.serialDefaultBaudRate);
    container
        .read(serialProvider.notifier)
        .setAutoReconnect(data.serialAutoReconnect);
    container.read(uploadConfirmStyleProvider.notifier).state =
        data.uploadConfirmStyle;
    container.read(fileSortModeProvider.notifier).state =
        FileSortMode.fromJsonName(data.fileSortMode);
    container.read(confirmShortcutProvider.notifier).state =
        data.confirmShortcut;
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
    container.read(dataContributionsProvider.notifier).state =
        data.dataContributions;
    container
        .read(dataRegistryProvider)
        .restoreContributions(data.dataContributions);
  }

  Future<void> saveFromContainer(ProviderContainer container) async {
    await Future.wait([
      appPersistence.save(
        AppPersistedData(
          themeMode: container.read(themeMode).name,
          themeStyle: container.read(themeStyle).value,
          themeColorValue: (container.read(themeColor))?.toARGB32(),
          editorThemeKey: container.read(editorThemeKey),
          activePluginThemeId: container.read(activePluginThemeId),
          welcomeCompleted: container.read(welcomeCompletedProvider),
          activeLocale: container.read(activeLocaleProvider),
          alwaysOnTop: container.read(alwaysOnTopProvider),
          windowPlacement: container.read(windowPlacementProvider),
        ),
      ),
      settingsPersistence.save(
        SettingsPersistedData(
          editorTextFont: container.read(editorTextFontProvider),
          editorFontSize: container.read(editorFontSize),
          editorWordWrap: container.read(editorWordWrap),
          editorLineNumber: container.read(editorLineNumber),
          editorCodeFolding: container.read(editorCodeFolding),
          editorGuideLines: container.read(editorGuideLines),
          editorLocalSuggestions: container.read(editorLocalSuggestions),
          editorKeyboardSuggestions: container.read(editorKeyboardSuggestions),
          editorUseSpaceAsTab: container.read(editorUseSpaceAsTab),
          editorTabSize: container.read(editorTabSize),
          editorGutterDivider: container.read(editorGutterDivider),
          editorSmoothCursor: container.read(editorSmoothCursor),
          editorMinimap: container.read(editorMinimap),
          editorFormatOnSave: container.read(editorFormatOnSave),
          useLsp: container.read(useLsp),
          lspType: container.read(lspType).jsonName,
          lspWebSocketPath: container.read(lspWebSocketPath),
          lspStdioExecutable: container.read(lspStdioExecutable),
          lspStdioArgs: container.read(lspStdioArgs),
          lspVirtualEnvironment: container.read(lspVirtualEnvironment),
          lspBasedPyrightTypeCheckingMode: container
              .read(lspBasedPyrightTypeCheckingMode)
              .jsonName,
          disableWarning: container.read(disableWarning),
          disableError: container.read(disableError),
          lspSemanticHighlighting: container.read(lspSemanticHighlighting),
          lspCodeCompletion: container.read(lspCodeCompletion),
          lspHoverInfo: container.read(lspHoverInfo),
          lspCodeAction: container.read(lspCodeAction),
          lspSignatureHelp: container.read(lspSignatureHelp),
          lspDocumentColor: container.read(lspDocumentColor),
          lspDocumentHighlight: container.read(lspDocumentHighlight),
          lspCodeFolding: container.read(lspCodeFolding),
          lspShowInlayHints: container.read(lspShowInlayHints),
          lspGoToDefinition: container.read(lspGoToDefinition),
          lspRename: container.read(lspRename),
          lspAlwaysStart: container.read(lspAlwaysStart),
          chineseToUnicodeConversion: container.read(
            chineseToUnicodeConversion,
          ),
          enableSignalDetection: container.read(enableSignalDetection),
          ensureBoardFilesystemOnConnect: container.read(
            ensureBoardFilesystemOnConnect,
          ),
          deviceRunChdirToScriptDir: container.read(deviceRunChdirToScriptDir),
          serialDefaultBaudRate: container.read(serialDefaultBaudRate),
          serialAutoReconnect: container.read(serialAutoReconnect),
          serialActivePortPath:
              container.read(persistedSerialPortProvider) ?? '',
          terminalFontFamily: container.read(terminalFontFamily),
          terminalFontSize: container.read(terminalFontSize),
          terminalLineHeight: container.read(terminalLineHeight),
          terminalLigatures: container.read(terminalLigatures),
          terminalAppearance: container.read(terminalAppearance).name,
          terminalMinimumContrast: container.read(terminalMinimumContrast),
          terminalCustomForeground: container.read(terminalCustomForeground),
          terminalCustomBackground: container.read(terminalCustomBackground),
          terminalCustomPalette: container.read(terminalCustomPalette),
          useMaterialContextMenu: container.read(useMaterialContextMenu),
          uploadConfirmStyle: container.read(uploadConfirmStyleProvider),
          fileSortMode: container.read(fileSortModeProvider).jsonName,
          confirmShortcut: container.read(confirmShortcutProvider),
          cancelShortcut: container.read(cancelShortcutProvider),
          webReplHost: container.read(webReplHost),
          webReplPort: container.read(webReplPort),
          webReplPassword: container.read(webReplPassword),
          microPythonStubsEnabled: container.read(microPythonStubsEnabled),
          microPythonStubsAutoDetectLayers: container.read(
            microPythonStubsAutoDetectLayers,
          ),
          microPythonStubsLayers: container.read(microPythonStubsLayers),
          microPythonStubsExtraPaths: container.read(
            microPythonStubsExtraPaths,
          ),
          replMode: container.read(replModeProvider).name,
          fileTransferMode: container.read(fileTransferModeProvider).name,
          hardwareResetStrategy: container
              .read(hardwareResetStrategyProvider)
              .name,
        ),
      ),
      functionPagePersistence.save(
        FunctionPagePersistedData(
          desktopSelectedIndex: container.read(desktopSelectedIndex),
          mobileSelectedIndex: container.read(mobileSelectedIndex),
          tabletSelectedIndex: container.read(tabletSelectedIndex),
          functionPageShow: container.read(functionPageShow),
          consolePageShow: container.read(consolePageShow),
          consoleDockSide: container.read(consoleDockSideProvider).name,
        ),
      ),
      _saveProject(container),
      _saveTabs(container),
      dataContributionsPersistence.save(
        container.read(dataContributionsProvider),
      ),
    ]);
  }

  Future<void> _saveProject(ProviderContainer container) async {
    final projectPath = container.read(persistedProjectPathProvider);
    await projectPersistence.save(
      ProjectPersistedData(projectPath: projectPath),
    );
  }

  Future<void> _saveTabs(ProviderContainer container) async {
    final primary = container.read(tabbedViewControllerProvider);
    final layout = container.read(editorLayoutProvider);
    if (layout is SplitLayout) {
      // The tree is persisted as it stands, so any number of nested groups
      // reopens exactly as it was left -- including which of them is the
      // primary one.
      final persisted = persistEditorLayout(
        layout,
        primary: primary,
        convert: _persistGroup,
      );
      await tabsPersistence.save(
        TabsPersistedData(
          tabs: const [],
          selectedTabIndex: 0,
          groups: persisted.groups,
          layout: persisted.node,
          primaryGroupIndex: persisted.primaryIndex,
        ),
      );
      return;
    }
    // A single group needs no tree: the flat list restores it, and it is the
    // only place its tabs are written, so no buffer is serialized twice.
    final group = _persistGroup(primary);
    await tabsPersistence.save(
      TabsPersistedData(
        tabs: group.tabs,
        selectedTabIndex: primary.selectedIndex ?? 0,
        selectedTabPath: group.selectedTabPath,
      ),
    );
  }

  PersistedEditorGroup _persistGroup(TabbedViewController group) {
    return PersistedEditorGroup(
      tabs: [
        for (final tab in group.tabs)
          if (tab.value is OutlineTabValue)
            // Outline tabs persist as markers so a saved outline keeps its
            // position inside its group, wherever the tab was dragged to.
            PersistedTab(filePath: '', isOutline: true)
          else if (editorTabValueOf(tab) case final value?
              when value.type == 'file')
            _persistTab(value),
      ],
      selectedTabPath: editorTabValueOf(group.selectedTab)?.filePath,
    );
  }

  PersistedTab _persistTab(TabDataValue value) {
    return PersistedTab(
      filePath: value.filePath,
      isBoardFile: value.isBoardFile ?? false,
      boardFilePath: value.boardFilePath,
      isSaved: value.isSaved,
      unsavedContent: (!value.isSaved && value.editorController != null)
          ? value.editorController!.text
          : null,
      cursorOffset: value.editorController?.selection.extentOffset,
      scrollLine: value.editorController?.firstVisibleLine,
      foldedRanges: _persistFoldedRanges(value.editorController),
    );
  }
}

/// A fingerprint of what [PersistenceManager] writes for the editor area,
/// leaving out the buffers themselves.
///
/// Cheap enough to compute on every tab notification, so the session is only
/// saved when this changes: re-selecting the selected tab or a title refresh
/// writes nothing, while opening, closing, moving or selecting a tab, saving
/// one or reshaping the groups does.
String persistedEditorAreaKey(ProviderContainer container) {
  final persisted = persistEditorLayout(
    container.read(editorLayoutProvider),
    primary: container.read(tabbedViewControllerProvider),
    convert: (group) => PersistedEditorGroup(
      tabs: [for (final tab in group.tabs) ?_persistedTabShape(tab)],
      selectedTabPath: editorTabValueOf(group.selectedTab)?.filePath,
    ),
  );
  return jsonEncode({
    'groups': [for (final group in persisted.groups) group.toJson()],
    'layout': persisted.node.toJson(),
    'primary': persisted.primaryIndex,
  });
}

/// The part of one tab that [_persistGroup] writes, minus its buffer.
///
/// The list has to mirror the one [_persistGroup] produces, outline markers
/// included: opening or closing an outline tab changes what a save records, so
/// it has to change the key that decides whether a save happens at all. A key
/// that ignored outline tabs left the new layout unwritten until some unrelated
/// edit dirtied the session.
PersistedTab? _persistedTabShape(TabData tab) {
  if (tab.value is OutlineTabValue) {
    return PersistedTab(filePath: '', isOutline: true);
  }
  final value = editorTabValueOf(tab);
  if (value == null || value.type != 'file') return null;
  return PersistedTab(
    filePath: value.filePath,
    isBoardFile: value.isBoardFile ?? false,
    boardFilePath: value.boardFilePath,
    isSaved: value.isSaved,
  );
}

List<PersistedFoldRange> _persistFoldedRanges(CodeForgeController? controller) {
  final snapshots = controller?.foldedRanges ?? const [];
  if (snapshots.isEmpty) return const [];

  List<PersistedFoldRange> convert(List<FoldRangeSnapshot> snapshots) => [
    for (final snapshot in snapshots)
      PersistedFoldRange(
        startLine: snapshot.startLine,
        endLine: snapshot.endLine,
        children: convert(snapshot.children),
      ),
  ];

  return convert(snapshots);
}
