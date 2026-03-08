import 'package:code_forge/code_forge/controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/editor/main.dart';
import 'package:pyrite_ide/core/services/editor/ui.dart';
import 'package:pyrite_ide/core/services/expansion_page.dart';
import 'package:pyrite_ide/core/services/pylsp/data.dart';
import 'package:re_editor/re_editor.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:tabbed_view/tabbed_view.dart' hide TabbedView;
import 'package:pyrite_ide/shared/tabbed_view/tabbed_view.dart';
import 'package:flutter/material.dart';
import 'package:xterm/ui.dart';

class Editor extends ConsumerWidget {
  const Editor({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            IconButton(
              icon: Icon(Icons.undo, size: 20),
              onPressed: () => undoAction(ref),
            ),
            IconButton(
              icon: Icon(Icons.redo, size: 20),
              onPressed: () => redoAction(ref),
            ),
          ],
        ),
        toolbarHeight: 50,
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
      body: body(context, ref),
    );
  }

  Widget body(BuildContext context, WidgetRef ref) {
    return TabbedViewTheme(
      data: TabbedViewThemeData.minimalist(
        tabRadius: 5,
        colorSet: MaterialColor(
          Theme.of(context).colorScheme.primary.toARGB32(),
          <int, Color>{
            50: Theme.of(context).colorScheme.secondaryContainer,
            100: Theme.of(context).colorScheme.onSecondary,
            200: Theme.of(context).colorScheme.secondaryContainer,
            300: Theme.of(context).colorScheme.secondaryContainer,
            400: Theme.of(context).colorScheme.secondaryContainer,
            500: Theme.of(context).colorScheme.secondaryContainer,
            600: Theme.of(context).colorScheme.secondaryContainer,
            700: Theme.of(context).colorScheme.secondaryContainer,
            800: Theme.of(context).colorScheme.secondary,
            900: Theme.of(context).colorScheme.onSecondaryContainer,
          },
        ),
      ),
      child: TabbedView(controller: ref.watch(tabbedViewController)),
    );
  }
}

class ExpansionPage extends ConsumerWidget {
  const ExpansionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            IconButton(
              icon: Icon(Icons.undo, size: 20),
              onPressed: () => undoAction(ref),
            ),
            IconButton(
              icon: Icon(Icons.redo, size: 20),
              onPressed: () => redoAction(ref),
            ),
          ],
        ),
        toolbarHeight: 50,
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
      body: body(context, ref),
    );
  }

  Widget body(BuildContext context, WidgetRef ref) {
    return TabbedViewTheme(
      data: TabbedViewThemeData.minimalist(
        tabRadius: 5,
        colorSet: MaterialColor(
          Theme.of(context).colorScheme.primary.toARGB32(),
          <int, Color>{
            50: Theme.of(context).colorScheme.secondaryContainer,
            100: Theme.of(context).colorScheme.onSecondary,
            200: Theme.of(context).colorScheme.secondaryContainer,
            300: Theme.of(context).colorScheme.secondaryContainer,
            400: Theme.of(context).colorScheme.secondaryContainer,
            500: Theme.of(context).colorScheme.secondaryContainer,
            600: Theme.of(context).colorScheme.secondaryContainer,
            700: Theme.of(context).colorScheme.secondaryContainer,
            800: Theme.of(context).colorScheme.secondary,
            900: Theme.of(context).colorScheme.onSecondaryContainer,
          },
        ),
      ),
      child: TabbedView(controller: ref.watch(expansionViewController)),
    );
  }
}

class ReplView extends StatelessWidget {
  const ReplView({super.key});

  @override
  Widget build(BuildContext context) {
    return TerminalView(repl, controller: replController);
  }
}

class QuestionView extends ConsumerWidget {
  const QuestionView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ScrollConfiguration(
      behavior: NoScrollbarBehavior(),
      child: ListView.builder(
        addAutomaticKeepAlives: false,
        itemCount: ref.watch(diagnostics).length,
        itemBuilder: (context, index) {
          List<DiagnosticItem> nowDiagnostics = ref.watch(diagnostics);
          return ListTile(
            title: Text(nowDiagnostics[index].message),
            subtitle: Text(
              "[行 ${nowDiagnostics[index].range.start["line"] + 1}, 列 ${nowDiagnostics[index].range.start["character"] + 1}]",
            ),
          );
        },
      ),
    );
  }
}
