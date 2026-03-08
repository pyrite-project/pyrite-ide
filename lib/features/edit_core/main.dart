import 'dart:io';
import 'package:code_forge/code_forge/code_area.dart';
import 'package:code_forge/code_forge/controller.dart';
import 'package:code_forge/code_forge/styling.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:re_highlight/languages/python.dart';

class EditCore extends ConsumerStatefulWidget {
  const EditCore({
    super.key,
    required this.file,
    required this.editorController,
  });
  final File file;
  final CodeForgeController editorController;

  @override
  ConsumerState<EditCore> createState() => _EditCoreState();
}

class _EditCoreState extends ConsumerState<EditCore> {
  @override
  Widget build(BuildContext context) {
    final theme = Map.of(ref.watch(editorThemeMode));
    theme["root"] = TextStyle(
      color: theme["root"]?.color,
      backgroundColor: theme["root"]?.backgroundColor?.withAlpha(225),
    );

    return CodeForge(
      filePath: widget.file.path,
      editorTheme: theme,
      language: langPython,
      controller: widget.editorController,
      matchHighlightStyle: const MatchHighlightStyle(
        currentMatchStyle: TextStyle(backgroundColor: Color(0xFFFFA726)),
        otherMatchStyle: TextStyle(backgroundColor: Color(0x55FFFF00)),
      ),
      textStyle: TextStyle(
        fontSize: ref.watch(editorFontSize),
        fontFamily: editorTextFonts[ref.watch(editorTextFontProvider)],
      ),
      lineWrap: ref.watch(editorWordWrap),
    );
  }
}
