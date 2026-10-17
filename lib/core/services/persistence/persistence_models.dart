import 'package:pyrite_ide/core/models/settings.dart';
import 'package:pyrite_ide/core/models/terminal_appearance.dart';

/// A folded region captured for a session, keyed by document lines.
///
/// [children] are nested ranges that were folded before their parent
/// collapsed; restoring them lets the editor re-collapse those children when
/// the parent is unfolded again.
class PersistedFoldRange {
  final int startLine;
  final int endLine;
  final List<PersistedFoldRange> children;

  const PersistedFoldRange({
    required this.startLine,
    required this.endLine,
    this.children = const [],
  });

  Map<String, dynamic> toJson() => {
    'startLine': startLine,
    'endLine': endLine,
    'children': children.map((c) => c.toJson()).toList(),
  };

  factory PersistedFoldRange.fromJson(Map<String, dynamic> json) {
    return PersistedFoldRange(
      startLine: (json['startLine'] as num?)?.toInt() ?? 0,
      endLine: (json['endLine'] as num?)?.toInt() ?? 0,
      children:
          (json['children'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(PersistedFoldRange.fromJson)
              .toList() ??
          const [],
    );
  }
}

class PersistedTab {
  final String filePath;
  final bool isBoardFile;
  final String? boardFilePath;
  final bool isSaved;
  final String? unsavedContent;

  /// Caret offset captured at save time so a reopened tab resumes where the
  /// user left off. Null for sessions written before this field existed, and
  /// clamped on restore when the file shrank while the app was closed.
  final int? cursorOffset;

  /// Zero-based index of the topmost visible line at save time.
  ///
  /// Restoring the viewport by line (not by pixel offset) survives font size
  /// changes and window resizes between sessions. Null for sessions written
  /// before this field existed, and clamped on restore when the file shrank.
  final int? scrollLine;

  /// Folded regions at save time, so a reopened tab collapses the same
  /// regions. Empty for sessions written before this field existed; ranges
  /// that no longer match the restored document are applied best-effort.
  final List<PersistedFoldRange> foldedRanges;

  PersistedTab({
    required this.filePath,
    this.isBoardFile = false,
    this.boardFilePath,
    this.isSaved = true,
    this.unsavedContent,
    this.cursorOffset,
    this.scrollLine,
    this.foldedRanges = const [],
  });

  Map<String, dynamic> toJson() => {
    'filePath': filePath,
    'isBoardFile': isBoardFile,
    'boardFilePath': boardFilePath,
    'isSaved': isSaved,
    'unsavedContent': unsavedContent,
    'cursorOffset': cursorOffset,
    'scrollLine': scrollLine,
    'foldedRanges': foldedRanges.map((f) => f.toJson()).toList(),
  };

  factory PersistedTab.fromJson(Map<String, dynamic> json) => PersistedTab(
    filePath: json['filePath'] as String,
    isBoardFile: json['isBoardFile'] as bool? ?? false,
    boardFilePath: json['boardFilePath'] as String?,
    isSaved: json['isSaved'] as bool? ?? true,
    unsavedContent: json['unsavedContent'] as String?,
    cursorOffset: (json['cursorOffset'] as num?)?.toInt(),
    scrollLine: (json['scrollLine'] as num?)?.toInt(),
    foldedRanges:
        (json['foldedRanges'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .map(PersistedFoldRange.fromJson)
            .toList() ??
        const [],
  );
}

/// One editor group as persisted: its tabs and which of them was selected.
class PersistedEditorGroup {
  final List<PersistedTab> tabs;

  /// File path of the tab selected in this group at save time, resolved the
  /// same way [PersistedTab] selection is: by path, never by index.
  final String? selectedTabPath;

  PersistedEditorGroup({required this.tabs, this.selectedTabPath});

  Map<String, dynamic> toJson() => {
    'tabs': tabs.map((t) => t.toJson()).toList(),
    'selectedTabPath': selectedTabPath,
  };

  factory PersistedEditorGroup.fromJson(Map<String, dynamic> json) =>
      PersistedEditorGroup(
        tabs:
            (json['tabs'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map(PersistedTab.fromJson)
                .toList() ??
            const [],
        selectedTabPath: json['selectedTabPath'] as String?,
      );
}

/// The editor area's layout as persisted.
///
/// A group is a leaf pointing into [TabsPersistedData.groups]; a split holds an
/// axis and its children. The tree is written nested, exactly as it stands, so
/// any number of nested splits restores as it was left.
class PersistedEditorLayout {
  /// Axis of a split node: `horizontal` or `vertical`. Null for a group leaf.
  final String? axis;

  /// Index into [TabsPersistedData.groups] for a group leaf.
  final int? groupIndex;

  /// Children of a split node, empty for a group leaf.
  final List<PersistedEditorLayout> children;

  /// The children's relative sizes, or null for equal shares.
  final List<double>? weights;

  PersistedEditorLayout.split(this.axis, this.children, {this.weights})
    : groupIndex = null;

  PersistedEditorLayout.group(this.groupIndex)
    : axis = null,
      children = const [],
      weights = null;

  bool get isSplit => axis != null;

  Map<String, dynamic> toJson() => {
    if (axis != null) 'axis': axis,
    if (groupIndex != null) 'groupIndex': groupIndex,
    if (isSplit) 'children': children.map((c) => c.toJson()).toList(),
    if (weights != null) 'weights': weights,
  };

  factory PersistedEditorLayout.fromJson(Map<String, dynamic> json) {
    final axis = json['axis'] as String?;
    // A split node carries `axis`; a group leaf carries `groupIndex`. The group
    // index is absent on splits, so the axis is the only reliable discriminant.
    if (axis != null) {
      return PersistedEditorLayout.split(
        axis,
        (json['children'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(PersistedEditorLayout.fromJson)
            .toList(),
        weights: (json['weights'] as List<dynamic>?)
            ?.whereType<num>()
            .map((weight) => weight.toDouble())
            .toList(),
      );
    }
    final groupIndex = (json['groupIndex'] as num?)?.toInt() ?? 0;
    return PersistedEditorLayout.group(groupIndex);
  }
}

class PersistedData {
  final String? projectPath;

  /// The tabs of a session saved with a single editor group.
  final List<PersistedTab> tabs;

  /// One entry per editor group of a split session, in layout order.
  final List<PersistedEditorGroup> tabGroups;

  /// The editor area's layout tree, or null for a single group.
  final PersistedEditorLayout? tabLayout;

  /// Which of [tabGroups] is the primary group.
  final int tabPrimaryGroupIndex;
  final int selectedTabIndex;

  /// File path of the tab that was selected, preferred over [selectedTabIndex]
  /// when restoring because the rebuilt tab list does not share the saved
  /// index space. See `TabsPersistedData.selectedTabPath`.
  final String? selectedTabPath;
  final String themeMode;
  final String themeStyle;
  final int? themeColorValue;
  final String editorThemeKey;
  final String? activePluginThemeId;
  final bool welcomeCompleted;
  final String activeLocale;
  final bool alwaysOnTop;
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
  final bool editorSmoothCursor;
  final bool editorMinimap;
  final bool editorFormatOnSave;
  final bool useLsp;
  final String lspType;
  final String lspWebSocketPath;
  final String lspStdioExecutable;
  final String lspStdioArgs;
  final String lspVirtualEnvironment;
  final String lspBasedPyrightTypeCheckingMode;
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
  final bool lspShowInlayHints;
  final bool lspGoToDefinition;
  final bool lspRename;
  final bool lspAlwaysStart;
  final int desktopSelectedIndex;
  final int mobileSelectedIndex;
  final int tabletSelectedIndex;
  final bool functionPageShow;
  final bool consolePageShow;
  final String consoleDockSide;
  final bool chineseToUnicodeConversion;
  final bool enableSignalDetection;
  final bool ensureBoardFilesystemOnConnect;
  final int serialDefaultBaudRate;
  final bool serialAutoReconnect;
  final String terminalFontFamily;
  final double terminalFontSize;
  final double terminalLineHeight;
  final bool terminalLigatures;
  final String terminalAppearance;
  final bool terminalMinimumContrast;
  final int terminalCustomForeground;
  final int terminalCustomBackground;
  final List<int> terminalCustomPalette;
  final bool useMaterialContextMenu;
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
  final List<DataContributionRecord> dataContributions;
  final String replMode;
  final String fileTransferMode;
  final String hardwareResetStrategy;

  PersistedData({
    this.projectPath,
    this.tabs = const [],
    this.tabGroups = const [],
    this.tabLayout,
    this.tabPrimaryGroupIndex = 0,
    this.selectedTabIndex = 0,
    this.selectedTabPath,
    this.themeMode = 'system',
    this.themeStyle = 'standard',
    this.themeColorValue,
    this.editorThemeKey = 'atom-one',
    this.activePluginThemeId,
    this.welcomeCompleted = false,
    this.activeLocale = 'zh-CN',
    this.alwaysOnTop = false,
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
    this.editorSmoothCursor = false,
    this.editorMinimap = true,
    this.editorFormatOnSave = false,
    this.useLsp = true,
    this.lspType = 'web_socket',
    this.lspWebSocketPath = '127.0.0.1:2026',
    this.lspStdioExecutable = '',
    this.lspStdioArgs = '',
    this.lspVirtualEnvironment = '',
    this.lspBasedPyrightTypeCheckingMode = 'standard',
    this.disableWarning = false,
    this.disableError = false,
    this.lspSemanticHighlighting = true,
    this.lspCodeCompletion = true,
    this.lspHoverInfo = true,
    this.lspCodeAction = true,
    this.lspSignatureHelp = true,
    this.lspDocumentColor = true,
    this.lspDocumentHighlight = true,
    this.lspCodeFolding = true,
    this.lspShowInlayHints = true,
    this.lspGoToDefinition = true,
    this.lspRename = true,
    this.lspAlwaysStart = false,
    this.desktopSelectedIndex = 0,
    this.mobileSelectedIndex = 0,
    this.tabletSelectedIndex = 0,
    this.functionPageShow = true,
    this.consolePageShow = true,
    this.consoleDockSide = 'bottom',
    this.chineseToUnicodeConversion = true,
    this.enableSignalDetection = true,
    this.ensureBoardFilesystemOnConnect = false,
    this.serialDefaultBaudRate = 115200,
    this.serialAutoReconnect = false,
    this.terminalFontFamily = 'JetBrains Maple Mono',
    this.terminalFontSize = 13,
    this.terminalLineHeight = 1.2,
    this.terminalLigatures = true,
    this.terminalAppearance = 'dark',
    this.terminalMinimumContrast = false,
    this.terminalCustomForeground = kDefaultTerminalCustomForeground,
    this.terminalCustomBackground = kDefaultTerminalCustomBackground,
    this.terminalCustomPalette = kDefaultTerminalCustomPalette,
    this.useMaterialContextMenu = false,
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
    this.dataContributions = const [],
    this.replMode = 'rawRepl',
    this.fileTransferMode = 'streaming',
    this.hardwareResetStrategy = 'disabled',
  });
}

class DataContributionRecord {
  const DataContributionRecord({
    required this.pluginId,
    required this.pluginType,
    required this.kind,
    required this.contributionId,
    required this.payload,
    this.enabled = true,
  });

  final String pluginId;
  final String pluginType;
  final String kind;
  final String contributionId;
  final Map<String, dynamic> payload;
  final bool enabled;

  Map<String, dynamic> toJson() => {
    'pluginId': pluginId,
    'pluginType': pluginType,
    'kind': kind,
    'contributionId': contributionId,
    'payload': payload,
    'enabled': enabled,
  };

  factory DataContributionRecord.fromJson(Map<String, dynamic> json) {
    return DataContributionRecord(
      pluginId: json['pluginId']?.toString() ?? '',
      pluginType: json['pluginType']?.toString() ?? '',
      kind: json['kind']?.toString() ?? '',
      contributionId: json['contributionId']?.toString() ?? '',
      payload: Map<String, dynamic>.from(json['payload'] as Map? ?? {}),
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}

class DataContributionKeys {
  static const theme = 'theme';
  static const i18n = 'i18n';
  static const stubs = 'stubs';
  static const lspServer = 'lsp_server';
}
