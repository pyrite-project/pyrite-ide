import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
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
                      label: workspace == null
                          ? I18nKey.editorWelcomeNoProject
                          : I18nKey.editorWelcomeProjectOpen,
                      icon: Icons.folder_outlined,
                      containerColor: workspace == null
                          ? scheme.surfaceContainerHighest
                          : scheme.primaryContainer,
                      foregroundColor: workspace == null
                          ? scheme.onSurfaceVariant
                          : scheme.onPrimaryContainer,
                    ),
                    PillBadge(
                      label: usb.isConnected
                          ? I18nKey.devicesConnected
                          : I18nKey.editorWelcomeDeviceDisconnected,
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
                      label: const UseText(I18nKey.editorWelcomeOpenProject),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => context.go("/tools"),
                      icon: const Icon(Icons.usb),
                      label: const UseText(I18nKey.editorWelcomeConnectDevice),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => ref
                          .read(tabbedViewControllerProvider.notifier)
                          .createFile(),
                      icon: const Icon(Icons.add),
                      label: const UseText(I18nKey.menuNewFile),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => ref
                          .read(tabbedViewControllerProvider.notifier)
                          .openFile(context),
                      icon: const Icon(Icons.file_open_outlined),
                      label: const UseText(I18nKey.menuOpenFile),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                Column(
                  children: [
                    QuickStartStep(
                      icon: Icons.folder_open_outlined,
                      title: I18nKey.editorWelcomeStepOpenProject,
                      description:
                          workspace?.path ??
                          I18nKey.editorWelcomeStepOpenProjectDescription,
                    ),
                    QuickStartStep(
                      icon: Icons.usb,
                      title: I18nKey.editorWelcomeStepConnectDevice,
                      description: usb.isConnected
                          ? translateForWidget(
                              ref,
                              I18nKey.editorWelcomeCurrentDevice,
                            ).replaceAll('{port}', usb.selectedPortName ?? '')
                          : I18nKey.editorWelcomeStepConnectDeviceDescription,
                    ),
                    const QuickStartStep(
                      icon: Icons.play_arrow,
                      title: I18nKey.editorWelcomeStepEditRun,
                      description: I18nKey.editorWelcomeStepEditRunDescription,
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
  final Object title;
  final Object description;

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
                UseText(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                UseText(
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
