import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/local_file_items_provider.dart';
import 'package:pyrite_ide/shared/studio_text.dart';

class EditorWelcome extends ConsumerWidget {
  const EditorWelcome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset("assets/icons/app_icon.png", width: 72, height: 72),
              const SizedBox(height: 24),
              const TextLogo(),
              const SizedBox(height: 12),
              Text(
                "一个更轻量、清晰的 MicroPython IDE",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () =>
                        ref.read(localFileItemsProvider.notifier).openFolder(),
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text("打开项目文件夹"),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.push("/tools"),
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
            ],
          ),
        ),
      ),
    );
  }
}
