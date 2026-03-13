import 'dart:async';
import 'dart:io';
import 'package:code_forge/LSP/lsp.dart';
import 'package:code_forge/code_forge/controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/file/local.dart';
import 'package:pyrite_ide/core/services/pylsp/core.dart';
import 'package:pyrite_ide/core/services/pylsp/data.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/features/edit_core/main.dart';
import 'package:pyrite_ide/pages/editor/welcome.dart';
import 'package:tabbed_view/tabbed_view.dart';
import 'package:xterm/xterm.dart';

final Map<String, CodeForgeController> editorControllerMap = {};

final StateProvider<bool?> lspState = StateProvider<bool?>((ref) => null);

final Terminal repl = Terminal();
final TerminalController replController = TerminalController();

class TabDataValue {
  const TabDataValue({
    required this.type,
    required this.filePath,
    this.editorController,
    this.file,
  });
  final String type;
  final String filePath;
  final File? file;
  final CodeForgeController? editorController;
}

final StateProvider<TabbedViewController> tabbedViewController =
    StateProvider<TabbedViewController>(
      (ref) => TabbedViewController(
        [
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
        ],
        onTabSelection: (tabIndex, tabData) {
          if ((tabData!.value as TabDataValue).type == "file") {
            if ((tabData.value as TabDataValue).editorController?.lspConfig !=
                null) {
              ref
                  .read(lspState.notifier)
                  .state = (tabData.value as TabDataValue)
                  .editorController!
                  .lspConfig!
                  .isInitialized;
            }
          } else {
            ref.read(lspState.notifier).state = null;
          }
        },
        onTabRemove: (tabData) {
          if (tabData.value.type == "file") {
            final String path = tabData.value.filePath;
            // final String uri = Uri.file(path).toString();

            // Dispose editor resources eagerly to avoid leaks on large files.
            openFilesMap.remove(path);
            final controller = editorControllerMap[path];
            controller?.dispose();
            editorControllerMap.remove(path);
          }
          ref.read(lspState.notifier).state = null;
        },
      ),
    );

Future<TabData> createNewFileTab(
  File file,
  WidgetRef ref,
  CodeForgeController editorController,
) async {
  if (openFilesisSavedMap[file.path] == null) {
    openFilesisSavedMap[file.path] = StateProvider<bool>((ref) => true);
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
  );

  final uri = Uri.file(file.path).toString();
  ref.read(activeDiagnosticUri.notifier).state = uri;

  if (value.editorController?.lspConfig != null) {
    ref.read(lspState.notifier).state =
        value.editorController!.lspConfig!.isInitialized;
    await value.editorController!.lspConfig!.initialize();
    ref.read(lspState.notifier).state =
        value.editorController!.lspConfig!.isInitialized;
  } else {
    ref.read(lspState.notifier).state = null;
  }

  return TabData(
    value: value,
    text: file.path.split(pattern).last,
    content: EditCore(file: file, editorController: editorController),
    keepAlive: true,
  );
}

Future<CodeForgeController> createNewEditorController(
  File file,
  WidgetRef ref,
) async {
  String pattern = "\\";

  if (Platform.isWindows) {
    pattern = "\\";
  } else {
    pattern = "/";
  }
  final String initialText = await file.readAsString();
  final uri = Uri.file(file.path).toString().split(pattern);
  // final fileName = uri.removeLast();
  uri.removeLast();
  final workspacePath = uri.join(pattern);
  CodeForgeController controller = CodeForgeController(
    lspConfig: (ref.read(useLsp))
        ? LspSocketConfig(
            workspacePath: workspacePath,
            languageId: "python",
            serverUrl: "ws://${ref.read(lspWebScoketPath)}",
            disableWarning: ref.read(disableWarning),
            disableError: ref.read(disableError),
          )
        : null,
  );
  controller.text = initialText;
  controller.openedFile = file.path;
  editorControllerMap[file.path] = controller;
  return controller;
}

void onTabTap(
  TabData tabData,
  TabbedViewController controller,
  int newTabIndex,
  dynamic ref,
) async {
  controller.selectedIndex = newTabIndex;
  if (tabData.value.type == "file") {
    if ((tabData.value as TabDataValue).editorController?.lspConfig != null) {
      ref.read(lspState.notifier).state = (tabData.value as TabDataValue)
          .editorController!
          .lspConfig!
          .isInitialized;
    } else {
      ref.read(lspState.notifier).state = null;
    }
  } else {
    ref.read(lspState.notifier).state = null;
  }
}

void afterTabClose(
  int index,
  TabbedViewController controller,
  dynamic ref,
) async {
  final tabData = controller.selectedTab;
  if (tabData?.value.type == "file") {
    if ((tabData?.value as TabDataValue).editorController?.lspConfig != null) {
      ref.read(lspState.notifier).state = (tabData?.value as TabDataValue)
          .editorController!
          .lspConfig!
          .isInitialized;
    } else {
      ref.read(lspState.notifier).state = null;
    }
  } else {
    ref.read(lspState.notifier).state = null;
  }

  cleanDiagnostics(ref);
}

void afterFileSave() {
  final TabData nowTab = container.read(tabbedViewController).selectedTab!;
  container.read(openFilesisSavedMap[nowTab.value.filePath]!.notifier).state =
      true;
  nowTab.leading = (context, status) {
    return null;
  };
}
