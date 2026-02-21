import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/editor/main.dart';
import 'package:pyrite_ide/core/services/file/local.dart';
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

void openFileAction(WidgetRef ref) async {
  File? file = await getFile();
  if (file != null) {
    final TabData newTab = await createNewFileTab(
      file,
      ref,
      await createNewEditorController(file, ref),
    );
    ref.read(tabbedViewController).addTab(newTab);
    ref.read(tabbedViewController).selectTab(newTab);
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
  if (nowTab != null && nowTab.value["type"] == "file") {
    saveFile(nowTab.value["file"], nowTab.value["editor_controller"].text);
    afterFileSave();
  }
}

void saveAsAction(WidgetRef ref) async {
  final TabData? nowTab = ref.read(tabbedViewController).selectedTab;
  if (nowTab != null && nowTab.value["type"] == "file") {
    final bool state = await saveAs(nowTab.value["editor_controller"].text);
    if (state) afterFileSave();
  }
}
