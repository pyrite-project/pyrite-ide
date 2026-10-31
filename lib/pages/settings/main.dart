import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/models/settings.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/function_page.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/shared/md3_widgets.dart';
import 'package:pyrite_ide/shared/studio_text.dart';

class Settings extends ConsumerWidget {
  const Settings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final body = ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SettingsSection(
          title: I18nKey.settingsWorkspaceSection,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const UseText(I18nKey.settingsEditorTitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go("/settings/editor"),
            ),

            ListTile(
              leading: const Icon(Icons.terminal),
              title: const UseText(I18nKey.settingsTerminalTitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go("/settings/terminal"),
            ),

            ListTile(
              leading: const Icon(Icons.data_object),
              title: const UseText(I18nKey.settingsLspTitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go("/settings/lsp"),
            ),
          ],
        ),
        SettingsSection(
          title: I18nKey.settingsInterfaceSection,
          children: [
            ListTile(
              leading: const Icon(Icons.color_lens_outlined),
              title: const UseText(I18nKey.settingsStyleTitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go("/settings/style"),
            ),

            ListTile(
              leading: const Icon(Icons.translate),
              title: const UseText(I18nKey.settingsLanguageTitle),
              trailing: DropdownButton<String>(
                value: _effectiveLocale(ref),
                items: [
                  for (final locale in ref.watch(availableLocalesProvider))
                    DropdownMenuItem(value: locale, child: Text(locale)),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  ref.read(activeLocaleProvider.notifier).state = value;
                },
              ),
            ),

            SwitchListTile(
              secondary: const Icon(Icons.dashboard),
              title: const UseText(I18nKey.settingsFunctionPanelTitle),
              value: ref.watch(functionPageShow),
              onChanged: (value) {
                ref.read(functionPageShow.notifier).state = value;
              },
            ),

            SwitchListTile(
              secondary: const Icon(Icons.terminal),
              title: const UseText(I18nKey.settingsConsolePanelTitle),
              value: ref.watch(consolePageShow),
              onChanged: (value) {
                ref.read(consolePageShow.notifier).state = value;
              },
            ),

            ListTile(
              leading: const Icon(Icons.sort),
              title: const UseText(I18nKey.settingsFileSortTitle),
              subtitle: const UseText(I18nKey.settingsFileSortSubtitle),
              trailing: DropdownButton<FileSortMode>(
                value: ref.watch(fileSortModeProvider),
                items: const [
                  DropdownMenuItem(
                    value: FileSortMode.byName,
                    child: UseText(I18nKey.settingsFileSortByName),
                  ),
                  DropdownMenuItem(
                    value: FileSortMode.byType,
                    child: UseText(I18nKey.settingsFileSortByType),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  ref.read(fileSortModeProvider.notifier).state = value;
                },
              ),
            ),

            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const UseText(I18nKey.settingsWelcomeTitle),
              trailing: const Icon(Icons.open_in_full),
              onTap: () {
                ref.read(welcomeCompletedProvider.notifier).state = false;
                context.go('/welcome');
              },
            ),

            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const UseText(I18nKey.settingsAboutTitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go("/settings/about"),
            ),
          ],
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const UseText(I18nKey.settingsTitle)),
      body: body,
    );
  }

  String _effectiveLocale(WidgetRef ref) {
    final locale = ref.watch(activeLocaleProvider);
    final available = ref.watch(availableLocalesProvider);
    return available.contains(locale) ? locale : defaultLocale;
  }
}
