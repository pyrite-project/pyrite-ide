import 'dart:io';
import 'package:code_forge/code_forge.dart';

class TabDataValue {
  TabDataValue({
    required this.type,
    required this.filePath,
    this.file,
    this.editorController,
    this.undoRedoController,
    this.isBoardFile,
    this.boardFilePath,
    this.isSaved = true,
  });
  final String type;
  final String filePath;
  final File? file;
  final CodeForgeController? editorController;
  final UndoRedoController? undoRedoController;
  final bool? isBoardFile;
  final String? boardFilePath;
  bool isSaved;
}
