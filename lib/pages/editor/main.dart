import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/editor/main.dart';
import 'package:pyrite_ide/core/services/editor/ui.dart';
import 'package:pyrite_ide/core/services/expansion_page.dart';
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
