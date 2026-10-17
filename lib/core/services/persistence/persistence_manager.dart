import 'dart:convert';

import 'package:code_forge/code_forge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/models/terminal_appearance.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/editor/editor_split.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/function_page.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/core/services/persistence/app_persistence.dart';
import 'package:pyrite_ide/core/services/persistence/data_contributions_persistence.dart';
import 'package:pyrite_ide/core/services/persistence/settings_persistence.dart';
import 'package:pyrite_ide/core/services/persistence/function_page_persistence.dart';
import 'package:pyrite_ide/core/services/persistence/file/project_persistence.dart';
import 'package:pyrite_ide/core/services/persistence/editor/tabs_persistence.dart';
import 'package:pyrite_ide/core/services/persistence/persistence_models.dart';
import 'package:pyrite_ide/core/services/data_registry.dart';
import 'package:pyrite_ide/core/services/serial/repl_mode_provider.dart';
import 'package:pyrite_ide/core/services/file/file_transfer_mode_provider.dart';
import 'package:pyrite_ide/core/services/serial/hardware_reset_provider.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:tabbed_view/tabbed_view.dart' show TabbedViewController;

class PersistenceManager {
  final AppPersistence appPersistence = AppPersistence();
  final DataContributionsPersistence dataContributionsPersistence =
      DataContributionsPersistence();
  final SettingsPersistence settingsPersistence = SettingsPersistence();
  final FunctionPagePersistence functionPagePersistence =
      FunctionPagePersistence();
  final ProjectPersistence projectPersistence = ProjectPersistence();
  final TabsPersistence tabsPersistence = TabsPersistence();

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
      serialDefaultBaudRate: settings?.serialDefaultBaudRate ?? 115200,
      serialAutoReconnect: settings?.serialAutoReconnect ?? false,
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
          serialDefaultBaudRate: container.read(serialDefaultBaudRate),
          serialAutoReconnect: container.read(serialAutoReconnect),
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
    final dir = container.read(fileProvider);
    await projectPersistence.save(ProjectPersistedData(projectPath: dir?.path));
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
          if (editorTabValueOf(tab) case final value? when value.type == 'file')
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
      tabs: [
        for (final tab in group.tabs)
          if (editorTabValueOf(tab) case final value? when value.type == 'file')
            PersistedTab(
              filePath: value.filePath,
              isBoardFile: value.isBoardFile ?? false,
              boardFilePath: value.boardFilePath,
              isSaved: value.isSaved,
            ),
      ],
      selectedTabPath: editorTabValueOf(group.selectedTab)?.filePath,
    ),
  );
  return jsonEncode({
    'groups': [for (final group in persisted.groups) group.toJson()],
    'layout': persisted.node.toJson(),
    'primary': persisted.primaryIndex,
  });
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
