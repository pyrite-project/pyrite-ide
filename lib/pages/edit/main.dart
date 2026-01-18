import 'package:tabbed_view/tabbed_view.dart';
import 'package:flutter/material.dart';
import 'package:pyrite_ide/pages/edit/app_bar.dart';
import 'package:pyrite_ide/pages/edit/welcome.dart';

class Edit extends StatefulWidget {
  const Edit({super.key});

  @override
  State<StatefulWidget> createState() => _Edit();
}

class _Edit extends State<Edit> {
  final TabbedViewController tabbedViewController = TabbedViewController([
    TabData(
      text: "欢迎",
      content: Welcome(),
      leading: (context, status) => Padding(
        padding: EdgeInsetsGeometry.directional(
          start: 5,
          end: 10,
          top: 5,
          bottom: 5,
        ),
        child: Image.asset(
          "assets/icons/app_icon.png",
          width: 15,
          height: 15,
          color: Theme.of(context).colorScheme.secondary,
        ),
      ),
    ),
  ]);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: editAppBar(),
      body: TabbedViewTheme(
        data: TabbedViewThemeData.minimalist(
          tabRadius: 5,
          colorSet: MaterialColor(
            Theme.of(context).colorScheme.primary.toARGB32(),
            <int, Color>{
              50: Theme.of(context).colorScheme.secondaryContainer,
              100: Theme.of(context).colorScheme.secondary,
              200: Theme.of(context).colorScheme.secondaryContainer,
              300: Theme.of(context).colorScheme.secondaryContainer,
              400: Theme.of(context).colorScheme.secondaryContainer,
              500: Theme.of(context).colorScheme.secondaryContainer,
              600: Theme.of(context).colorScheme.secondaryContainer,
              700: Theme.of(context).colorScheme.secondaryContainer,
              800: Theme.of(context).colorScheme.secondaryContainer,
              900: Theme.of(context).colorScheme.secondaryContainer,
            },
          ),
        ),
        child: TabbedView(controller: tabbedViewController),
      ),
    );
  }
}
