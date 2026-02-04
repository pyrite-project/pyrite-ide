import 'package:flutter/material.dart';
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
final StateProvider<bool> functionPageState = StateProvider<bool>(
  (ref) => true,
);

List<dynamic> nowNavigationBarItems = desktopRailItems;
StateProvider<int> nowViewSelectedIndex = desktopSelectedIndex;
