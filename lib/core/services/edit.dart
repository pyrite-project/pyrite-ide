import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/features/edit_core/main.dart';
import 'package:pyrite_ide/pages/edit/welcome.dart';
import 'package:re_editor/re_editor.dart';
import 'package:tabbed_view/tabbed_view.dart';
import 'package:xterm/xterm.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pty/flutter_pty.dart' as pty;

StateProvider<Map<String, CodeLineEditingController>> editorControllerMap =
    StateProvider<Map<String, CodeLineEditingController>>((ref) => {});

final TabbedViewController tabbedViewController = TabbedViewController([
  TabData(
    text: "欢迎",
    content: Welcome(),
    leading: (context, status) => Padding(
      padding: EdgeInsetsGeometry.directional(
        start: 5,
        end: 10,
        top: 5,
        bottom: 5,
      ),
      child: Image.asset("assets/icons/app_icon.png", width: 15, height: 15),
    ),
  ),
]);

final Terminal terminal = Terminal();

TabData createNewTab(
  File file,
  WidgetRef ref,
  CodeLineEditingController editorController,
) {
  String pattern = "\\";

  if (Platform.isWindows) {
    pattern = "\\";
  } else {
    pattern = "/";
  }
  return TabData(
    text: file.path.split(pattern).last,
    content: EditCore(file: file, editorController: editorController),
  );
}

Future<CodeLineEditingController> createNewEditorController(
  File file,
  WidgetRef ref,
) async {
  CodeLineEditingController controller = CodeLineEditingController();
  controller.text = await file.readAsString();
  return controller;
}
