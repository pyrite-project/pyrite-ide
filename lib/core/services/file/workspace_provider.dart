import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/board_file_items_provider.dart';
import 'package:pyrite_ide/core/services/file/local_utils.dart' as utils;
import 'package:tabbed_view/tabbed_view.dart';

class LocalWorkspaceNotifier extends StateNotifier<Directory?> {
  final Ref ref;
  LocalWorkspaceNotifier(this.ref) : super(null);

  Future<Directory?> getDirectory() async {
    final String? path = await getDirectoryPath();
    final Directory? dir;
    if (path != null) {
      dir = Directory(path);
      state = dir;
      return dir;
    } else {
      return null;
    }
  }

  Future<Stream<FileSystemEntity>> getFilesList({String? path}) async {
    Stream<FileSystemEntity> datas;
    if (state != null && (path == null || path == state!.path)) {
      datas = state!.list();
    } else {
      if (path != null) {
        datas = Directory(path).list();
      } else {
        datas = Stream.empty();
      }
    }
    return datas;
  }

  void saveFile() {
    final TabData? nowTab = ref.read(tabbedViewControllerProvider).selectedTab;
    if (nowTab != null && nowTab.value.type == "file") {
      print(
        "debug: saveFileAction with file ${nowTab.value.filePath}, mpy device: ${nowTab.value.device!.micropython}",
      );
      if (nowTab.value.device.micropython && nowTab.value.device.file != null) {
        print("debug: save to board");
        ref
            .read(boardFileItemsProvider.notifier)
            .saveFile(
              nowTab.value.device.file!,
              nowTab.value.editorController!.text,
            );
      } else {
        utils.saveLocalFile(
          nowTab.value.file!,
          nowTab.value.editorController!.text,
        );
      }
      ref.read(tabbedViewControllerProvider.notifier).afterFileSave();
    }
  }

  void saveAs() async {
    final TabData? nowTab = ref.read(tabbedViewControllerProvider).selectedTab;
    if (nowTab != null && nowTab.value.type == "file") {
      final bool state = await utils.saveAs(
        nowTab.value.editorController!.text,
      );
      if (state) {
        ref.read(tabbedViewControllerProvider.notifier).afterFileSave();
      }
    }
  }
}

final StateNotifierProvider<LocalWorkspaceNotifier, Directory?>
workspaceProvider = StateNotifierProvider((ref) => LocalWorkspaceNotifier(ref));
