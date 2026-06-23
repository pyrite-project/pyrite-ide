import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

StateProvider<bool> useLsp = StateProvider<bool>((ref) => true);
StateProvider<String> lspWebScoketPath = StateProvider<String>(
  (ref) => "127.0.0.1:2026",
);
StateProvider<bool> disableWarning = StateProvider<bool>((ref) => false);
StateProvider<bool> disableError = StateProvider<bool>((ref) => false);

StateProvider<bool> chineseToUnicodeConversion = StateProvider<bool>(
  (ref) => true,
);

StateProvider<bool> enableSignalDetection = StateProvider<bool>(
  (ref) => true,
);

const Map<String, String> uploadConfirmStyles = {
  "浮动工具栏": "toolbar",
  "确认对话框": "dialog",
};

StateProvider<String> uploadConfirmStyleProvider = StateProvider<String>(
  (ref) => "toolbar",
);
