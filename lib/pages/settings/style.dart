import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/data_registry.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/shared/md3_widgets.dart';
import 'package:pyrite_ide/shared/studio_text.dart';

class StyleSettings extends ConsumerWidget {
  const StyleSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeColorValue = ref.watch(themeColor);
    final activePluginThemeIdValue = ref.watch(activePluginThemeId);
    final dataRegistry = ref.watch(dataRegistryProvider);

    final hasPluginTheme = activePluginThemeIdValue != null;
    final pluginTheme = hasPluginTheme
        ? dataRegistry.getThemeById(activePluginThemeIdValue)
        : null;
    // If plugin theme forces a mode, ThemeMode setting is disabled
    final themeModeDisabled = pluginTheme?.mode != null;

    final body = ListView(
      padding: EdgeInsets.all(12),
      children: [
        SettingsSection(
          title: I18nKey.settingsStyleThemeMode,
          description: themeModeDisabled
              ? pluginTheme?.mode == 'dark'
                    ? I18nKey.settingsStyleThemeModePluginLockedDark
                    : I18nKey.settingsStyleThemeModePluginLockedLight
              : I18nKey.settingsStyleThemeModeDescription,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.auto_mode),
                    label: UseText(I18nKey.settingsStyleModeAuto),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode),
                    label: UseText(I18nKey.settingsStyleModeLight),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode),
                    label: UseText(I18nKey.settingsStyleModeDark),
                  ),
                ],
                selected: {ref.watch(themeMode)},
                onSelectionChanged: themeModeDisabled
                    ? null
                    : (value) {
                        ref.read(themeMode.notifier).state = value.first;
                      },
              ),
            ),
          ],
        ),
        SettingsSection(
          title: I18nKey.settingsStyleThemeStyle,
          description: hasPluginTheme
              ? I18nKey.settingsStylePluginThemeDisabledDescription
              : I18nKey.settingsStyleThemeStyleDescription,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: SegmentedButton<ThemeStyle>(
                segments: const [
                  ButtonSegment(
                    value: ThemeStyle.standard,
                    icon: Icon(Icons.lan),
                    label: UseText(I18nKey.settingsStyleStandard),
                  ),
                  ButtonSegment(
                    value: ThemeStyle.compact,
                    icon: Icon(Icons.window),
                    label: UseText(I18nKey.settingsStyleCompact),
                  ),
                  ButtonSegment(
                    value: ThemeStyle.comfortable,
                    icon: Icon(Icons.space_dashboard),
                    label: UseText(I18nKey.settingsStyleComfortable),
                  ),
                ],
                selected: {ref.watch(themeStyle)},
                onSelectionChanged: hasPluginTheme
                    ? null
                    : (value) {
                        ref.read(themeStyle.notifier).state = value.first;
                      },
              ),
            ),
          ],
        ),
        if (!hasPluginTheme)
          SettingsSection(
            title: I18nKey.settingsStyleThemeColor,
            description: I18nKey.settingsStyleThemeColorDescription,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ChoiceChip(
                      avatar: const Icon(Icons.auto_awesome),
                      label: const UseText(I18nKey.settingsStyleFollowSystem),
                      selected: themeColorValue == null,
                      onSelected: (v) {
                        if (v) {
                          ref.read(themeColor.notifier).state = null;
                        } else {
                          ref.read(themeColor.notifier).state = Colors.teal;
                        }
                      },
                    ),
                    SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: context.effectiveRadius,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      margin: EdgeInsets.all(0),
                      child: ColorPicker(
                        color:
                            themeColorValue ??
                            Theme.of(context).colorScheme.primary,
                        onColorChanged: (color) =>
                            ref.read(themeColor.notifier).state = color,
                        pickersEnabled: const {
                          ColorPickerType.primary: true,
                          ColorPickerType.accent: true,
                          ColorPickerType.wheel: true,
                        },
                        enableShadesSelection: false,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        SettingsSection(
          title: I18nKey.settingsStylePluginTheme,
          description: I18nKey.settingsStylePluginThemeDescription,
          children: [
            RadioGroup<String?>(
              groupValue: activePluginThemeIdValue,
              onChanged: (value) {
                ref.read(activePluginThemeId.notifier).state = value;
              },
              child: Column(
                children: [
                  RadioListTile<String?>(
                    title: const UseText(I18nKey.settingsStyleBuiltin),
                    subtitle: const UseText(
                      I18nKey.settingsStyleBuiltinSubtitle,
                    ),
                    value: null,
                  ),
                  for (final theme in dataRegistry.allThemes)
                    RadioListTile<String?>(
                      title: Text(theme.name),
                      subtitle: Text(
                        [
                          'by ${theme.pluginId}',
                          if (theme.mode != null)
                            '· ${translateForWidget(ref, theme.mode == 'dark' ? I18nKey.settingsStyleDarkOnly : I18nKey.settingsStyleLightOnly)}',
                        ].join(' '),
                      ),
                      value: theme.id,
                    ),
                ],
              ),
            ),
          ],
        ),
        SettingsSection(
          title: I18nKey.settingsStyleMenuStyle,
          description: I18nKey.settingsStyleMenuStyleDescription,
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.menu_open_outlined),
              title: const UseText(I18nKey.settingsStyleMd3ContextMenu),
              subtitle: const UseText(
                I18nKey.settingsStyleMd3ContextMenuSubtitle,
              ),
              value: ref.watch(useMaterialContextMenu),
              onChanged: (value) {
                ref.read(useMaterialContextMenu.notifier).state = value;
              },
            ),
          ],
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const UseText(I18nKey.settingsStyleTitle)),
      body: body,
    );
  }
}
