import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/services/serial/android_usb_serial_provider.dart';
import 'package:pyrite_ide/core/services/serial/desktop_usb_serial_provider.dart';
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
                if (Platform.isAndroid) {
                  ref
                      .read(androidUsbSerialProvider.notifier)
                      .setAutoReconnect(value);
                } else {
                  ref
                      .read(desktopUsbSerialProvider.notifier)
                      .setAutoReconnect(value);
                }
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
              secondary: const Icon(Icons.format_underlined),
              title: const UseText(I18nKey.settingsTerminalUnderline),
              subtitle: const UseText(
                I18nKey.settingsTerminalUnderlineSubtitle,
              ),
              value: ref.watch(desktopTerminalEnableUnderline),
              onChanged: (value) {
                ref.read(desktopTerminalEnableUnderline.notifier).state = value;
              },
            ),
          ],
        ),
        SettingsSection(
          title: "WebREPL",
          description: I18nKey.settingsTerminalWebReplDescription,
          children: [
            SwitchListTile(
              title: const UseText(I18nKey.settingsTerminalWebReplEnable),
              subtitle: const UseText(
                I18nKey.settingsTerminalWebReplEnableSubtitle,
              ),
              value:
                  ref.watch(webReplProvider).state != WebReplState.disconnected,
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
                ref.watch(webReplHost).isEmpty
                    ? I18nKey.settingsTerminalUnset.fallback
                    : ref.watch(webReplHost),
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
                      if (Platform.isAndroid) {
                        ref
                            .read(androidUsbSerialProvider.notifier)
                            .setBaudRate(rate);
                      } else {
                        ref
                            .read(desktopUsbSerialProvider.notifier)
                            .setBaudRate(rate);
                      }
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
            onTap: () {
              ref.read(terminalFontFamily.notifier).state = name;
              Navigator.pop(context);
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
                  onChanged: (value) =>
                      ref.read(terminalFontSize.notifier).state = value,
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
