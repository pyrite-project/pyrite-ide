import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/file.dart';

const Map<String, String> editorTextFonts = {
  "JetBrains Mono": "JetBrainsMono",
  "自定义": "",
};

final StateProvider<String> editorTextFontProvider = StateProvider<String>(
  (ref) => "JetBrains Mono",
);

final ByteData _null = ByteData(0);

Future<ByteData> loadFontData() async {
  File? file = await getFile();
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
  String pattern;

  if (Platform.isWindows) {
    pattern = "\\";
  } else {
    pattern = "/";
  }

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
