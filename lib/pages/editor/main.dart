import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/services/board_manager/utils.dart';
import 'package:pyrite_ide/core/services/editor/editor_controller_provider.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/expansion_page.dart';
import 'package:pyrite_ide/core/services/file/board_file_items_provider.dart';
import 'package:pyrite_ide/core/services/file/board_workspace_provider.dart';
import 'package:pyrite_ide/core/services/file/local_workspace_provider.dart';
import 'package:pyrite_ide/core/services/function_page.dart';
import 'package:tabbed_view/tabbed_view.dart' hide TabbedView;
import 'package:pyrite_ide/shared/tabbed_view/tabbed_view.dart';
import 'package:flutter/material.dart';

class Editor extends ConsumerWidget {
  const Editor({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedValue = ref
        .watch(tabbedViewControllerProvider)
        .selectedTab
        ?.value;
    final fileValue =
        selectedValue is TabDataValue && selectedValue.type == "file"
        ? selectedValue
        : null;
    final canSave = fileValue != null;
    final isConnected = ref.watch(getUsbSerialProvider()).isConnected;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: canSave
                    ? () async {
                        await ref
                            .read(localWorkspaceProvider.notifier)
                            .saveFile();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("已保存当前文件")),
                        );
                      }
                    : null,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text("保存"),
              ),
              const SizedBox(width: 4),
              OutlinedButton.icon(
                onPressed: canSave && isConnected
                    ? () => uploadCurrentFile(context, ref)
                    : null,
                icon: const Icon(Icons.upload_outlined, size: 18),
                label: const Text("上传"),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: canSave && isConnected
                    ? () => runCurrentFile(context, ref)
                    : null,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text("运行"),
              ),
              const SizedBox(height: 24, child: VerticalDivider(thickness: 1)),
              IconButton(
                tooltip: "显示 REPL",
                icon: const Icon(Icons.terminal, size: 20),
                onPressed: () =>
                    ref.read(consolePageShow.notifier).state = true,
              ),
              IconButton(
                tooltip: isConnected ? "中断设备运行" : "连接设备后可中断运行",
                icon: const Icon(Icons.stop_circle_outlined, size: 20),
                onPressed: isConnected
                    ? () {
                        ref
                            .read(getUsbSerialProvider().notifier)
                            .sendCommand("\x03");
                      }
                    : null,
              ),
              IconButton(
                tooltip: isConnected ? "软重启设备" : "连接设备后可软重启",
                icon: const Icon(Icons.restart_alt, size: 20),
                onPressed: isConnected
                    ? () {
                        ref
                            .read(getUsbSerialProvider().notifier)
                            .sendCommand("\x04");
                      }
                    : null,
              ),
              PopupMenuButton<String>(
                tooltip: "更多编辑操作",
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  switch (value) {
                    case "saveAs":
                      ref.read(localWorkspaceProvider.notifier).saveAs();
                      break;
                    case "cut":
                      ref.read(editorControllerMapProvider.notifier).cut();
                      break;
                    case "copy":
                      ref.read(editorControllerMapProvider.notifier).copy();
                      break;
                    case "paste":
                      ref.read(editorControllerMapProvider.notifier).paste();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: "saveAs",
                    enabled: canSave,
                    child: const Text("另存为"),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: "cut",
                    enabled: canSave,
                    child: const Text("剪切"),
                  ),
                  PopupMenuItem(
                    value: "copy",
                    enabled: canSave,
                    child: const Text("复制"),
                  ),
                  PopupMenuItem(
                    value: "paste",
                    enabled: canSave,
                    child: const Text("粘贴"),
                  ),
                ],
              ),
            ],
          ),
        ),
        toolbarHeight: 50,
      ),
      body: body(context, ref),
    );
  }

  Future<String?> uploadCurrentFile(
    BuildContext context,
    WidgetRef ref, {
    bool quiet = false,
  }) async {
    final selectedValue = ref
        .read(tabbedViewControllerProvider)
        .selectedTab
        ?.value;
    if (selectedValue is! TabDataValue || selectedValue.type != "file") {
      if (!quiet) showEditorSnackBar(context, "先打开一个 Python 文件");
      return null;
    }

    final remotePath =
        selectedValue.boardFilePath ??
        "/${path.basename(selectedValue.filePath)}";

    if (selectedValue.isBoardFile == true) {
      await ref.read(localWorkspaceProvider.notifier).saveFile();
    } else {
      await ref
          .read(boardWorkspaceProvider.notifier)
          .writeFile(remotePath, selectedValue.editorController!.text);
      ref.read(boardFileItemsProvider.notifier).buildRootFileListItems();
    }

    if (!context.mounted) return null;
    if (!quiet) showEditorSnackBar(context, "已上传到设备：$remotePath");
    return remotePath;
  }

  Future<void> runCurrentFile(BuildContext context, WidgetRef ref) async {
    final remotePath = await uploadCurrentFile(context, ref, quiet: true);
    if (remotePath == null || !context.mounted) return;

    final escapedPath = remotePath
        .replaceAll("\\", "\\\\")
        .replaceAll("'", "\\'");
    ref.read(consolePageShow.notifier).state = true;
    ref.read(getUsbSerialProvider().notifier).sendCommand("\x03");
    await Future.delayed(const Duration(milliseconds: 160));
    if (!context.mounted) return;
    ref
        .read(getUsbSerialProvider().notifier)
        .sendCommand("exec(open('$escapedPath').read())\r");
    showEditorSnackBar(context, "正在运行：$remotePath");
  }

  void showEditorSnackBar(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget body(BuildContext context, WidgetRef ref) {
    return TabbedViewTheme(
      data: TabbedViewThemeData.underline(
        colorSet: MaterialColor(
          Theme.of(context).colorScheme.primary.toARGB32(),
          <int, Color>{
            50: Theme.of(context).colorScheme.surface,
            400: Theme.of(context).colorScheme.secondaryContainer,
            500: Theme.of(context).colorScheme.surface,
            700: Theme.of(context).colorScheme.secondary,
            900: Theme.of(context).colorScheme.onSecondaryContainer,
          },
        ),
        underlineColorSet: MaterialColor(
          Theme.of(context).colorScheme.primary.toARGB32(),
          <int, Color>{},
        ),
      ),
      child: TabbedView(controller: ref.watch(tabbedViewControllerProvider)),
    );
  }
}

class ExpansionPage extends ConsumerWidget {
  const ExpansionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text("扩展面板"), toolbarHeight: 50),
      body: body(context, ref),
    );
  }

  Widget body(BuildContext context, WidgetRef ref) {
    return TabbedViewTheme(
      data: TabbedViewThemeData.underline(
        colorSet: MaterialColor(
          Theme.of(context).colorScheme.primary.toARGB32(),
          <int, Color>{
            50: Theme.of(context).colorScheme.surface,
            400: Theme.of(context).colorScheme.secondaryContainer,
            500: Theme.of(context).colorScheme.surface,
            700: Theme.of(context).colorScheme.secondary,
            900: Theme.of(context).colorScheme.onSecondaryContainer,
          },
        ),
        underlineColorSet: MaterialColor(
          Theme.of(context).colorScheme.primary.toARGB32(),
          <int, Color>{},
        ),
      ),
      child: TabbedView(controller: ref.watch(expansionViewController)),
    );
  }
}
