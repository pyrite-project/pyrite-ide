import 'package:pyrite_ide/core/models/settings.dart';

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
  final bool editorCodeFolding;
  final bool editorGuideLines;
  final bool editorLocalSuggestions;
  final bool editorKeyboardSuggestions;
  final bool editorUseSpaceAsTab;
  final int editorTabSize;
  final bool editorGutterDivider;
  final bool useLsp;
  final String lspType;
  final String lspWebSocketPath;
  final String lspStdioExecutable;
  final String lspStdioArgs;
  final bool disableWarning;
  final bool disableError;
  final bool lspSemanticHighlighting;
  final bool lspCodeCompletion;
  final bool lspHoverInfo;
  final bool lspCodeAction;
  final bool lspSignatureHelp;
  final bool lspDocumentColor;
  final bool lspDocumentHighlight;
  final bool lspCodeFolding;
  final bool lspInlayHint;
  final bool lspGoToDefinition;
  final bool lspRename;
  final int desktopSelectedIndex;
  final int mobileSelectedIndex;
  final int tabletSelectedIndex;
  final bool functionPageShow;
  final bool consolePageShow;
  final bool expansionPageShow;
  final bool chineseToUnicodeConversion;
  final bool enableSignalDetection;
  final int serialDefaultBaudRate;
  final bool serialAutoReconnect;
  final String terminalFontFamily;
  final double terminalFontSize;
  final double terminalLineHeight;
  final String uploadConfirmStyle;
  final String confirmShortcut;
  final String cancelShortcut;
  final String webReplHost;
  final int webReplPort;
  final String webReplPassword;
  final bool microPythonStubsEnabled;
  final bool microPythonStubsAutoDetectLayers;
  final List<MicroPythonStubsLayer> microPythonStubsLayers;
  final List<String> microPythonStubsExtraPaths;

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
    this.editorCodeFolding = true,
    this.editorGuideLines = true,
    this.editorLocalSuggestions = false,
    this.editorKeyboardSuggestions = true,
    this.editorUseSpaceAsTab = true,
    this.editorTabSize = 4,
    this.editorGutterDivider = false,
    this.useLsp = true,
    this.lspType = 'web_socket',
    this.lspWebSocketPath = '127.0.0.1:2026',
    this.lspStdioExecutable = '',
    this.lspStdioArgs = '--stdio',
    this.disableWarning = false,
    this.disableError = false,
    this.lspSemanticHighlighting = false,
    this.lspCodeCompletion = true,
    this.lspHoverInfo = true,
    this.lspCodeAction = true,
    this.lspSignatureHelp = true,
    this.lspDocumentColor = false,
    this.lspDocumentHighlight = true,
    this.lspCodeFolding = false,
    this.lspInlayHint = false,
    this.lspGoToDefinition = true,
    this.lspRename = true,
    this.desktopSelectedIndex = 0,
    this.mobileSelectedIndex = 0,
    this.tabletSelectedIndex = 0,
    this.functionPageShow = true,
    this.consolePageShow = true,
    this.expansionPageShow = true,
    this.chineseToUnicodeConversion = true,
    this.enableSignalDetection = true,
    this.serialDefaultBaudRate = 115200,
    this.serialAutoReconnect = false,
    this.terminalFontFamily = 'JetBrains Mono',
    this.terminalFontSize = 13,
    this.terminalLineHeight = 1.2,
    this.uploadConfirmStyle = 'toolbar',
    this.confirmShortcut = 'Ctrl+Enter',
    this.cancelShortcut = 'Esc',
    this.webReplHost = '',
    this.webReplPort = 8266,
    this.webReplPassword = '',
    this.microPythonStubsEnabled = false,
    this.microPythonStubsAutoDetectLayers = false,
    this.microPythonStubsLayers = const [],
    this.microPythonStubsExtraPaths = const [],
  });
}
