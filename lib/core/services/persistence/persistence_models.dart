class PersistedTab {
  final String filePath;
  final bool isBoardFile;
  final bool isSaved;
  final String? unsavedContent;

  PersistedTab({
    required this.filePath,
    this.isBoardFile = false,
    this.isSaved = true,
    this.unsavedContent,
  });

  Map<String, dynamic> toJson() => {
    'filePath': filePath,
    'isBoardFile': isBoardFile,
    'isSaved': isSaved,
    'unsavedContent': unsavedContent,
  };

  factory PersistedTab.fromJson(Map<String, dynamic> json) => PersistedTab(
    filePath: json['filePath'] as String,
    isBoardFile: json['isBoardFile'] as bool? ?? false,
    isSaved: json['isSaved'] as bool? ?? true,
    unsavedContent: json['unsavedContent'] as String?,
  );
}

class PersistedData {
  final String? workspacePath;
  final List<PersistedTab> tabs;
  final int selectedTabIndex;
  final String themeMode;
  final String themeStyle;
  final int? themeColorValue;
  final String editorTextFont;
  final double editorFontSize;
  final bool editorWordWrap;
  final bool editorLineNumber;
  final bool useLsp;
  final String lspWebSocketPath;
  final bool disableWarning;
  final bool disableError;
  final int desktopSelectedIndex;
  final int mobileSelectedIndex;
  final int tabletSelectedIndex;
  final bool functionPageShow;
  final bool consolePageShow;
  final bool expansionPageShow;

  PersistedData({
    this.workspacePath,
    this.tabs = const [],
    this.selectedTabIndex = 0,
    this.themeMode = 'system',
    this.themeStyle = 'standard',
    this.themeColorValue,
    this.editorTextFont = 'JetBrains Mono',
    this.editorFontSize = 15,
    this.editorWordWrap = false,
    this.editorLineNumber = true,
    this.useLsp = true,
    this.lspWebSocketPath = '127.0.0.1:2026',
    this.disableWarning = false,
    this.disableError = false,
    this.desktopSelectedIndex = 0,
    this.mobileSelectedIndex = 0,
    this.tabletSelectedIndex = 0,
    this.functionPageShow = true,
    this.consolePageShow = true,
    this.expansionPageShow = true,
  });
}
