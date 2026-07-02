import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/core/services/serial/utils.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/local_file_items_provider.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/shared/md3_widgets.dart';
import 'package:pyrite_ide/shared/studio_text.dart';

class EditorWelcome extends ConsumerWidget {
  const EditorWelcome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final workspace = ref.watch(fileProvider);
    final usb = ref.watch(getUsbSerialProvider());
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  "assets/icons/app_icon.webp",
                  width: 72,
                  height: 72,
                ),
                const SizedBox(height: 20),
                const TextLogo(),
                const SizedBox(height: 18),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    PillBadge(
                      label: workspace == null ? "未打开项目" : "项目已打开",
                      icon: Icons.folder_outlined,
                      containerColor: workspace == null
                          ? scheme.surfaceContainerHighest
                          : scheme.primaryContainer,
                      foregroundColor: workspace == null
                          ? scheme.onSurfaceVariant
                          : scheme.onPrimaryContainer,
                    ),
                    PillBadge(
                      label: usb.isConnected ? "设备已连接" : "未连接设备",
                      icon: Icons.usb,
                      containerColor: usb.isConnected
                          ? scheme.primaryContainer
                          : scheme.surfaceContainerHighest,
                      foregroundColor: usb.isConnected
                          ? scheme.onPrimaryContainer
                          : scheme.onSurfaceVariant,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => ref
                          .read(localFileItemsProvider.notifier)
                          .openFolder(),
                      icon: const Icon(Icons.folder_open_outlined),
                      label: const Text("打开项目文件夹"),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => context.go("/tools"),
                      icon: const Icon(Icons.usb),
                      label: const Text("连接设备"),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => ref
                          .read(tabbedViewControllerProvider.notifier)
                          .createFile(),
                      icon: const Icon(Icons.add),
                      label: const Text("新建文件"),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => ref
                          .read(tabbedViewControllerProvider.notifier)
                          .openFile(context),
                      icon: const Icon(Icons.file_open_outlined),
                      label: const Text("打开文件"),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                Column(
                  children: [
                    QuickStartStep(
                      icon: Icons.folder_open_outlined,
                      title: "1. 打开保存脚本的项目文件夹",
                      description: workspace?.path ?? "本地项目会显示在左侧文件面板中。",
                    ),
                    QuickStartStep(
                      icon: Icons.usb,
                      title: "2. 连接 MicroPython 设备",
                      description: usb.isConnected
                          ? "当前设备：${usb.selectedPortName}"
                          : "连接后可以同步板端文件并使用 REPL。",
                    ),
                    const QuickStartStep(
                      icon: Icons.play_arrow,
                      title: "3. 编辑、上传并运行脚本",
                      description: "保存、上传、运行和中断都在编辑器顶部工具栏中。",
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class QuickStartStep extends StatelessWidget {
  const QuickStartStep({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
