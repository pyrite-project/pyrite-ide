import 'dart:io';
import 'package:code_forge/code_forge/controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/services/editor/editor_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/local_file_items_provider.dart';
import 'package:pyrite_ide/core/services/file/local_utils.dart' as local;
import 'package:pyrite_ide/core/services/file/upload_and_download_diff.dart';
import 'package:pyrite_ide/core/services/function_page.dart';
import 'package:pyrite_ide/core/services/persistence/persistence_models.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:tabbed_view/tabbed_view.dart';
import 'package:pyrite_ide/features/edit_core/main.dart';
import 'package:pyrite_ide/pages/editor/welcome.dart';

class TabbedViewControllerNotifier extends StateNotifier<TabbedViewController> {
  final Ref ref;
  VoidCallback? onUnsavedChange;

  TabbedViewControllerNotifier(this.ref) : super(_buildTabbedViewController());

  static TabbedViewController _buildTabbedViewController() {
    return TabbedViewController([
      TabData(
        closable: false,
        value: TabDataValue(type: "page", filePath: "welcome"),
        text: "欢迎   ",
        content: EditorWelcome(),
        leading: (context, status) => Padding(
          padding: EdgeInsetsGeometry.directional(
            start: 5,
            end: 10,
            top: 5,
            bottom: 5,
          ),
          child: Image.asset(
            "assets/icons/app_icon_appbar.png",
            color: Theme.of(context).colorScheme.primary,
            width: 15,
            height: 15,
          ),
        ),
      ),
    ]);
  }

  Future<TabData?> _createNewFileTab(
    File file,
    CodeForgeController? editorController, {
    bool isBoardFile = false,
    String? boardFilePath,
    bool isSaved = true,
  }) async {
    if (editorController == null) {
      return null;
    }

    String pattern = "\\";

    if (Platform.isWindows) {
      pattern = "\\";
    } else {
      pattern = "/";
    }

    TabDataValue value = TabDataValue(
      type: "file",
      filePath: file.path,
      file: file,
      editorController: editorController,
      isBoardFile: isBoardFile,
      boardFilePath: boardFilePath,
      isSaved: isSaved,
    );

    final tab = TabData(
      leading: (context, status) => Padding(
        padding: EdgeInsetsGeometry.only(right: 4),
        child: Icon(
          (isBoardFile)
              ? Icons.developer_board_outlined
              : Icons.description_outlined,
          size: 16,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      value: value,
      text: file.path.split(pattern).last,
      content: EditCore(file: file, editorController: editorController),
      keepAlive: true,
    );

    String savedText = editorController.text;
    editorController.addListener(() {
      if (tab.value is TabDataValue) {
        final val = tab.value as TabDataValue;
        final currentText = editorController.text;
        if (currentText == savedText) return;
        savedText = currentText;
        if (val.isSaved) {
          val.isSaved = false;
          tab.leading = (context, status) => Padding(
            padding: EdgeInsets.only(right: 4),
            child: Row(
              children: [
                Icon(Icons.circle, size: 8, color: Colors.orange),
                SizedBox(width: 4),
                Padding(
                  padding: EdgeInsetsGeometry.only(right: 4),
                  child: Icon(
                    (isBoardFile)
                        ? Icons.developer_board_outlined
                        : Icons.description_outlined,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          );
          final idx = state.selectedIndex;
          state = TabbedViewController(List.from(state.tabs));
          if (idx != null) state.selectedIndex = idx;
          onUnsavedChange?.call();
        }
      }
    });

    return tab;
  }

  void createFile() async {
    final file = await local.sysCreateFile();
    if (file != null) {
      final TabData? newTab = await _createNewFileTab(
        file,
        await ref
            .read(editorControllerMapProvider.notifier)
            .createNewEditorController(file),
      );

      if (newTab == null) {
        debugPrint("cannot open file");
        return;
      }

      state.addTab(newTab);
      state = TabbedViewController(List.from(state.tabs));
      state.selectTab(newTab);
      ref.read(localFileItemsProvider.notifier).buildRootFileListItems();
    }
  }

  Future openFile(
    BuildContext context, {
    File? file,
    bool isBoardFile = false,
    String? boardFilePath,
    String? initialText,
  }) async {
    file ??= await local.sysGetFile();
    if (file != null) {
      final TabData? newTab = await _createNewFileTab(
        file,
        await ref
            .read(editorControllerMapProvider.notifier)
            .createNewEditorController(file, initialText: initialText),
        isBoardFile: isBoardFile,
        boardFilePath: boardFilePath,
      );

      if (newTab == null) {
        return;
      }

      for (TabData tab in state.tabs) {
        final value = tab.value as TabDataValue;
        final sameLocalFile = value.filePath == file.path;
        final sameBoardFile =
            boardFilePath != null && value.boardFilePath == boardFilePath;
        if (sameLocalFile || sameBoardFile) {
          TabbedViewController newController = TabbedViewController(
            List.from(state.tabs),
          );
          newController.selectTab(tab);
          state = newController;
          return;
        }
      }

      state.addTab(newTab);

      pendingUploadProviderMap[file.path] = StateProvider((ref) => null);
      pendingDownloadProviderMap[file.path] = StateProvider((ref) => null);

      TabbedViewController newController = TabbedViewController(
        List.from(state.tabs),
      );
      newController.selectTab(newTab);
      state = newController;
      if (context.mounted) {
        if (ResponsiveBreakpoints.of(context).isMobile) {
          ref.read(mobileSelectedIndex.notifier).state = 3;
        } else if (ResponsiveBreakpoints.of(context).isTablet) {
          ref.read(tabletSelectedIndex.notifier).state = 3;
        }
      }
    }
  }

  void onTabTap(TabData tabData, int newTabIndex) async {
    // print("tap");
    TabbedViewController newController = TabbedViewController(
      List.from(state.tabs),
    );
    newController.selectedIndex = newTabIndex;
    state = newController;
  }

  void afterTabClose(int index, TabData tabData) async {
    final value = tabData.value;
    final filePath = value.filePath;
    TabbedViewController newController = TabbedViewController(
      List.from(state.tabs),
    );
    state = newController;

    ref
            .read(
              pendingUploadProviderMap[filePath]!.notifier,
            )
            .state =
        null;
    ref
            .read(
              pendingDownloadProviderMap[filePath]!.notifier,
            )
            .state =
        null;

    if (value != null && value is TabDataValue && value.isBoardFile == true) {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  void afterFileSave() {
    final TabData nowTab = state.selectedTab!;
    if (nowTab.value is TabDataValue) {
      (nowTab.value as TabDataValue).isSaved = true;
    }
    nowTab.leading = (context, status) {
      return null;
    };
  }

  Future<void> restoreTabs(
    List<PersistedTab> persistedTabs,
    int selectedIndex,
  ) async {
    final List<TabData> tabs = [];

    tabs.addAll(_buildTabbedViewController().tabs);

    for (final persisted in persistedTabs) {
      final file = File(persisted.filePath);
      final exists = await file.exists();
      if (!exists && persisted.unsavedContent == null) continue;

      if (!exists && persisted.unsavedContent != null) {
        await file.create(recursive: true);
        await file.writeAsString(persisted.unsavedContent!);
      } else if (exists &&
          !persisted.isSaved &&
          persisted.unsavedContent != null) {
        await file.writeAsString(persisted.unsavedContent!);
      }

      final controller = await ref
          .read(editorControllerMapProvider.notifier)
          .createNewEditorController(
            file,
          );
      if (controller == null) continue;
      final tab = await _createNewFileTab(
        file,
        controller,
        isBoardFile: persisted.isBoardFile,
        boardFilePath: persisted.boardFilePath,
        isSaved: persisted.isSaved,
      );
      if (tab != null) {
        if (!persisted.isSaved && persisted.unsavedContent != null) {
          tab.leading = (context, status) => Padding(
            padding: EdgeInsets.only(right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 8, color: Colors.orange),
                SizedBox(width: 4),
                Icon(
                  persisted.isBoardFile
                      ? Icons.developer_board_outlined
                      : Icons.description_outlined,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
          );
        }
        tabs.add(tab);
      }
    }

    final newController = TabbedViewController(tabs);
    if (selectedIndex > 0 && selectedIndex < tabs.length) {
      newController.selectedIndex = selectedIndex;
    }
    state = newController;
  }
}

final StateNotifierProvider<TabbedViewControllerNotifier, TabbedViewController>
tabbedViewControllerProvider = StateNotifierProvider(
  (ref) => TabbedViewControllerNotifier(ref),
);
