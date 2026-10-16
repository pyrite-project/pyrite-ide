import 'package:flutter/material.dart';
import 'package:tabbed_view/tabbed_view.dart';

/// The underline theme shared by every tab strip in the IDE.
///
/// The editor strip and the console strip have to render identically: a tab can
/// be dragged from one to the other, so a different theme would make the same
/// tab change appearance in the middle of the drag.
TabbedViewThemeData buildTabStripTheme(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return TabbedViewThemeData.underline(
    colorSet: MaterialColor(scheme.primary.toARGB32(), <int, Color>{
      50: scheme.surface,
      400: scheme.secondaryContainer,
      500: scheme.surface,
      700: scheme.secondary,
      900: scheme.onSecondaryContainer,
    }),
    underlineColorSet: MaterialColor(scheme.primary.toARGB32(), <int, Color>{}),
  );
}
