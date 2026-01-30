import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pyrite_ide/core/constants/window.dart';
import 'package:window_manager/window_manager.dart';

class UseWindow {
  void init() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      WidgetsFlutterBinding.ensureInitialized();
      await windowManager.ensureInitialized();
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    }
  }
}

class UseTitleBar extends StatelessWidget {
  const UseTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (details) => windowManager.startDragging(),
      child: Container(
        padding: EdgeInsets.only(left: 15, right: 5),
        color: Theme.of(context).colorScheme.surface,
        height: 50,
        child: Row(
          children: [
            Image.asset("assets/icons/app_icon.png", width: 25, height: 25),
            SizedBox(width: 15),
            MenuBar(
              style: MenuStyle(
                backgroundColor: WidgetStateProperty.all(
                  Theme.of(context).colorScheme.surface,
                ),
                elevation: WidgetStateProperty.all(0),
              ),
              children: [
                SubmenuButton(
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.all(
                      Theme.of(context).colorScheme.surface,
                    ),
                    overlayColor: WidgetStateProperty.all(
                      Theme.of(context).colorScheme.surface,
                    ),
                  ),
                  alignmentOffset: Offset(0, 5),
                  menuChildren: [MenuItemButton(child: Text("data"))],
                  child: Text("文件"),
                ),
              ],
            ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: Icon(Icons.minimize, size: 18),
                    onPressed: () => windowManager.minimize(),
                  ),

                  // 最大化/恢复按钮
                  FutureBuilder<bool>(
                    future: windowManager.isMaximized(),
                    builder: (context, snapshot) {
                      return IconButton(
                        icon: Icon(
                          snapshot.data == true
                              ? Icons.filter_none
                              : Icons.crop_square,
                          size: 20,
                        ),
                        onPressed: () async {
                          if (await windowManager.isMaximized()) {
                            await windowManager.unmaximize();
                          } else {
                            await windowManager.maximize();
                          }
                        },
                      );
                    },
                  ),

                  // 关闭按钮
                  IconButton(
                    hoverColor: Colors.redAccent,
                    icon: Icon(Icons.close, size: 20),
                    onPressed: () => windowManager.close(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
