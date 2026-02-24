import 'package:flutter/material.dart';
import 'package:pyrite_ide/shared/studio_text.dart';

const List<Widget> itemsIcons = [
  Icon(Icons.folder),
  Icon(Icons.table_chart),
  Icon(Icons.settings),
];

const List<String> itemsLabel = ["文件", "工具", "设置"];

List<Widget> bottomItems = [
  NavigationDestination(icon: itemsIcons[0], label: itemsLabel[0]),
  NavigationDestination(icon: itemsIcons[1], label: itemsLabel[1]),
  NavigationDestination(icon: itemsIcons[2], label: itemsLabel[2]),
  const NavigationDestination(icon: Icon(Icons.edit_document), label: "编辑器"),
];

List<NavigationRailDestination> tabletRailItems = [
  NavigationRailDestination(icon: itemsIcons[0], label: UseText(itemsLabel[0])),
  NavigationRailDestination(icon: itemsIcons[1], label: UseText(itemsLabel[1])),
  NavigationRailDestination(icon: itemsIcons[2], label: UseText(itemsLabel[2])),
  const NavigationRailDestination(
    icon: Icon(Icons.edit_document),
    label: UseText("编辑器"),
  ),
];

List<NavigationRailDestination> desktopRailItems = [
  NavigationRailDestination(icon: itemsIcons[0], label: UseText(itemsLabel[0])),
  NavigationRailDestination(icon: itemsIcons[1], label: UseText(itemsLabel[1])),
  NavigationRailDestination(icon: itemsIcons[2], label: UseText(itemsLabel[2])),
];
