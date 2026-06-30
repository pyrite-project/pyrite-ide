import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/function_page.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/core/services/persistence/app_persistence.dart';
import 'package:pyrite_ide/core/services/persistence/settings_persistence.dart';
import 'package:pyrite_ide/core/services/persistence/function_page_persistence.dart';
import 'package:pyrite_ide/core/services/persistence/file/project_persistence.dart';
import 'package:pyrite_ide/core/services/persistence/editor/tabs_persistence.dart';
import 'package:pyrite_ide/core/services/persistence/persistence_models.dart';
import 'package:pyrite_ide/core/services/settings.dart';

class PersistenceManager {
  final AppPersistence appPersistence = AppPersistence();
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
      useLsp: settings?.useLsp ?? true,
      lspType: settings?.lspType ?? 'webScoket',
      lspWebSocketPath: settings?.lspWebSocketPath ?? '127.0.0.1:2026',
      lspStdioExecutable: settings?.lspStdioExecutable ?? '',
      lspStdioArgs: settings?.lspStdioArgs ?? '--stdio',
      disableWarning: settings?.disableWarning ?? false,
      disableError: settings?.disableError ?? false,
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
      uploadConfirmStyle:
          settings?.uploadConfirmStyle ?? 'toolbar',
      confirmShortcut:
          settings?.confirmShortcut ?? 'Ctrl+Enter',
      cancelShortcut:
          settings?.cancelShortcut ?? 'Esc',
      webReplHost: settings?.webReplHost ?? '',
      webReplPort: settings?.webReplPort ?? 8266,
      webReplPassword: settings?.webReplPassword ?? '',
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
          useLsp: container.read(useLsp),
          lspType: container.read(lspType).name,
          lspWebSocketPath: container.read(lspWebScoketPath),
          lspStdioExecutable: container.read(lspStdioExecutable),
          lspStdioArgs: container.read(lspStdioArgs),
          disableWarning: container.read(disableWarning),
          disableError: container.read(disableError),
          chineseToUnicodeConversion:
              container.read(chineseToUnicodeConversion),
          enableSignalDetection:
              container.read(enableSignalDetection),
          uploadConfirmStyle:
              container.read(uploadConfirmStyleProvider),
          confirmShortcut:
              container.read(confirmShortcutProvider),
          cancelShortcut:
              container.read(cancelShortcutProvider),
          webReplHost: container.read(webReplHost),
          webReplPort: container.read(webReplPort),
          webReplPassword: container.read(webReplPassword),
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
