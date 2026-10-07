import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/models/settings.dart';
import 'package:pyrite_ide/core/models/terminal_appearance.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/file/local_backend.dart' as local;

const Map<String, String> editorTextFonts = {
  "JetBrains Mono": "JetBrainsMono",
  "JetBrains Maple Mono": "JetBrainsMapleMono",
  "custom": "custom",
};

String getFontDisplayName(String name) {
  if (name == "custom") {
    return I18nKey.settingsFontCustom.fallback;
  }
  return name;
}

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
    final FontLoader font = FontLoader("custom");
    font.addFont(data);
    await font.load();
    container.read(editorTextFontProvider.notifier).state = "custom";
  }
}

void customizationTerminalTextFont() async {
  Future<ByteData> data = loadFontData();
  ByteData data0 = await data;

  if (data0 != _null) {
    final FontLoader font = FontLoader("custom");
    font.addFont(data);
    await font.load();
    container.read(terminalFontFamily.notifier).state = "custom";
  }
}

StateProvider<double> editorFontSize = StateProvider<double>((ref) => 15);
StateProvider<bool> editorWordWrap = StateProvider<bool>((ref) => false);
StateProvider<bool> editorLineNumber = StateProvider<bool>((ref) => true);
StateProvider<bool> editorCodeFolding = StateProvider<bool>((ref) => true);
StateProvider<bool> editorGuideLines = StateProvider<bool>((ref) => true);
StateProvider<bool> editorLocalSuggestions = StateProvider<bool>(
  (ref) => false,
);
StateProvider<bool> editorKeyboardSuggestions = StateProvider<bool>(
  (ref) => true,
);
StateProvider<bool> editorUseSpaceAsTab = StateProvider<bool>((ref) => true);
StateProvider<int> editorTabSize = StateProvider<int>((ref) => 4);
StateProvider<bool> editorGutterDivider = StateProvider<bool>((ref) => false);
StateProvider<bool> editorSmoothCursor = StateProvider<bool>((ref) => false);
StateProvider<bool> editorMinimap = StateProvider<bool>((ref) => true);
StateProvider<bool> editorFormatOnSave = StateProvider<bool>((ref) => false);

StateProvider<bool> useLsp = StateProvider<bool>((ref) => true);
StateProvider<LspType> lspType = StateProvider<LspType>(
  (ref) => LspType.webSocket,
);
StateProvider<String> lspWebSocketPath = StateProvider<String>(
  (ref) => "127.0.0.1:2026",
);
StateProvider<String> lspStdioExecutable = StateProvider<String>((ref) => "");
StateProvider<String> lspStdioArgs = StateProvider<String>((ref) => "");
StateProvider<String> lspVirtualEnvironment = StateProvider<String>(
  (ref) => "",
);
StateProvider<BasedPyrightTypeCheckingMode> lspBasedPyrightTypeCheckingMode =
    StateProvider<BasedPyrightTypeCheckingMode>(
      (ref) => BasedPyrightTypeCheckingMode.standard,
    );
StateProvider<bool> disableWarning = StateProvider<bool>((ref) => false);
StateProvider<bool> disableError = StateProvider<bool>((ref) => false);
StateProvider<bool> lspSemanticHighlighting = StateProvider<bool>(
  (ref) => true,
);
StateProvider<bool> lspCodeCompletion = StateProvider<bool>((ref) => true);
StateProvider<bool> lspHoverInfo = StateProvider<bool>((ref) => true);
StateProvider<bool> lspCodeAction = StateProvider<bool>((ref) => true);
StateProvider<bool> lspSignatureHelp = StateProvider<bool>((ref) => true);
StateProvider<bool> lspDocumentColor = StateProvider<bool>((ref) => true);
StateProvider<bool> lspDocumentHighlight = StateProvider<bool>((ref) => true);
StateProvider<bool> lspCodeFolding = StateProvider<bool>((ref) => true);
StateProvider<bool> lspShowInlayHints = StateProvider<bool>((ref) => true);
StateProvider<bool> lspGoToDefinition = StateProvider<bool>((ref) => true);
StateProvider<bool> lspRename = StateProvider<bool>((ref) => true);
// Not a capability: it decides which files get a server at all, so it stays off
// and the language server only starts for .py files until the user opts in.
StateProvider<bool> lspAlwaysStart = StateProvider<bool>((ref) => false);

/// The LSP client capabilities exposed as switches on the LSP settings page.
///
/// [EditorControllerMapNotifier] subscribes to this list so a flip reaches the
/// language servers that are already running. A capability is only ever read
/// out of these providers when a workspace's server is created, so a switch
/// missing from this list is one that only ever applies to servers started
/// later.
final List<StateProvider<bool>> lspCapabilityProviders = [
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
];

StateProvider<bool> chineseToUnicodeConversion = StateProvider<bool>(
  (ref) => true,
);

StateProvider<bool> enableSignalDetection = StateProvider<bool>((ref) => true);
StateProvider<bool> ensureBoardFilesystemOnConnect = StateProvider<bool>(
  (ref) => false,
);
StateProvider<int> serialDefaultBaudRate = StateProvider<int>((ref) => 115200);
StateProvider<bool> serialAutoReconnect = StateProvider<bool>((ref) => false);
StateProvider<String> terminalFontFamily = StateProvider<String>(
  (ref) => "JetBrains Maple Mono",
);
StateProvider<double> terminalFontSize = StateProvider<double>((ref) => 13);
StateProvider<double> terminalLineHeight = StateProvider<double>((ref) => 1.3);
StateProvider<bool> terminalLigatures = StateProvider<bool>((ref) => true);

StateProvider<TerminalAppearance> terminalAppearance =
    StateProvider<TerminalAppearance>((ref) => TerminalAppearance.dark);
StateProvider<bool> terminalMinimumContrast = StateProvider<bool>(
  (ref) => false,
);
StateProvider<int> terminalCustomForeground = StateProvider<int>(
  (ref) => kDefaultTerminalCustomForeground,
);
StateProvider<int> terminalCustomBackground = StateProvider<int>(
  (ref) => kDefaultTerminalCustomBackground,
);
StateProvider<List<int>> terminalCustomPalette = StateProvider<List<int>>(
  (ref) => kDefaultTerminalCustomPalette,
);

StateProvider<bool> useMaterialContextMenu = StateProvider<bool>(
  (ref) => false,
);

const Map<String, String> uploadConfirmStyles = {
  "toolbar": "toolbar",
  "dialog": "dialog",
};

String getUploadConfirmStyleDisplayName(String key) {
  switch (key) {
    case "toolbar":
      return I18nKey.settingsUploadConfirmToolbar.fallback;
    case "dialog":
      return I18nKey.settingsUploadConfirmDialog.fallback;
    default:
      return key;
  }
}

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

StateProvider<bool> microPythonStubsEnabled = StateProvider<bool>(
  (ref) => false,
);
StateProvider<bool> microPythonStubsAutoDetectLayers = StateProvider<bool>(
  (ref) => false,
);
StateProvider<List<MicroPythonStubsLayer>> microPythonStubsLayers =
    StateProvider<List<MicroPythonStubsLayer>>((ref) => const []);
StateProvider<List<String>> microPythonStubsExtraPaths =
    StateProvider<List<String>>((ref) => const []);
