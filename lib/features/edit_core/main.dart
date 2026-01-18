import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:pyrite_ide/features/edit_core/editor_autocomplete.dart';

class EditCore extends StatefulWidget {
  const EditCore({super.key, this.filePath});
  final String? filePath;

  @override
  State<StatefulWidget> createState() => _EditCore();
}

class _EditCore extends State<EditCore> with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);
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
                children: [
                  DefaultCodeLineNumber(
                    controller: editingController,
                    notifier: notifier,
                  ),
                  DefaultCodeChunkIndicator(
                    width: 20,
                    controller: chunkController,
                    notifier: notifier,
                  ),
                ],
              );
            },
        controller: CodeLineEditingController(),
        style: CodeEditorStyle(
          codeTheme: CodeHighlightTheme(
            languages: {
              'micropython': CodeHighlightThemeMode(mode: langPython),
            },
            theme: atomOneDarkTheme,
          ),
          fontSize: 15,
          fontFamily: 'JetBrainsMono',
        ),
        wordWrap: false,
      ),
    );
  }

  @override
  // TODO: implement wantKeepAlive
  bool get wantKeepAlive => true;
}
