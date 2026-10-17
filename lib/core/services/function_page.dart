import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/constants/navigation_bar.dart';

int selectedIndexValue = 0;
final StateProvider<int> desktopSelectedIndex = StateProvider<int>(
  (ref) => selectedIndexValue,
);
final StateProvider<int> mobileSelectedIndex = StateProvider<int>(
  (ref) => selectedIndexValue,
);
final StateProvider<int> tabletSelectedIndex = StateProvider<int>(
  (ref) => selectedIndexValue,
);

List<dynamic> nowNavigationBarItems = desktopRailItems;
StateProvider<int> nowViewSelectedIndex = desktopSelectedIndex;

final StateProvider<bool> functionPageShow = StateProvider<bool>((ref) => true);
final StateProvider<bool> consolePageShow = StateProvider<bool>((ref) => true);

/// The edge of the workspace the console pane is docked to.
///
/// The console owns a single pane (and keeps its tabs) whichever edge it sits
/// on: docking only changes the split axis and the order of the two panes.
enum ConsoleDockSide {
  left,
  top,
  right,
  bottom;

  /// The axis the workspace splits along while the console sits on this edge.
  Axis get axis => switch (this) {
    ConsoleDockSide.left || ConsoleDockSide.right => Axis.horizontal,
    ConsoleDockSide.top || ConsoleDockSide.bottom => Axis.vertical,
  };

  /// Whether the console pane is laid out before the primary pane.
  bool get consoleFirst => switch (this) {
    ConsoleDockSide.left || ConsoleDockSide.top => true,
    ConsoleDockSide.right || ConsoleDockSide.bottom => false,
  };
}

final StateProvider<ConsoleDockSide> consoleDockSideProvider =
    StateProvider<ConsoleDockSide>((ref) => ConsoleDockSide.bottom);

final TextEditingController commandEditorController = TextEditingController();
