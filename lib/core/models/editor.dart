import 'dart:io';
import 'package:code_forge/code_forge/controller.dart';

class TabDataValue {
  const TabDataValue({
    required this.type,
    required this.filePath,
    this.file,
    this.editorController,
    this.isBoardFile,
    this.isSaved = true,
  });
  final String type;
  final String filePath;
  final File? file;
  final CodeForgeController? editorController;
  final bool? isBoardFile;
  final bool isSaved;
}
