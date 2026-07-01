import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/models/settings.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/file/local_utils.dart' as local;

const Map<String, String> editorTextFonts = {
  "JetBrains Mono": "JetBrainsMono",
  "自定义": "",
};

final StateProvider<String> editorTextFontProvider = StateProvider<String>(
  (ref) => "JetBrains Mono",
);

final ByteData _null = ByteData(0);

Future<ByteData> loadFontData() async {
  File? file = await local.sysGetFile();
  if (file != null) {
    final bytes = await file.readAsBytes();
    return ByteData.sublistView(bytes);
  } else {
    return _null;
  }
}

void customizationEditorTextFont() async {
  Future<ByteData> data = loadFontData();
  ByteData data0 = await data;

  if (data0 != _null) {
    final FontLoader font = FontLoader("自定义");
    font.addFont(data);
    await font.load();
    container.read(editorTextFontProvider.notifier).state = "自定义";
  }
}

StateProvider<double> editorFontSize = StateProvider<double>((ref) => 15);
StateProvider<bool> editorWordWrap = StateProvider<bool>((ref) => false);
StateProvider<bool> editorLineNumber = StateProvider<bool>((ref) => true);
StateProvider<bool> editorCodeFolding = StateProvider<bool>((ref) => true);
StateProvider<bool> editorGuideLines = StateProvider<bool>((ref) => true);
StateProvider<bool> editorLocalSuggestions = StateProvider<bool>((ref) => false);
StateProvider<bool> editorKeyboardSuggestions = StateProvider<bool>((ref) => true);
StateProvider<bool> editorUseSpaceAsTab = StateProvider<bool>((ref) => true);
StateProvider<int> editorTabSize = StateProvider<int>((ref) => 4);
StateProvider<bool> editorGutterDivider = StateProvider<bool>((ref) => false);

StateProvider<bool> useLsp = StateProvider<bool>((ref) => true);
StateProvider<LspType> lspType = StateProvider<LspType>(
  (ref) => LspType.webSocket,
);
StateProvider<String> lspWebSocketPath = StateProvider<String>(
  (ref) => "127.0.0.1:2026",
);
StateProvider<String> lspStdioExecutable = StateProvider<String>(
  (ref) => "",
);
StateProvider<String> lspStdioArgs = StateProvider<String>(
  (ref) => "--stdio",
);
StateProvider<bool> disableWarning = StateProvider<bool>((ref) => false);
StateProvider<bool> disableError = StateProvider<bool>((ref) => false);
StateProvider<bool> lspSemanticHighlighting = StateProvider<bool>((ref) => false);
StateProvider<bool> lspCodeCompletion = StateProvider<bool>((ref) => true);
StateProvider<bool> lspHoverInfo = StateProvider<bool>((ref) => true);
StateProvider<bool> lspCodeAction = StateProvider<bool>((ref) => true);
StateProvider<bool> lspSignatureHelp = StateProvider<bool>((ref) => true);
StateProvider<bool> lspDocumentColor = StateProvider<bool>((ref) => false);
StateProvider<bool> lspDocumentHighlight = StateProvider<bool>((ref) => true);
StateProvider<bool> lspCodeFolding = StateProvider<bool>((ref) => false);
StateProvider<bool> lspInlayHint = StateProvider<bool>((ref) => false);
StateProvider<bool> lspGoToDefinition = StateProvider<bool>((ref) => true);
StateProvider<bool> lspRename = StateProvider<bool>((ref) => true);

StateProvider<bool> chineseToUnicodeConversion = StateProvider<bool>(
  (ref) => true,
);

StateProvider<bool> enableSignalDetection = StateProvider<bool>((ref) => true);
StateProvider<int> serialDefaultBaudRate = StateProvider<int>((ref) => 115200);
StateProvider<bool> serialAutoReconnect = StateProvider<bool>((ref) => false);
StateProvider<String> terminalFontFamily = StateProvider<String>((ref) => "JetBrains Mono");
StateProvider<double> terminalFontSize = StateProvider<double>((ref) => 13);
StateProvider<double> terminalLineHeight = StateProvider<double>((ref) => 1.2);

const Map<String, String> uploadConfirmStyles = {
  "浮动工具栏": "toolbar",
  "确认对话框": "dialog",
};

StateProvider<String> uploadConfirmStyleProvider = StateProvider<String>(
  (ref) => "toolbar",
);

const Map<String, String> defaultShortcuts = {
  'confirm': 'Ctrl+Enter',
  'cancel': 'Esc',
};

StateProvider<String> confirmShortcutProvider = StateProvider<String>(
  (ref) => defaultShortcuts['confirm']!,
);

StateProvider<String> cancelShortcutProvider = StateProvider<String>(
  (ref) => defaultShortcuts['cancel']!,
);

StateProvider<String> webReplHost = StateProvider<String>((ref) => '');
StateProvider<int> webReplPort = StateProvider<int>((ref) => 8266);
StateProvider<String> webReplPassword = StateProvider<String>((ref) => '');
