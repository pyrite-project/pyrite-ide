import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/services/board_manager/utils.dart';
import 'package:pyrite_ide/core/services/editor/editor_controller_provider.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/expansion_page.dart';
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
    final canSave =
        selectedValue is TabDataValue && selectedValue.type == "file";
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
              IconButton(
                tooltip: "另存为",
                icon: const Icon(Icons.save_as_outlined, size: 20),
                onPressed: canSave
                    ? () => ref.read(localWorkspaceProvider.notifier).saveAs()
                    : null,
              ),
              const SizedBox(height: 24, child: VerticalDivider(thickness: 1)),
              IconButton(
                tooltip: "剪切",
                icon: const Icon(Icons.content_cut, size: 20),
                onPressed: canSave
                    ? ref.read(editorControllerMapProvider.notifier).cut
                    : null,
              ),
              IconButton(
                tooltip: "复制",
                icon: const Icon(Icons.content_copy, size: 20),
                onPressed: canSave
                    ? ref.read(editorControllerMapProvider.notifier).copy
                    : null,
              ),
              IconButton(
                tooltip: "粘贴",
                icon: const Icon(Icons.content_paste, size: 20),
                onPressed: canSave
                    ? ref.read(editorControllerMapProvider.notifier).paste
                    : null,
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
            ],
          ),
        ),
        toolbarHeight: 50,
      ),
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
