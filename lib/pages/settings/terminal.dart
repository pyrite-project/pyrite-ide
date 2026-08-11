import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/models/terminal_appearance.dart';
import 'package:pyrite_ide/core/services/serial/repl_mode_provider.dart';
import 'package:pyrite_ide/core/services/file/file_transfer_mode_provider.dart';
import 'package:pyrite_ide/core/services/serial/serial_provider.dart';
import 'package:pyrite_ide/core/services/serial/hardware_reset_provider.dart';
import 'package:pyrite_ide/core/services/serial/web_repl_provider.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/shared/md3_widgets.dart';
import 'package:pyrite_ide/shared/studio_text.dart';

const List<int> kAvailableBaudRates = [
  9600,
  14400,
  19200,
  38400,
  57600,
  115200,
  230400,
  460800,
  921600,
];

class TerminalSettings extends ConsumerWidget {
  const TerminalSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final webReplInfo = ref.watch(webReplProvider);
    final webReplHostValue = ref.watch(webReplHost);
    final webReplPortValue = ref.watch(webReplPort);
    final webReplEndpoint = webReplHostValue.isEmpty
        ? null
        : _tryBuildWebReplEndpoint(webReplHostValue, webReplPortValue);
    final body = ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SettingsSection(
          title: I18nKey.settingsTerminalSerialSection,
          description: I18nKey.settingsTerminalSerialDescription,
          children: [
            ListTile(
              leading: const Icon(Icons.speed),
              title: const UseText(I18nKey.settingsTerminalBaudRate),
              subtitle: Text("${ref.watch(serialDefaultBaudRate)} baud"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showBaudRateDialog(
                context,
                ref,
                ref.read(serialDefaultBaudRate),
              ),
            ),

            SwitchListTile(
              title: const UseText(I18nKey.settingsTerminalAutoReconnect),
              subtitle: const UseText(
                I18nKey.settingsTerminalAutoReconnectSubtitle,
              ),
              value: ref.watch(serialAutoReconnect),
              onChanged: (value) {
                ref.read(serialAutoReconnect.notifier).state = value;
                ref.read(serialProvider.notifier).setAutoReconnect(value);
              },
            ),

            SwitchListTile(
              title: const UseText(I18nKey.settingsTerminalSignalDetection),
              subtitle: const UseText(
                I18nKey.settingsTerminalSignalDetectionSubtitle,
              ),
              value: ref.watch(enableSignalDetection),
              onChanged: (value) {
                ref.read(enableSignalDetection.notifier).state = value;
              },
            ),

            SwitchListTile(
              title: const UseText(I18nKey.settingsTerminalEnsureFilesystem),
              subtitle: const UseText(
                I18nKey.settingsTerminalEnsureFilesystemSubtitle,
              ),
              value: ref.watch(ensureBoardFilesystemOnConnect),
              onChanged: (value) {
                ref.read(ensureBoardFilesystemOnConnect.notifier).state = value;
              },
            ),

            SwitchListTile(
              title: const UseText(I18nKey.settingsTerminalChineseToUnicode),
              subtitle: const UseText(
                I18nKey.settingsTerminalChineseToUnicodeSubtitle,
              ),
              value: ref.watch(chineseToUnicodeConversion),
              onChanged: (value) {
                ref.read(chineseToUnicodeConversion.notifier).state = value;
              },
            ),

            ListTile(
              leading: const Icon(Icons.terminal),
              title: const UseText(I18nKey.settingsTerminalReplMode),
              subtitle: Text(
                translateForWidget(
                  ref,
                  _replModeLabel(ref.watch(replModeProvider)),
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showReplModeDialog(context, ref),
            ),

            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const UseText(I18nKey.settingsTerminalTransferMode),
              subtitle: Text(
                translateForWidget(
                  ref,
                  _transferModeLabel(ref.watch(fileTransferModeProvider)),
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showTransferModeDialog(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.power_settings_new),
              title: const UseText(I18nKey.settingsTerminalHardwareReset),
              subtitle: Text(
                translateForWidget(
                  ref,
                  _hardwareResetLabel(ref.watch(hardwareResetStrategyProvider)),
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showHardwareResetDialog(context, ref),
            ),
          ],
        ),
        SettingsSection(
          title: I18nKey.settingsTerminalDisplaySection,
          description: I18nKey.settingsTerminalDisplayDescription,
          children: [
            ListTile(
              leading: const Icon(Icons.font_download_outlined),
              title: const UseText(I18nKey.settingsTerminalFont),
              subtitle: Text(ref.watch(terminalFontFamily)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showTerminalFontDialog(context, ref),
            ),

            ListTile(
              leading: const Icon(Icons.format_size),
              title: const UseText(I18nKey.settingsTerminalFontSize),
              subtitle: Text(
                "${ref.watch(terminalFontSize).toStringAsFixed(0)} px",
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showTerminalFontSizeDialog(context),
            ),

            ListTile(
              leading: const Icon(Icons.format_line_spacing),
              title: const UseText(I18nKey.settingsTerminalLineHeight),
              subtitle: Text(ref.watch(terminalLineHeight).toStringAsFixed(1)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showTerminalLineHeightDialog(context),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.text_fields),
              title: const UseText(I18nKey.settingsTerminalLigatures),
              subtitle: const UseText(
                I18nKey.settingsTerminalLigaturesSubtitle,
              ),
              value: ref.watch(terminalLigatures),
              onChanged: (value) =>
                  ref.read(terminalLigatures.notifier).state = value,
            ),
            const SectionDivider(),
            const _TerminalAppearanceSelector(),
            SwitchListTile(
              secondary: const Icon(Icons.visibility_outlined),
              title: const UseText(I18nKey.settingsTerminalMinimumContrast),
              subtitle: const UseText(
                I18nKey.settingsTerminalMinimumContrastSubtitle,
              ),
              value: ref.watch(terminalMinimumContrast),
              onChanged: (value) =>
                  ref.read(terminalMinimumContrast.notifier).state = value,
            ),
            if (ref.watch(terminalAppearance) == TerminalAppearance.custom)
              const _TerminalCustomColorsSection(),
          ],
        ),
        SettingsSection(
          title: "WebREPL",
          description: I18nKey.settingsTerminalWebReplDescription,
          children: [
            SwitchListTile(
              title: const UseText(I18nKey.settingsTerminalWebReplEnable),
              subtitle: webReplInfo.errorMessage == null
                  ? const UseText(I18nKey.settingsTerminalWebReplEnableSubtitle)
                  : Text(webReplInfo.errorMessage!),
              value: switch (webReplInfo.state) {
                WebReplState.waitingPassword || WebReplState.connected => true,
                _ => false,
              },
              onChanged: (value) {
                if (value) {
                  ref.read(webReplProvider.notifier).connect();
                } else {
                  ref.read(webReplProvider.notifier).disconnect();
                }
              },
            ),

            ListTile(
              leading: const Icon(Icons.wifi),
              title: const UseText(I18nKey.settingsTerminalDeviceIp),
              subtitle: Text(
                webReplEndpoint ?? I18nKey.settingsTerminalUnset.fallback,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showInputDialog(
                context,
                ref,
                I18nKey.settingsTerminalDeviceIp,
                I18nKey.settingsTerminalExampleIp,
                ref.read(webReplHost),
                (value) => ref.read(webReplHost.notifier).state = value.trim(),
              ),
            ),

            ListTile(
              leading: const Icon(Icons.numbers),
              title: const UseText(I18nKey.settingsTerminalPort),
              subtitle: Text("${ref.watch(webReplPort)}"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showPortDialog(context, ref),
            ),

            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const UseText(I18nKey.settingsTerminalPassword),
              subtitle: Text(
                ref.watch(webReplPassword).isEmpty
                    ? I18nKey.settingsTerminalUnset.fallback
                    : I18nKey.settingsTerminalSet.fallback,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showInputDialog(
                context,
                ref,
                I18nKey.settingsTerminalWebReplPassword,
                I18nKey.settingsTerminalWebReplPasswordHint,
                ref.read(webReplPassword),
                (value) =>
                    ref.read(webReplPassword.notifier).state = value.trim(),
              ),
            ),
          ],
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const UseText(I18nKey.settingsTerminalTitle)),
      body: body,
    );
  }

  String? _tryBuildWebReplEndpoint(String host, int port) {
    try {
      return buildWebReplUri(host, port).toString();
    } on FormatException {
      return host;
    }
  }

  void _showBaudRateDialog(BuildContext context, WidgetRef ref, int current) {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const UseText(I18nKey.settingsTerminalSelectBaudRate),
        children: [
          SizedBox(
            width: 360,
            height: 360,
            child: ListView(
              shrinkWrap: true,
              children: kAvailableBaudRates.map((rate) {
                final selected = rate == current;
                return SimpleDialogOption(
                  child: ListTile(
                    title: Text("$rate baud"),
                    trailing: selected ? const Icon(Icons.check) : null,
                    minTileHeight: 0,
                    onTap: () {
                      ref.read(serialProvider.notifier).setBaudRate(rate);
                      ref.read(serialDefaultBaudRate.notifier).state = rate;
                      Navigator.pop(context);
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  void _showReplModeDialog(BuildContext context, WidgetRef ref) {
    final current = ref.read(replModeProvider);
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const UseText(I18nKey.settingsTerminalReplMode),
        children: ReplMode.values.map((mode) {
          final selected = mode == current;
          final label = _replModeLabel(mode);
          return SimpleDialogOption(
            child: ListTile(
              title: UseText(label),
              trailing: selected ? const Icon(Icons.check) : null,
              minTileHeight: 0,
              onTap: () {
                ref.read(replModeProvider.notifier).state = mode;
                Navigator.pop(context);
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  I18nKey _replModeLabel(ReplMode mode) => switch (mode) {
    ReplMode.rawRepl => I18nKey.settingsTerminalReplModeRawRepl,
    ReplMode.paste => I18nKey.settingsTerminalReplModePaste,
  };

  void _showTransferModeDialog(BuildContext context, WidgetRef ref) {
    final current = ref.read(fileTransferModeProvider);
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const UseText(I18nKey.settingsTerminalTransferMode),
        children: FileTransferMode.values.map((mode) {
          final selected = mode == current;
          final label = _transferModeLabel(mode);
          return SimpleDialogOption(
            child: ListTile(
              title: UseText(label),
              trailing: selected ? const Icon(Icons.check) : null,
              minTileHeight: 0,
              onTap: () {
                ref.read(fileTransferModeProvider.notifier).state = mode;
                Navigator.pop(context);
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  I18nKey _transferModeLabel(FileTransferMode mode) => switch (mode) {
    FileTransferMode.chunked => I18nKey.settingsTerminalTransferModeChunked,
    FileTransferMode.streaming => I18nKey.settingsTerminalTransferModeStreaming,
  };

  void _showHardwareResetDialog(BuildContext context, WidgetRef ref) {
    final current = ref.read(hardwareResetStrategyProvider);
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const UseText(I18nKey.settingsTerminalHardwareReset),
        children: HardwareResetStrategy.values.map((strategy) {
          return SimpleDialogOption(
            child: ListTile(
              title: UseText(_hardwareResetLabel(strategy)),
              trailing: strategy == current ? const Icon(Icons.check) : null,
              minTileHeight: 0,
              onTap: () {
                ref.read(hardwareResetStrategyProvider.notifier).state =
                    strategy;
                Navigator.pop(context);
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  I18nKey _hardwareResetLabel(
    HardwareResetStrategy strategy,
  ) => switch (strategy) {
    HardwareResetStrategy.disabled =>
      I18nKey.settingsTerminalHardwareResetDisabled,
    HardwareResetStrategy.dtrPulse => I18nKey.settingsTerminalHardwareResetDtr,
    HardwareResetStrategy.rtsPulse => I18nKey.settingsTerminalHardwareResetRts,
    HardwareResetStrategy.esp32 => I18nKey.settingsTerminalHardwareResetEsp32,
  };

  void _showTerminalFontDialog(BuildContext context, WidgetRef ref) {
    final List<SimpleDialogOption> children = [];
    editorTextFonts.forEach((name, value) {
      final selected = ref.read(terminalFontFamily) == name;
      children.add(
        SimpleDialogOption(
          child: ListTile(
            title: Text(name),
            subtitle: Text(
              "print('Pyrite IDE')",
              style: TextStyle(fontFamily: value.isEmpty ? null : value),
            ),
            trailing: selected ? const Icon(Icons.check) : null,
            minTileHeight: 0,
            onTap: (name == "custom")
                ? () {
                    customizationTerminalTextFont();
                    context.pop(name);
                  }
                : () {
                    ref.read(terminalFontFamily.notifier).state = name;
                    context.pop(name);
                  },
          ),
        ),
      );
    });
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const UseText(I18nKey.settingsTerminalSelectFont),
        children: children,
      ),
    );
  }

  void _showTerminalFontSizeDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final size = ref.watch(terminalFontSize);
          return SimpleDialog(
            title: const UseText(I18nKey.settingsTerminalFontSize),
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 12),
                child: Text(
                  "print('Pyrite IDE')",
                  style: TextStyle(
                    fontFamily: editorTextFonts[ref.watch(terminalFontFamily)],
                    fontSize: size,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Slider(
                  min: 10,
                  max: 28,
                  divisions: 18,
                  value: size,
                  label: size.toStringAsFixed(0),
                  onChanged: (value) {
                    ref.read(terminalFontSize.notifier).state = value;
                    context.pop();
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showTerminalLineHeightDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final lineHeight = ref.watch(terminalLineHeight);
          return SimpleDialog(
            title: const UseText(I18nKey.settingsTerminalLineHeight),
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 12),
                child: Text(
                  "print('Pyrite IDE')",
                  style: TextStyle(
                    fontFamily: editorTextFonts[ref.watch(terminalFontFamily)],
                    fontSize: ref.watch(terminalFontSize),
                    height: lineHeight,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Slider(
                  min: 1.0,
                  max: 1.8,
                  divisions: 8,
                  value: lineHeight,
                  label: lineHeight.toStringAsFixed(1),
                  onChanged: (value) =>
                      ref.read(terminalLineHeight.notifier).state = value,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showInputDialog(
    BuildContext context,
    WidgetRef ref,
    Object title,
    Object hint,
    String currentValue,
    void Function(String) onSaved,
  ) {
    final controller = TextEditingController(text: currentValue);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: UseText(title),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hint: UseText(hint),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const UseText(I18nKey.commonCancel),
          ),
          FilledButton(
            onPressed: () {
              onSaved(controller.text);
              Navigator.pop(context);
            },
            child: const UseText(I18nKey.commonSave),
          ),
        ],
      ),
    );
  }

  void _showPortDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(
      text: ref.read(webReplPort).toString(),
    );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const UseText(I18nKey.settingsTerminalPort),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hint: UseText(I18nKey.settingsTerminalDefaultPortHint),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const UseText(I18nKey.commonCancel),
          ),
          FilledButton(
            onPressed: () {
              final port = int.tryParse(controller.text.trim());
              if (port != null && port > 0 && port <= 65535) {
                ref.read(webReplPort.notifier).state = port;
                Navigator.pop(context);
              }
            },
            child: const UseText(I18nKey.commonSave),
          ),
        ],
      ),
    );
  }
}

class _TerminalAppearanceSelector extends ConsumerWidget {
  const _TerminalAppearanceSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(terminalAppearance);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.contrast,
                size: 24,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 16),
              const UseText(I18nKey.settingsTerminalAppearance),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            child: SegmentedButton<TerminalAppearance>(
              segments: [
                for (final appearance in TerminalAppearance.values)
                  ButtonSegment(
                    value: appearance,
                    label: UseText(
                      _terminalAppearanceLabel(appearance),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    icon: Icon(
                      {
                        TerminalAppearance.followIde: Icons.auto_awesome,
                        TerminalAppearance.light: Icons.light_mode,
                        TerminalAppearance.dark: Icons.dark_mode,
                        TerminalAppearance.custom: Icons.dashboard_customize,
                      }[appearance],
                    ),
                  ),
              ],
              selected: {selected},
              onSelectionChanged: (value) =>
                  ref.read(terminalAppearance.notifier).state = value.first,
            ),
          ),
        ],
      ),
    );
  }
}

I18nKey _terminalAppearanceLabel(TerminalAppearance appearance) =>
    switch (appearance) {
      TerminalAppearance.followIde =>
        I18nKey.settingsTerminalAppearanceFollowIde,
      TerminalAppearance.light => I18nKey.settingsTerminalAppearanceLight,
      TerminalAppearance.dark => I18nKey.settingsTerminalAppearanceDark,
      TerminalAppearance.custom => I18nKey.settingsTerminalAppearanceCustom,
    };

class _TerminalCustomColors extends ConsumerWidget {
  const _TerminalCustomColors();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foreground = Color(ref.watch(terminalCustomForeground));
    final background = Color(ref.watch(terminalCustomBackground));
    final palette = ref.watch(terminalCustomPalette);
    final isModified =
        foreground.toARGB32() != kDefaultTerminalCustomForeground ||
        background.toARGB32() != kDefaultTerminalCustomBackground ||
        !listEquals(palette, kDefaultTerminalCustomPalette);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: UseText(I18nKey.settingsTerminalCustomPreview),
              ),
              TextButton.icon(
                onPressed: isModified
                    ? () => _confirmResetCustomColors(context, ref)
                    : null,
                icon: const Icon(Icons.restart_alt),
                label: const UseText(I18nKey.settingsTerminalCustomReset),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _TerminalColorPreview(
            foreground: foreground,
            background: background,
            palette: palette,
          ),
          const SizedBox(height: 20),
          const UseText(I18nKey.settingsTerminalCustomBaseColors),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final controls = [
                _ColorSettingTile(
                  label: I18nKey.settingsTerminalCustomForeground,
                  color: foreground,
                  onChanged: (color) =>
                      ref.read(terminalCustomForeground.notifier).state = color
                          .toARGB32(),
                ),
                _ColorSettingTile(
                  label: I18nKey.settingsTerminalCustomBackground,
                  color: background,
                  onChanged: (color) =>
                      ref.read(terminalCustomBackground.notifier).state = color
                          .toARGB32(),
                ),
              ];
              if (constraints.maxWidth >= 520) {
                return Row(
                  children: [
                    Expanded(child: controls[0]),
                    const SizedBox(width: 12),
                    Expanded(child: controls[1]),
                  ],
                );
              }
              return Column(
                children: [controls[0], const SizedBox(height: 8), controls[1]],
              );
            },
          ),
          // const SizedBox(height: 20),
          // const UseText(I18nKey.settingsTerminalCustomPalette),
          // const SizedBox(height: 8),
          // LayoutBuilder(
          //   builder: (context, constraints) {
          //     final columns = constraints.maxWidth >= 720
          //         ? 8
          //         : constraints.maxWidth >= 360
          //         ? 4
          //         : 2;
          //     return GridView.builder(
          //       shrinkWrap: true,
          //       physics: const NeverScrollableScrollPhysics(),
          //       gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          //         crossAxisCount: columns,
          //         crossAxisSpacing: 8,
          //         mainAxisSpacing: 8,
          //         childAspectRatio: 1.2,
          //       ),
          //       itemCount: palette.length,
          //       itemBuilder: (context, index) => _PaletteColorButton(
          //         index: index,
          //         color: Color(palette[index]),
          //         onChanged: (color) {
          //           final updated = [...palette];
          //           updated[index] = color.toARGB32();
          //           ref.read(terminalCustomPalette.notifier).state = updated;
          //         },
          //       ),
          //     );
          //   },
          // ),
        ],
      ),
    );
  }
}

class _TerminalCustomColorsSection extends StatelessWidget {
  const _TerminalCustomColorsSection();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExpansionTile(
      key: const Key('terminal-custom-colors-expansion'),
      initiallyExpanded: false,
      leading: Icon(Icons.palette_outlined, color: scheme.primary),
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      childrenPadding: EdgeInsets.zero,
      shape: const Border(),
      collapsedShape: const Border(),
      title: UseText(
        I18nKey.settingsTerminalCustomSection,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: UseText(
        I18nKey.settingsTerminalCustomSectionDescription,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
      children: const [_TerminalCustomColors()],
    );
  }
}

class _TerminalColorPreview extends StatelessWidget {
  const _TerminalColorPreview({
    required this.foreground,
    required this.background,
    required this.palette,
  });

  final Color foreground;
  final Color background;
  final List<int> palette;

  @override
  Widget build(BuildContext context) {
    final colors = palette.length == 16
        ? palette.map(Color.new).toList()
        : kDefaultTerminalCustomPalette.map(Color.new).toList();
    final terminalStyle = TextStyle(
      color: foreground,
      fontFamily: 'JetBrainsMapleMono',
      fontSize: 13,
      height: 1.45,
    );
    return Semantics(
      label: I18nKey.settingsTerminalCustomPreview.fallback,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 88),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: RichText(
          text: TextSpan(
            style: terminalStyle,
            children: [
              TextSpan(
                text: 'pyrite',
                style: TextStyle(color: colors[2]),
              ),
              TextSpan(
                text: '@workspace',
                style: TextStyle(color: colors[6]),
              ),
              const TextSpan(text: ':~\$ '),
              TextSpan(
                text: 'flutter test\n',
                style: TextStyle(color: colors[4]),
              ),
              TextSpan(
                text: 'PASS',
                style: TextStyle(color: colors[10]),
              ),
              const TextSpan(text: ' 10 tests  '),
              TextSpan(
                text: '0 failed',
                style: TextStyle(color: colors[11]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorSettingTile extends StatelessWidget {
  const _ColorSettingTile({
    required this.label,
    required this.color,
    required this.onChanged,
  });

  final I18nKey label;
  final Color color;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showColorDialog(context, label, color, onChanged),
      child: Container(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  UseText(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    _colorHex(color),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontFamily: 'JetBrainsMapleMono',
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20),
          ],
        ),
      ),
    );
  }
}

// class _PaletteColorButton extends StatelessWidget {
//   const _PaletteColorButton({
//     required this.index,
//     required this.color,
//     required this.onChanged,
//   });

//   final int index;
//   final Color color;
//   final ValueChanged<Color> onChanged;

//   @override
//   Widget build(BuildContext context) {
//     final label = 'ANSI $index';
//     return Tooltip(
//       message: '$label · ${_colorHex(color)}',
//       child: InkWell(
//         onTap: () => _showColorDialog(context, label, color, onChanged),
//         borderRadius: BorderRadius.circular(6),
//         child: Container(
//           padding: const EdgeInsets.all(6),
//           decoration: BoxDecoration(
//             borderRadius: BorderRadius.circular(6),
//             border: Border.all(
//               color: Theme.of(context).colorScheme.outlineVariant,
//             ),
//           ),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Expanded(
//                 child: Container(
//                   width: double.infinity,
//                   decoration: BoxDecoration(
//                     color: color,
//                     borderRadius: BorderRadius.circular(3),
//                     border: Border.all(
//                       color: Theme.of(context).colorScheme.outline,
//                     ),
//                   ),
//                 ),
//               ),
//               const SizedBox(height: 4),
//               Text(label, style: Theme.of(context).textTheme.labelSmall),
//               Text(
//                 _colorHex(color),
//                 maxLines: 1,
//                 overflow: TextOverflow.ellipsis,
//                 style: Theme.of(context).textTheme.labelSmall?.copyWith(
//                   color: Theme.of(context).colorScheme.onSurfaceVariant,
//                   fontFamily: 'JetBrainsMapleMono',
//                   fontSize: 10,
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }

Future<void> _confirmResetCustomColors(
  BuildContext context,
  WidgetRef ref,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const UseText(I18nKey.settingsTerminalCustomResetConfirmTitle),
      content: const UseText(I18nKey.settingsTerminalCustomResetConfirmMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const UseText(I18nKey.commonCancel),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.restart_alt),
          label: const UseText(I18nKey.settingsTerminalCustomReset),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  ref.read(terminalCustomForeground.notifier).state =
      kDefaultTerminalCustomForeground;
  ref.read(terminalCustomBackground.notifier).state =
      kDefaultTerminalCustomBackground;
  ref.read(terminalCustomPalette.notifier).state =
      kDefaultTerminalCustomPalette;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: UseText(I18nKey.settingsTerminalCustomResetDone)),
  );
}

String _colorHex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

Future<void> _showColorDialog(
  BuildContext context,
  Object title,
  Color initial,
  ValueChanged<Color> onChanged,
) async {
  var selected = initial;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: UseText(title),
        content: SingleChildScrollView(
          child: ColorPicker(
            color: selected,
            onColorChanged: (color) => setState(() => selected = color),
            pickersEnabled: const {
              ColorPickerType.primary: true,
              ColorPickerType.accent: true,
              ColorPickerType.wheel: true,
            },
            enableShadesSelection: false,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const UseText(I18nKey.commonCancel),
          ),
          FilledButton(
            onPressed: () {
              onChanged(selected);
              Navigator.pop(context);
            },
            child: const UseText(I18nKey.commonSave),
          ),
        ],
      ),
    ),
  );
}
