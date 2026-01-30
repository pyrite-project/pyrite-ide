import 'dart:convert';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/edit.dart';
import 'package:tabbed_view/tabbed_view.dart';
import 'package:flutter/material.dart';
import 'package:pyrite_ide/pages/edit/app_bar.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import 'package:xterm/ui.dart';
import 'package:flutter/foundation.dart';

class Edit extends ConsumerWidget {
  const Edit({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: editAppBar(),
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
      child: TabbedView(controller: tabbedViewController),
    );
  }

  Widget functionPage(BuildContext context) {
    return DefaultTabController(
      length: 1,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TabBar(
                  tabAlignment: TabAlignment.start,
                  tabs: [Tab(text: "REPL", height: 35)],
                  isScrollable: true,
                ),
              ),
            ],
          ),

          Expanded(child: TabBarView(children: [ReplView()])),
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
