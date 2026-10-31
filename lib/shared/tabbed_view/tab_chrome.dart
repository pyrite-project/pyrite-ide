import 'package:flutter/widgets.dart';
import 'package:super_context_menu/super_context_menu.dart';

/// Strip chrome a tab brings along, implemented by the tab's value.
///
/// The chrome travels with the tab: whichever strip hosts it -- the console
/// panel or an editor group -- shows this tab's menu on a right-click and its
/// actions at the strip's trailing edge while the tab is selected. The shared
/// strip only knows this interface, never the feature behind it.
abstract interface class TabChrome {
  /// The tab's context menu, or null for none.
  Menu? buildTabMenu(BuildContext context);

  /// Buttons for the strip's trailing edge while the tab is selected, or null
  /// for none.
  Widget? buildTabActions(BuildContext context);
}
