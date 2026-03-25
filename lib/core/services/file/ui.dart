import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/editor/main.dart';
import 'package:pyrite_ide/core/services/file/board.dart' as board;
import 'package:pyrite_ide/core/services/file/local.dart' as local;
import 'package:pyrite_ide/core/services/function_page.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:tabbed_view/tabbed_view.dart';

void createFileAction(WidgetRef ref) async {
  final file = await local.createFile();
  if (file != null) {
    final TabData? newTab = await createNewFileTab(
      file,
      ref,
      await createNewEditorController(file, ref),
      Device(micropython: false),
    );

    if (newTab == null) {
      print("cannot open file");
      return;
    }

    ref.read(tabbedViewController).addTab(newTab);
    ref.read(tabbedViewController).selectTab(newTab);
    ref.watch(local.treeItems.notifier).state = await local.buildFileListItems(
      ref,
      await local.getFilesList(ref),
    );
  }
}

void openFileAction(BuildContext context, WidgetRef ref, {Device? device, File? file}) async {
  file ??= await local.getFile();
  device ??= Device(micropython: false);
  print("debug: mpy device: ${device.micropython}");
  if (file != null) {
    final TabData? newTab = await createNewFileTab(
      file,
      ref,
      await createNewEditorController(file, ref),
      device,
    );

    if (newTab == null) {
      print("cannot open file");
      return;
    }

    for (TabData tab in ref.read(tabbedViewController).tabs) {
      if ((tab.value as TabDataValue).filePath == file.path) {
        ref.read(tabbedViewController).selectTab(tab);
        return;
      }
    }
    ref.read(tabbedViewController).addTab(newTab);
    ref.read(tabbedViewController).selectTab(newTab);
    if (context.mounted) {
      if (ResponsiveBreakpoints.of(context).isMobile) {
        ref.read(mobileSelectedIndex.notifier).state = 3;
      } else if (ResponsiveBreakpoints.of(context).isTablet) {
        ref.read(tabletSelectedIndex.notifier).state = 3;
      }
    }
  }
}

void openFolderAction(WidgetRef ref) async {
  await local.getDirectory(ref);
  ref.watch(local.treeItems.notifier).state = await local.buildFileListItems(
    ref,
    await local.getFilesList(ref),
  );
}

void saveFileAction(WidgetRef ref) {
  final TabData? nowTab = ref.read(tabbedViewController).selectedTab;
  if (nowTab != null && nowTab.value.type == "file") {
    print("debug: saveFileAction with file ${nowTab.value.filePath}, mpy device: ${nowTab.value.device!.micropython}");
    if (nowTab.value.device.micropython && nowTab.value.device.file != null) {
      print("debug: save to board");
      board.saveFile(ref, nowTab.value.device.file!, nowTab.value.editorController!.text);
    }
    else {
      local.saveFile(nowTab.value.file!, nowTab.value.editorController!.text);
    }
    afterFileSave();
  }
}

void saveAsAction(WidgetRef ref) async {
  final TabData? nowTab = ref.read(tabbedViewController).selectedTab;
  if (nowTab != null && nowTab.value.type == "file") {
    final bool state = await local.saveAs(nowTab.value.editorController!.text);
    if (state) afterFileSave();
  }
}
