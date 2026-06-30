class PersistedTab {
  final String filePath;
  final bool isBoardFile;
  final String? boardFilePath;
  final bool isSaved;
  final String? unsavedContent;

  PersistedTab({
    required this.filePath,
    this.isBoardFile = false,
    this.boardFilePath,
    this.isSaved = true,
    this.unsavedContent,
  });

  Map<String, dynamic> toJson() => {
    'filePath': filePath,
    'isBoardFile': isBoardFile,
    'boardFilePath': boardFilePath,
    'isSaved': isSaved,
    'unsavedContent': unsavedContent,
  };

  factory PersistedTab.fromJson(Map<String, dynamic> json) => PersistedTab(
    filePath: json['filePath'] as String,
    isBoardFile: json['isBoardFile'] as bool? ?? false,
    boardFilePath: json['boardFilePath'] as String?,
    isSaved: json['isSaved'] as bool? ?? true,
    unsavedContent: json['unsavedContent'] as String?,
  );
}

class PersistedData {
  final String? projectPath;
  final List<PersistedTab> tabs;
  final int selectedTabIndex;
  final String themeMode;
  final String themeStyle;
  final int? themeColorValue;
  final String editorThemeKey;
  final String? activePluginThemeId;
  final String editorTextFont;
  final double editorFontSize;
  final bool editorWordWrap;
  final bool editorLineNumber;
  final bool useLsp;
  final String lspType;
  final String lspWebSocketPath;
  final String lspStdioExecutable;
  final String lspStdioArgs;
  final bool disableWarning;
  final bool disableError;
  final int desktopSelectedIndex;
  final int mobileSelectedIndex;
  final int tabletSelectedIndex;
  final bool functionPageShow;
  final bool consolePageShow;
  final bool expansionPageShow;
  final bool chineseToUnicodeConversion;
  final bool enableSignalDetection;
  final String uploadConfirmStyle;
  final String confirmShortcut;
  final String cancelShortcut;

  PersistedData({
    this.projectPath,
    this.tabs = const [],
    this.selectedTabIndex = 0,
    this.themeMode = 'system',
    this.themeStyle = 'standard',
    this.themeColorValue,
    this.editorThemeKey = 'atom-one',
    this.activePluginThemeId,
    this.editorTextFont = 'JetBrains Mono',
    this.editorFontSize = 15,
    this.editorWordWrap = false,
    this.editorLineNumber = true,
    this.useLsp = true,
    this.lspType = 'webScoket',
    this.lspWebSocketPath = '127.0.0.1:2026',
    this.lspStdioExecutable = '',
    this.lspStdioArgs = '--stdio',
    this.disableWarning = false,
    this.disableError = false,
    this.desktopSelectedIndex = 0,
    this.mobileSelectedIndex = 0,
    this.tabletSelectedIndex = 0,
    this.functionPageShow = true,
    this.consolePageShow = true,
    this.expansionPageShow = true,
    this.chineseToUnicodeConversion = true,
    this.enableSignalDetection = true,
    this.uploadConfirmStyle = 'toolbar',
    this.confirmShortcut = 'Ctrl+Enter',
    this.cancelShortcut = 'Esc',
  });
}
