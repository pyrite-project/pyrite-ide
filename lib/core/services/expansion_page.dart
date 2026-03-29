import 'package:code_forge/code_forge/controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabbed_view/tabbed_view.dart';

final Map<String, CodeForgeController> expansionControllerMap = {};

final StateProvider<TabbedViewController> expansionViewController =
    StateProvider<TabbedViewController>(
      (ref) => TabbedViewController([
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
      ]),
    );
