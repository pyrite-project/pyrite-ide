import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/services/app.dart';
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
import 'package:pyrite_ide/core/services/settings.dart';

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
      useLsp: settings?.useLsp ?? true,
      lspType: settings?.lspType ?? 'web_socket',
      lspWebSocketPath: settings?.lspWebSocketPath ?? '127.0.0.1:2026',
      lspStdioExecutable: settings?.lspStdioExecutable ?? '',
      lspStdioArgs: settings?.lspStdioArgs ?? '--stdio',
      disableWarning: settings?.disableWarning ?? false,
      disableError: settings?.disableError ?? false,
      lspSemanticHighlighting: settings?.lspSemanticHighlighting ?? false,
      lspCodeCompletion: settings?.lspCodeCompletion ?? true,
      lspHoverInfo: settings?.lspHoverInfo ?? true,
      lspCodeAction: settings?.lspCodeAction ?? true,
      lspSignatureHelp: settings?.lspSignatureHelp ?? true,
      lspDocumentColor: settings?.lspDocumentColor ?? false,
      lspDocumentHighlight: settings?.lspDocumentHighlight ?? true,
      lspCodeFolding: settings?.lspCodeFolding ?? false,
      lspInlayHint: settings?.lspInlayHint ?? false,
      lspGoToDefinition: settings?.lspGoToDefinition ?? true,
      lspRename: settings?.lspRename ?? true,
      desktopSelectedIndex: functionPage?.desktopSelectedIndex ?? 0,
      mobileSelectedIndex: functionPage?.mobileSelectedIndex ?? 0,
      tabletSelectedIndex: functionPage?.tabletSelectedIndex ?? 0,
      functionPageShow: functionPage?.functionPageShow ?? true,
      consolePageShow: functionPage?.consolePageShow ?? true,
      expansionPageShow: functionPage?.expansionPageShow ?? true,
      projectPath: project?.projectPath,
      tabs: tabsData?.tabs ?? [],
      selectedTabIndex: tabsData?.selectedTabIndex ?? 0,
      chineseToUnicodeConversion:
          settings?.chineseToUnicodeConversion ?? true,
      enableSignalDetection:
          settings?.enableSignalDetection ?? true,
      serialDefaultBaudRate: settings?.serialDefaultBaudRate ?? 115200,
      serialAutoReconnect: settings?.serialAutoReconnect ?? false,
      terminalFontFamily: settings?.terminalFontFamily ?? 'JetBrains Mono',
      terminalFontSize: settings?.terminalFontSize ?? 13,
      terminalLineHeight: settings?.terminalLineHeight ?? 1.2,
      uploadConfirmStyle:
          settings?.uploadConfirmStyle ?? 'toolbar',
      confirmShortcut:
          settings?.confirmShortcut ?? 'Ctrl+Enter',
      cancelShortcut:
          settings?.cancelShortcut ?? 'Esc',
      webReplHost: settings?.webReplHost ?? '',
      webReplPort: settings?.webReplPort ?? 8266,
      webReplPassword: settings?.webReplPassword ?? '',
      microPythonStubsEnabled: settings?.microPythonStubsEnabled ?? false,
      microPythonStubsAutoDetectLayers:
          settings?.microPythonStubsAutoDetectLayers ?? false,
      microPythonStubsLayers: settings?.microPythonStubsLayers ?? const [],
      microPythonStubsExtraPaths:
          settings?.microPythonStubsExtraPaths ?? const [],
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
          useLsp: container.read(useLsp),
          lspType: container.read(lspType).jsonName,
          lspWebSocketPath: container.read(lspWebSocketPath),
          lspStdioExecutable: container.read(lspStdioExecutable),
          lspStdioArgs: container.read(lspStdioArgs),
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
          lspInlayHint: container.read(lspInlayHint),
          lspGoToDefinition: container.read(lspGoToDefinition),
          lspRename: container.read(lspRename),
          chineseToUnicodeConversion:
              container.read(chineseToUnicodeConversion),
          enableSignalDetection:
              container.read(enableSignalDetection),
          serialDefaultBaudRate: container.read(serialDefaultBaudRate),
          serialAutoReconnect: container.read(serialAutoReconnect),
          terminalFontFamily: container.read(terminalFontFamily),
          terminalFontSize: container.read(terminalFontSize),
          terminalLineHeight: container.read(terminalLineHeight),
          uploadConfirmStyle:
              container.read(uploadConfirmStyleProvider),
          confirmShortcut:
              container.read(confirmShortcutProvider),
          cancelShortcut:
              container.read(cancelShortcutProvider),
          webReplHost: container.read(webReplHost),
          webReplPort: container.read(webReplPort),
          webReplPassword: container.read(webReplPassword),
          microPythonStubsEnabled: container.read(microPythonStubsEnabled),
          microPythonStubsAutoDetectLayers:
              container.read(microPythonStubsAutoDetectLayers),
          microPythonStubsLayers: container.read(microPythonStubsLayers),
          microPythonStubsExtraPaths:
              container.read(microPythonStubsExtraPaths),
        ),
      ),
      functionPagePersistence.save(
        FunctionPagePersistedData(
          desktopSelectedIndex: container.read(desktopSelectedIndex),
          mobileSelectedIndex: container.read(mobileSelectedIndex),
          tabletSelectedIndex: container.read(tabletSelectedIndex),
          functionPageShow: container.read(functionPageShow),
          consolePageShow: container.read(consolePageShow),
          expansionPageShow: container.read(expansionPageShow),
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
    await projectPersistence.save(
      ProjectPersistedData(projectPath: dir?.path),
    );
  }

  Future<void> _saveTabs(ProviderContainer container) async {
    final tabController = container.read(tabbedViewControllerProvider);
    final List<PersistedTab> tabs = [];
    for (final tab in tabController.tabs) {
      final value = tab.value;
      if (value is TabDataValue && value.type == "file") {
        tabs.add(
          PersistedTab(
            filePath: value.filePath,
            isBoardFile: value.isBoardFile ?? false,
            boardFilePath: value.boardFilePath,
            isSaved: value.isSaved,
            unsavedContent: (!value.isSaved && value.editorController != null)
                ? value.editorController!.text
                : null,
          ),
        );
      }
    }
    await tabsPersistence.save(
      TabsPersistedData(
        tabs: tabs,
        selectedTabIndex: tabController.selectedIndex ?? 0,
      ),
    );
  }
}
