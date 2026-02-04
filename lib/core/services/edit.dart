import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/file.dart';
import 'package:pyrite_ide/core/services/pylsp/core.dart';
import 'package:pyrite_ide/core/services/pylsp/data.dart';
import 'package:pyrite_ide/core/services/pylsp/main.dart';
import 'package:pyrite_ide/features/edit_core/main.dart';
import 'package:pyrite_ide/pages/edit/welcome.dart';
import 'package:pyrite_ide/shared/studio_text.dart';
import 'package:re_editor/re_editor.dart';
import 'package:tabbed_view/tabbed_view.dart';
import 'package:xterm/xterm.dart';

final StateProvider<Map<String, CodeLineEditingController>>
editorControllerMap = StateProvider<Map<String, CodeLineEditingController>>(
  (ref) => {},
);

Map<String, int> documentVersions = {};

String? lastText = "";

final StateProvider<TabbedViewController> tabbedViewController =
    StateProvider<TabbedViewController>(
      (ref) => TabbedViewController(
        [
          TabData(
            value: {"type": "page", "id": "welcome"},
            text: "欢迎",
            content: Welcome(),
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
        onTabRemove: (tabData) {
          if (tabData.value["type"] == "file") {
            ref.read(openFilesMap).remove(tabData.value["id"]);
            ref.read(editorControllerMap).remove(tabData.value["id"]);
          }
        },
      ),
    );

final Terminal terminal = Terminal();

Future<TabData> createNewFileTab(
  File file,
  WidgetRef ref,
  CodeLineEditingController editorController,
) async {
  String pattern = "\\";

  if (Platform.isWindows) {
    pattern = "\\";
  } else {
    pattern = "/";
  }

  Map<String, dynamic> value = {
    "type": "file",
    "id": file.path,
    "file": file,
    "editor_controller": editorController,
  };

  LspClient client = await PythonLspService(ref).client;

  client.sendRequest('textDocument/didOpen', {
    'textDocument': {
      'uri': Uri.file(file.path).toString(),
      'languageId': 'python',
      'version': documentVersions[value["id"]],
      'text': editorController.text,
    },
  });

  return TabData(
    value: value,
    text: file.path.split(pattern).last,
    content: EditCore(file: file, editorController: editorController),
  );
}

Future<CodeLineEditingController> createNewEditorController(
  File file,
  WidgetRef ref,
) async {
  Timer? debounce;
  CodeLineEditingController controller = CodeLineEditingController.fromText(
    await file.readAsString(),
  );
  LspClient client = await PythonLspService(ref).client;

  documentVersions[file.path] = 1;

  controller.addListener(() {
    if (lastText != controller.text) {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 1000), () {
        if (documentVersions[file.path] != null) {
          final String newText = controller.text;
          // Map<String, int> versions = ref.read(documentVersions.notifier).state;
          documentVersions[file.path] = documentVersions[file.path]! + 1;
          client.sendNotification("textDocument/didChange", {
            "textDocument": {
              "uri": Uri.file(file.path).toString(),
              "version": documentVersions[file.path],
            },
            "contentChanges": [
              {"text": newText},
            ],
          });
        }

        lastText = controller.text;
      });
    }
  });
  return controller;
}

void onTabTap(
  TabData tab,
  TabbedViewController controller,
  int newTabIndex,
  dynamic ref,
) async {
  if (tab.value["type"] == "file") {
    LspClient client = await PythonLspService(ref).client;
    await client.sendRequest("textDocument/didOpen", {
      "textDocument": {
        "uri": Uri.file(tab.value["id"]).toString(),
        "languageId": "python",
        "version": documentVersions[tab.value["id"]],
        "text": tab.value["editor_controller"].text,
      },
    });
  }
  controller.selectedIndex = newTabIndex;
}

void afterTabClose(
  int index,
  TabbedViewController controller,
  dynamic ref,
) async {
  final int newTabIndex = index - 1;
  if (controller.tabs[newTabIndex].value["type"] == "file" &&
      (index - 1) >= 0) {
    final TabData newTab = controller.tabs[index - 1];
    LspClient client = await PythonLspService(ref).client;
    client.sendRequest('textDocument/didOpen', {
      'textDocument': {
        'uri': Uri.file(newTab.value["id"]).toString(),
        'languageId': 'python',
        'version': 1,
        'text': newTab.value["editor_controller"].text,
      },
    });
  } else {
    cleanDiagnostics(ref);
  }
}
