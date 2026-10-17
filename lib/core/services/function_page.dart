import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/constants/navigation_bar.dart';
import 'package:pyrite_ide/core/models/pane_edge.dart';

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

/// The edge of the workspace the console panel is docked to.
///
/// The console owns a single pane (and keeps its tabs) whichever edge it sits
/// on: docking only changes the split axis and the order of the two panes.
final StateProvider<PaneEdge> consoleDockSideProvider = StateProvider<PaneEdge>(
  (ref) => PaneEdge.bottom,
);

final TextEditingController commandEditorController = TextEditingController();
