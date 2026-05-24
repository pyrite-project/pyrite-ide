import 'dart:io';
import 'package:code_forge/code_forge/controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/services/editor/editor_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/local_file_items_provider.dart';
import 'package:pyrite_ide/core/services/file/local_utils.dart' as local;
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
            "assets/icons/app_icon.png",
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
      isSaved: isSaved,
    );

    final tab = TabData(
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
                child: Icon(Icons.circle, size: 8, color: Colors.orange),
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
        print("cannot open file");
        return;
      }

      state.addTab(newTab);
      state = TabbedViewController(List.from(state.tabs));
      state.selectTab(newTab);
      ref.read(localFileItemsProvider.notifier).buildRootFileListItems();
    }
  }

  void openFile(
    BuildContext context, {
    File? file,
    bool isBoardFile = false,
    String? boardFilePath,
  }) async {
    file ??= await local.sysGetFile();
    if (file != null) {
      final TabData? newTab = await _createNewFileTab(
        file,
        await ref
            .read(editorControllerMapProvider.notifier)
            .createNewEditorController(file),
        isBoardFile: isBoardFile,
      );

      if (newTab == null) {
        return;
      }

      for (TabData tab in state.tabs) {
        if ((tab.value as TabDataValue).filePath == file.path) {
          TabbedViewController newController = TabbedViewController(
            List.from(state.tabs),
          );
          newController.selectTab(tab);
          state = newController;
          return;
        }
      }

      state.addTab(newTab);
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

  void afterTabClose(int index) async {
    TabbedViewController newController = TabbedViewController(
      List.from(state.tabs),
    );
    state = newController;
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
      if (persisted.isBoardFile) continue;
      final file = File(persisted.filePath);
      if (!await file.exists()) {
        if (persisted.unsavedContent == null) continue;
      }
      final controller = await ref
          .read(editorControllerMapProvider.notifier)
          .createNewEditorController(
            file,
            initialText: persisted.unsavedContent,
          );
      if (controller == null) continue;
      final tab = await _createNewFileTab(
        file,
        controller,
        isBoardFile: persisted.isBoardFile,
        isSaved: persisted.isSaved,
      );
      if (tab != null) {
        if (!persisted.isSaved && persisted.unsavedContent != null) {
          tab.leading = (context, status) => Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.circle, size: 8, color: Colors.orange),
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
