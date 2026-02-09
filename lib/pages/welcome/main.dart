import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/core/services/android_env_deployer/core.dart';
import 'package:pyrite_ide/core/services/android_env_deployer/main.dart';
import 'package:pyrite_ide/core/services/pylsp/main.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

class Welcome extends ConsumerWidget {
  const Welcome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (Platform.isAndroid) {
      if (ref.watch(state)) {
        return Scaffold(
          appBar: AppBar(title: Text("欢迎")),
          body: Padding(
            padding: EdgeInsetsGeometry.all(15),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text("欢迎来到 PyriteIDE"),
                  Text("正在针对目标平台（Android）进行环境部署"),
                  Text("这大概需要六至八分钟，请稍作等待"),
                  SizedBox(height: 15),
                  FilledButton(
                    onPressed: () => context.go("/index"),
                    child: Text("静默进行"),
                  ),
                  SizedBox(height: 15),
                  LinearProgressIndicator(),
                  SizedBox(height: 15),
                  Expanded(
                    child: CodeEditor(
                      controller: pythonDeployer.printController,
                      style: CodeEditorStyle(
                        codeTheme: CodeHighlightTheme(
                          languages: {
                            'micropython': CodeHighlightThemeMode(
                              mode: langPython,
                            ),
                          },
                          theme: Theme.of(context).brightness == Brightness.dark
                              ? atomOneDarkTheme
                              : atomOneLightTheme,
                        ),
                        fontSize: ref.watch(editorFontSize),
                        fontFamily:
                            editorTextFonts[ref.watch(editorTextFontProvider)],
                      ),
                      wordWrap: ref.watch(editorWordWrap),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          context.go("/index");
        });
        return Text("go");
      }
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.go("/index");
      });
      return Scaffold(appBar: AppBar(title: Text("欢迎")));
    }
  }
}
