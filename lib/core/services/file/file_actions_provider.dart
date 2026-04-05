import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/board_file_items_provider.dart';
import 'package:pyrite_ide/core/services/file/board_utils.dart' as board;
import 'package:pyrite_ide/core/services/file/local_file_items_provider.dart';
import 'package:pyrite_ide/core/services/file/local_workspace_provider.dart';
import 'package:pyrite_ide/core/services/file/local_utils.dart' as local;
import 'package:tabbed_view/tabbed_view.dart';

final Provider openFolderAction = Provider((ref) async {
  await ref.read(localWorkspaceProvider.notifier).getDirectory();
  ref.read(localFileItemsProvider.notifier).buildRootFileListItems();
});

final Provider saveFileAction = Provider((ref) {
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
      local.saveLocalFile(
        nowTab.value.file!,
        nowTab.value.editorController!.text,
      );
    }
    ref.read(tabbedViewControllerProvider.notifier).afterFileSave();
  }
});

final Provider saveAsAction = Provider((ref) async {
  final TabData? nowTab = ref.read(tabbedViewControllerProvider).selectedTab;
  if (nowTab != null && nowTab.value.type == "file") {
    final bool state = await local.saveAs(nowTab.value.editorController!.text);
    if (state) ref.read(tabbedViewControllerProvider.notifier).afterFileSave();
  }
});
