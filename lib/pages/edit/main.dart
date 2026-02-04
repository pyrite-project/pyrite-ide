import 'dart:convert';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/edit.dart';
import 'package:pyrite_ide/core/services/pylsp/core.dart';
import 'package:pyrite_ide/core/services/pylsp/data.dart';
import 'package:pyrite_ide/core/services/pylsp/main.dart';
import 'package:re_editor/re_editor.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:tabbed_view/tabbed_view.dart' hide TabbedView;
import 'package:pyrite_ide/shared/tabbed_view/tabbed_view.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import 'package:xterm/ui.dart';

class Edit extends ConsumerWidget {
  const Edit({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            IconButton(
              icon: Icon(Icons.undo, size: 20),
              onPressed: () {
                if (ref.read(tabbedViewController).selectedTab != null &&
                    ref.read(tabbedViewController).selectedTab!.value["type"] ==
                        "file") {
                  CodeLineEditingController editorController = ref
                      .read(tabbedViewController)
                      .selectedTab!
                      .value["editor_controller"];
                  editorController.undo();
                }
              },
            ),
            IconButton(
              icon: Icon(Icons.redo, size: 20),
              onPressed: () {
                if (ref.read(tabbedViewController).selectedTab != null &&
                    ref.read(tabbedViewController).selectedTab!.value["type"] ==
                        "file") {
                  CodeLineEditingController editorController = ref
                      .read(tabbedViewController)
                      .selectedTab!
                      .value["editor_controller"];
                  editorController.redo();
                }
              },
            ),
          ],
        ),
        toolbarHeight: 50,
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
      body: shadcn.ShadcnLayer(
        theme: shadcn.ThemeData(
          colorScheme: Theme.of(context).brightness == Brightness.light
              ? shadcn.ColorSchemes.lightDefaultColor
              : shadcn.ColorSchemes.darkDefaultColor,
        ),
        child: shadcn.ResizablePanel.vertical(
          draggerBuilder: (context) {
            return shadcn.HorizontalResizableDragger();
          },
          children: [
            shadcn.ResizablePane.flex(
              initialFlex: 2,
              minSize: 50,
              child: body(context, ref),
            ),
            shadcn.ResizablePane.flex(
              initialFlex: 2,
              minSize: 10,
              child: functionPage(context),
            ),
          ],
        ),
      ),
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

  Widget functionPage(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TabBar(
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    Tab(text: "REPL", height: 35),
                    Tab(text: "问题", height: 35),
                  ],
                  isScrollable: true,
                ),
              ),
            ],
          ),

          Expanded(child: TabBarView(children: [ReplView(), QuestionView()])),
        ],
      ),
    );
  }
}

class ReplView extends StatelessWidget {
  const ReplView({super.key});

  @override
  Widget build(BuildContext context) {
    return TerminalView(terminal);
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
