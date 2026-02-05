import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/edit.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:pyrite_ide/features/edit_core/editor_autocomplete.dart';

class EditCore extends ConsumerWidget {
  const EditCore({
    super.key,
    required this.file,
    required this.editorController,
  });
  final File file;
  final CodeLineEditingController editorController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CodeAutocomplete(
      viewBuilder: (context, notifier, onSelected) {
        return DefaultCodeAutocompleteListView(
          notifier: notifier,
          onSelected: onSelected,
        );
      },
      promptsBuilder: DefaultCodeAutocompletePromptsBuilder(
        language: langPython,
      ),
      child: CodeEditor(
        indicatorBuilder:
            (context, editingController, chunkController, notifier) {
              return Row(
                children: buildIndicator(
                  context,
                  editingController,
                  chunkController,
                  notifier,
                  ref,
                ),
              );
            },
        controller: editorController,
        style: CodeEditorStyle(
          codeTheme: CodeHighlightTheme(
            languages: {
              'micropython': CodeHighlightThemeMode(mode: langPython),
            },
            theme: atomOneDarkTheme,
          ),
          fontSize: ref.watch(editorFontSize),
          fontFamily: editorTextFonts[ref.watch(editorTextFontProvider)],
        ),
        wordWrap: ref.watch(editorWordWrap),
      ),
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
