import 'package:flutter/material.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/shared/studio_text.dart';

const List<Widget> itemsIcons = [
  Icon(Icons.folder_outlined),
  Icon(Icons.developer_board_outlined),
  Icon(Icons.account_tree_outlined),
  Icon(Icons.apps_outlined),
  Icon(Icons.settings_outlined),
];

const List<Widget> selectedItemsIcons = [
  Icon(Icons.folder),
  Icon(Icons.developer_board),
  Icon(Icons.account_tree),
  Icon(Icons.apps),
  Icon(Icons.settings),
];

const List<I18nKey> itemsLabel = [
  I18nKey.navFiles,
  I18nKey.navDevices,
  I18nKey.navGit,
  I18nKey.navPlugins,
  I18nKey.navSettings,
];

List<Widget> bottomItems = [
  NavigationDestination(
    icon: itemsIcons[0],
    selectedIcon: selectedItemsIcons[0],
    label: itemsLabel[0].fallback,
  ),
  NavigationDestination(
    icon: itemsIcons[1],
    selectedIcon: selectedItemsIcons[1],
    label: itemsLabel[1].fallback,
  ),
  NavigationDestination(
    icon: itemsIcons[2],
    selectedIcon: selectedItemsIcons[2],
    label: itemsLabel[2].fallback,
  ),
  NavigationDestination(
    icon: itemsIcons[3],
    selectedIcon: selectedItemsIcons[3],
    label: itemsLabel[3].fallback,
  ),
  NavigationDestination(
    icon: itemsIcons[4],
    selectedIcon: selectedItemsIcons[4],
    label: itemsLabel[4].fallback,
  ),
  NavigationDestination(
    icon: const Icon(Icons.note_alt_outlined),
    selectedIcon: const Icon(Icons.edit_document),
    label: I18nKey.navEditor.fallback,
  ),
];

List<Widget> drawerItems = [
  NavigationDrawerDestination(
    icon: itemsIcons[0],
    selectedIcon: selectedItemsIcons[0],
    label: UseText(itemsLabel[0]),
  ),
  NavigationDrawerDestination(
    icon: itemsIcons[1],
    selectedIcon: selectedItemsIcons[1],
    label: UseText(itemsLabel[1]),
  ),
  NavigationDrawerDestination(
    icon: itemsIcons[2],
    selectedIcon: selectedItemsIcons[2],
    label: UseText(itemsLabel[2]),
  ),
  NavigationDrawerDestination(
    icon: itemsIcons[3],
    selectedIcon: selectedItemsIcons[3],
    label: UseText(itemsLabel[3]),
  ),
  NavigationDrawerDestination(
    icon: itemsIcons[4],
    selectedIcon: selectedItemsIcons[4],
    label: UseText(itemsLabel[4]),
  ),
  const NavigationDrawerDestination(
    icon: Icon(Icons.note_alt_outlined),
    selectedIcon: Icon(Icons.edit_document),
    label: UseText(I18nKey.navEditor),
  ),
];

List<NavigationRailDestination> tabletRailItems = [
  NavigationRailDestination(
    icon: itemsIcons[0],
    selectedIcon: selectedItemsIcons[0],
    label: UseText(itemsLabel[0]),
  ),
  NavigationRailDestination(
    icon: itemsIcons[1],
    selectedIcon: selectedItemsIcons[1],
    label: UseText(itemsLabel[1]),
  ),
  NavigationRailDestination(
    icon: itemsIcons[2],
    selectedIcon: selectedItemsIcons[2],
    label: UseText(itemsLabel[2]),
  ),
  NavigationRailDestination(
    icon: itemsIcons[3],
    selectedIcon: selectedItemsIcons[3],
    label: UseText(itemsLabel[3]),
  ),
  NavigationRailDestination(
    icon: itemsIcons[4],
    selectedIcon: selectedItemsIcons[4],
    label: UseText(itemsLabel[4]),
  ),
  const NavigationRailDestination(
    icon: Icon(Icons.note_alt_outlined),
    selectedIcon: Icon(Icons.edit_document),
    label: UseText(I18nKey.navEditor),
  ),
];

List<NavigationRailDestination> desktopRailItems = [
  NavigationRailDestination(
    icon: itemsIcons[0],
    selectedIcon: selectedItemsIcons[0],
    label: UseText(itemsLabel[0]),
  ),
  NavigationRailDestination(
    icon: itemsIcons[1],
    selectedIcon: selectedItemsIcons[1],
    label: UseText(itemsLabel[1]),
  ),
  NavigationRailDestination(
    icon: itemsIcons[2],
    selectedIcon: selectedItemsIcons[2],
    label: UseText(itemsLabel[2]),
  ),
  NavigationRailDestination(
    icon: itemsIcons[3],
    selectedIcon: selectedItemsIcons[3],
    label: UseText(itemsLabel[3]),
  ),
  NavigationRailDestination(
    icon: itemsIcons[4],
    selectedIcon: selectedItemsIcons[4],
    label: UseText(itemsLabel[4]),
  ),
];
