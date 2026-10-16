import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/constants/navigation_bar.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';

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

  /// Arrow pointing at the edge the console would move to.
  IconData get icon => switch (this) {
    ConsoleDockSide.left => Icons.arrow_back,
    ConsoleDockSide.top => Icons.arrow_upward,
    ConsoleDockSide.right => Icons.arrow_forward,
    ConsoleDockSide.bottom => Icons.arrow_downward,
  };

  /// Label shown on the drop zone while a dock drag is in flight.
  I18nKey get labelKey => switch (this) {
    ConsoleDockSide.left => I18nKey.consoleDockLeft,
    ConsoleDockSide.top => I18nKey.consoleDockTop,
    ConsoleDockSide.right => I18nKey.consoleDockRight,
    ConsoleDockSide.bottom => I18nKey.consoleDockBottom,
  };
}

final StateProvider<ConsoleDockSide> consoleDockSideProvider =
    StateProvider<ConsoleDockSide>((ref) => ConsoleDockSide.bottom);

final TextEditingController commandEditorController = TextEditingController();
