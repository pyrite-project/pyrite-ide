import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/editor/main.dart';
import 'package:pyrite_ide/core/services/file/local.dart';
import 'package:pyrite_ide/core/services/pylsp/data.dart';
import 'package:pyrite_ide/core/services/pylsp/main.dart';
import 'package:re_editor/re_editor.dart';
import 'package:tabbed_view/tabbed_view.dart';

final Map<String, CodeLineEditingController> expansionControllerMap = {};

final StateProvider<TabbedViewController> expansionViewController =
    StateProvider<TabbedViewController>(
      (ref) => TabbedViewController(
        [
          TabData(
            closable: false,
            value: {"type": "page", "id": "welcome"},
            text: "欢迎   ",
            content: Center(child: Text("欢迎使用拓展页")),
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
          if (tabData.value.type == "file") {
            final String path = tabData.value.filePath;
            final String uri = Uri.file(path).toString();

            // Dispose editor resources eagerly to avoid leaks on large files.
            openFilesMap.remove(path);
            final controller = editorControllerMap[path];
            controller?.dispose();
            editorControllerMap.remove(path);
          }
        },
      ),
    );
