import 'dart:io';
import 'dart:async';
import 'package:code_forge/code_forge/code_area.dart';
import 'package:code_forge/code_forge/controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/editor/main.dart';
import 'package:pyrite_ide/core/services/expansion_page.dart';
import 'package:pyrite_ide/core/services/pylsp/data.dart';
import 'package:pyrite_ide/core/services/pylsp/features.dart';
import 'package:pyrite_ide/core/services/pylsp/main.dart';
import 'package:pyrite_ide/core/services/pylsp/hover.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/core/services/pylsp/markdown.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';
import 'package:pyrite_ide/features/edit_core/lsp_completion.dart';
import 'package:tabbed_view/tabbed_view.dart';

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
    final syntaxTheme = Theme.of(context).brightness == Brightness.dark
        ? atomOneDarkTheme
        : atomOneLightTheme;

    return CodeForge(
      filePath: widget.file.path,
      editorTheme: ref.watch(editorThemeMode),
      language: langPython,
      controller: widget.editorController,
      textStyle: TextStyle(
        fontSize: ref.watch(editorFontSize),
        fontFamily: editorTextFonts[ref.watch(editorTextFontProvider)],
      ),
      lineWrap: ref.watch(editorWordWrap),
    );
  }

  List<Widget> buildIndicator(
    BuildContext context,
    CodeLineEditingController editingController,
    CodeChunkController chunkController,
    ValueNotifier<CodeIndicatorValue?> notifier,
    WidgetRef ref,
  ) {
    List<Widget> children = [];
    if (ref.watch(editorLineNumber)) {
      children.add(
        DefaultCodeLineNumber(
          controller: editingController,
          notifier: notifier,
        ),
      );
    }
    children.add(
      DefaultCodeChunkIndicator(
        width: 20,
        controller: chunkController,
        notifier: notifier,
      ),
    );
    return children;
  }
}
