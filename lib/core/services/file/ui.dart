import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/editor/main.dart';
import 'package:pyrite_ide/core/services/file/local.dart';
import 'package:pyrite_ide/core/services/function_page.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:tabbed_view/tabbed_view.dart';

void createFileAction(WidgetRef ref) async {
  final file = await createFile();
  if (file != null) {
    final TabData newTab = await createNewFileTab(
      file,
      ref,
      await createNewEditorController(file, ref),
    );
    ref.read(tabbedViewController).addTab(newTab);
    ref.read(tabbedViewController).selectTab(newTab);
    ref.watch(treeItems.notifier).state = await buildFileListItems(
      ref,
      await getFilesList(ref),
    );
  }
}

void openFileAction(BuildContext context, WidgetRef ref, {File? file}) async {
  file ??= await getFile();
  if (file != null) {
    final TabData newTab = await createNewFileTab(
      file,
      ref,
      await createNewEditorController(file, ref),
    );
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
  await getDirectory(ref);
  ref.watch(treeItems.notifier).state = await buildFileListItems(
    ref,
    await getFilesList(ref),
  );
}

void saveFileAction(WidgetRef ref) {
  final TabData? nowTab = ref.read(tabbedViewController).selectedTab;
  if (nowTab != null && nowTab.value.type == "file") {
    saveFile(nowTab.value.file!, nowTab.value.editorController!.text);
    afterFileSave();
  }
}

void saveAsAction(WidgetRef ref) async {
  final TabData? nowTab = ref.read(tabbedViewController).selectedTab;
  if (nowTab != null && nowTab.value.type == "file") {
    final bool state = await saveAs(nowTab.value.editorController!.text);
    if (state) afterFileSave();
  }
}
