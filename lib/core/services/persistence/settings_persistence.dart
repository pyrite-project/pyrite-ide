import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pyrite_ide/core/models/settings.dart';

class SettingsPersistedData {
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
  final bool chineseToUnicodeConversion;
  final bool enableSignalDetection;
  final int serialDefaultBaudRate;
  final bool serialAutoReconnect;
  final String terminalFontFamily;
  final double terminalFontSize;
  final double terminalLineHeight;
  final bool desktopTerminalEnableUnderline;
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

  SettingsPersistedData({
    required this.editorTextFont,
    required this.editorFontSize,
    required this.editorWordWrap,
    required this.editorLineNumber,
    this.editorCodeFolding = true,
    this.editorGuideLines = true,
    this.editorLocalSuggestions = false,
    this.editorKeyboardSuggestions = true,
    this.editorUseSpaceAsTab = true,
    this.editorTabSize = 4,
    this.editorGutterDivider = false,
    required this.useLsp,
    this.lspType = 'web_socket',
    required this.lspWebSocketPath,
    this.lspStdioExecutable = '',
    this.lspStdioArgs = '--stdio',
    required this.disableWarning,
    required this.disableError,
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
    this.chineseToUnicodeConversion = true,
    this.enableSignalDetection = true,
    this.serialDefaultBaudRate = 115200,
    this.serialAutoReconnect = false,
    this.terminalFontFamily = 'JetBrains Mono',
    this.terminalFontSize = 13,
    this.terminalLineHeight = 1.2,
    this.desktopTerminalEnableUnderline = false,
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

  Map<String, dynamic> toJson() => {
    'editorTextFont': editorTextFont,
    'editorFontSize': editorFontSize,
    'editorWordWrap': editorWordWrap,
    'editorLineNumber': editorLineNumber,
    'editorCodeFolding': editorCodeFolding,
    'editorGuideLines': editorGuideLines,
    'editorLocalSuggestions': editorLocalSuggestions,
    'editorKeyboardSuggestions': editorKeyboardSuggestions,
    'editorUseSpaceAsTab': editorUseSpaceAsTab,
    'editorTabSize': editorTabSize,
    'editorGutterDivider': editorGutterDivider,
    'useLsp': useLsp,
    'lspType': lspType,
    'lspWebSocketPath': lspWebSocketPath,
    'lspStdioExecutable': lspStdioExecutable,
    'lspStdioArgs': lspStdioArgs,
    'disableWarning': disableWarning,
    'disableError': disableError,
    'lspSemanticHighlighting': lspSemanticHighlighting,
    'lspCodeCompletion': lspCodeCompletion,
    'lspHoverInfo': lspHoverInfo,
    'lspCodeAction': lspCodeAction,
    'lspSignatureHelp': lspSignatureHelp,
    'lspDocumentColor': lspDocumentColor,
    'lspDocumentHighlight': lspDocumentHighlight,
    'lspCodeFolding': lspCodeFolding,
    'lspInlayHint': lspInlayHint,
    'lspGoToDefinition': lspGoToDefinition,
    'lspRename': lspRename,
    'chineseToUnicodeConversion': chineseToUnicodeConversion,
    'enableSignalDetection': enableSignalDetection,
    'serialDefaultBaudRate': serialDefaultBaudRate,
    'serialAutoReconnect': serialAutoReconnect,
    'terminalFontFamily': terminalFontFamily,
    'terminalFontSize': terminalFontSize,
    'terminalLineHeight': terminalLineHeight,
    'desktopTerminalEnableUnderline': desktopTerminalEnableUnderline,
    'uploadConfirmStyle': uploadConfirmStyle,
    'confirmShortcut': confirmShortcut,
    'cancelShortcut': cancelShortcut,
    'webReplHost': webReplHost,
    'webReplPort': webReplPort,
    'webReplPassword': webReplPassword,
    'microPythonStubsEnabled': microPythonStubsEnabled,
    'microPythonStubsAutoDetectLayers': microPythonStubsAutoDetectLayers,
    'microPythonStubsLayers': microPythonStubsLayers
        .map((layer) => layer.toJson())
        .toList(),
    'microPythonStubsExtraPaths': microPythonStubsExtraPaths,
  };

  factory SettingsPersistedData.fromJson(
    Map<String, dynamic> json,
  ) => SettingsPersistedData(
    editorTextFont: json['editorTextFont'] as String? ?? 'JetBrains Mono',
    editorFontSize: (json['editorFontSize'] as num?)?.toDouble() ?? 15,
    editorWordWrap: json['editorWordWrap'] as bool? ?? false,
    editorLineNumber: json['editorLineNumber'] as bool? ?? true,
    editorCodeFolding: json['editorCodeFolding'] as bool? ?? true,
    editorGuideLines: json['editorGuideLines'] as bool? ?? true,
    editorLocalSuggestions: json['editorLocalSuggestions'] as bool? ?? false,
    editorKeyboardSuggestions:
        json['editorKeyboardSuggestions'] as bool? ?? true,
    editorUseSpaceAsTab: json['editorUseSpaceAsTab'] as bool? ?? true,
    editorTabSize: json['editorTabSize'] as int? ?? 4,
    editorGutterDivider: json['editorGutterDivider'] as bool? ?? false,
    useLsp: json['useLsp'] as bool? ?? true,
    lspType: json['lspType'] as String? ?? 'web_socket',
    lspWebSocketPath: json['lspWebSocketPath'] as String? ?? '127.0.0.1:2026',
    lspStdioExecutable: json['lspStdioExecutable'] as String? ?? '',
    lspStdioArgs: json['lspStdioArgs'] as String? ?? '--stdio',
    disableWarning: json['disableWarning'] as bool? ?? false,
    disableError: json['disableError'] as bool? ?? false,
    lspSemanticHighlighting: json['lspSemanticHighlighting'] as bool? ?? false,
    lspCodeCompletion: json['lspCodeCompletion'] as bool? ?? true,
    lspHoverInfo: json['lspHoverInfo'] as bool? ?? true,
    lspCodeAction: json['lspCodeAction'] as bool? ?? true,
    lspSignatureHelp: json['lspSignatureHelp'] as bool? ?? true,
    lspDocumentColor: json['lspDocumentColor'] as bool? ?? false,
    lspDocumentHighlight: json['lspDocumentHighlight'] as bool? ?? true,
    lspCodeFolding: json['lspCodeFolding'] as bool? ?? false,
    lspInlayHint: json['lspInlayHint'] as bool? ?? false,
    lspGoToDefinition: json['lspGoToDefinition'] as bool? ?? true,
    lspRename: json['lspRename'] as bool? ?? true,
    chineseToUnicodeConversion:
        json['chineseToUnicodeConversion'] as bool? ?? true,
    enableSignalDetection: json['enableSignalDetection'] as bool? ?? true,
    serialDefaultBaudRate: json['serialDefaultBaudRate'] as int? ?? 115200,
    serialAutoReconnect: json['serialAutoReconnect'] as bool? ?? false,
    terminalFontFamily:
        json['terminalFontFamily'] as String? ?? 'JetBrains Mono',
    terminalFontSize: (json['terminalFontSize'] as num?)?.toDouble() ?? 13,
    terminalLineHeight: (json['terminalLineHeight'] as num?)?.toDouble() ?? 1.2,
    desktopTerminalEnableUnderline:
        json['desktopTerminalEnableUnderline'] as bool? ?? false,
    uploadConfirmStyle: json['uploadConfirmStyle'] as String? ?? 'toolbar',
    confirmShortcut: json['confirmShortcut'] as String? ?? 'Ctrl+Enter',
    cancelShortcut: json['cancelShortcut'] as String? ?? 'Esc',
    webReplHost: json['webReplHost'] as String? ?? '',
    webReplPort: json['webReplPort'] as int? ?? 8266,
    webReplPassword: json['webReplPassword'] as String? ?? '',
    microPythonStubsEnabled: json['microPythonStubsEnabled'] as bool? ?? false,
    microPythonStubsAutoDetectLayers:
        json['microPythonStubsAutoDetectLayers'] as bool? ?? false,
    microPythonStubsLayers: (json['microPythonStubsLayers'] as List? ?? [])
        .whereType<Map>()
        .map(
          (item) =>
              MicroPythonStubsLayer.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(),
    microPythonStubsExtraPaths:
        (json['microPythonStubsExtraPaths'] as List? ?? [])
            .map((item) => item.toString())
            .toList(),
  );
}

class SettingsPersistence {
  static const _fileName = 'settings.json';

  Future<File> get _file async {
    final dir = await getApplicationSupportDirectory();
    final subDir = Directory('${dir.path}/data');
    if (!await subDir.exists()) await subDir.create(recursive: true);
    return File('${subDir.path}/$_fileName');
  }

  Future<SettingsPersistedData?> load() async {
    try {
      final file = await _file;
      if (!await file.exists()) return null;
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return SettingsPersistedData.fromJson(json);
    } catch (e) {
      debugPrint('SettingsPersistence: Failed to load: $e');
      return null;
    }
  }

  Future<void> save(SettingsPersistedData data) async {
    try {
      final file = await _file;
      await file.writeAsString(jsonEncode(data.toJson()));
    } catch (e) {
      debugPrint('SettingsPersistence: Failed to save: $e');
    }
  }
}
