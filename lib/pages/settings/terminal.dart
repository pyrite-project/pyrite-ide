import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/board_manager/android_usb_serial_provider.dart';
import 'package:pyrite_ide/core/services/board_manager/desktop_usb_serial_provider.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/shared/md3_widgets.dart';

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
    final serialProvider =
        Platform.isAndroid ? androidUsbSerialProvider : desktopUsbSerialProvider;
    final serialState = ref.watch(serialProvider) as dynamic;

    final body = ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SettingsSection(
          title: "串口设置",
          description: "配置开发板的串口连接参数。",
          children: [
            ListTile(
              leading: const Icon(Icons.speed),
              title: const Text("波特率"),
              subtitle: Text("${serialState.baudRate} baud"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showBaudRateDialog(context, ref, serialState.baudRate as int),
            ),
            const SectionDivider(),
            SwitchListTile(
              title: const Text("自动重连"),
              subtitle: const Text("断开后自动尝试重新连接"),
              value: serialState.autoReconnect as bool,
              onChanged: (value) {
                if (Platform.isAndroid) {
                  ref.read(androidUsbSerialProvider.notifier).setAutoReconnect(value);
                } else {
                  ref.read(desktopUsbSerialProvider.notifier).setAutoReconnect(value);
                }
              },
            ),
            const SectionDivider(),
            SwitchListTile(
              title: const Text("中文转 Unicode"),
              subtitle: const Text("输入中文时自动转为 \\uXXXX 转义序列"),
              value: ref.watch(chineseToUnicodeConversion),
              onChanged: (value) {
                ref.read(chineseToUnicodeConversion.notifier).state = value;
              },
            ),
          ],
        ),
        SettingsSection(
          title: "WebREPL",
          description: "通过 WebSocket 连接的远程 REPL。",
          children: [
            const ListTile(
              leading: Icon(Icons.wifi),
              title: Text("WebREPL 连接"),
              subtitle: Text("固件需支持 webrepl 模块"),
              trailing: PillBadge(label: "即将支持"),
            ),
          ],
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const Text("调试与终端")),
      body: body,
    );
  }

  void _showBaudRateDialog(BuildContext context, WidgetRef ref, int current) {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text("选择波特率"),
        children: kAvailableBaudRates.map((rate) {
          final selected = rate == current;
          return SimpleDialogOption(
            child: ListTile(
              title: Text("$rate baud"),
              trailing: selected ? const Icon(Icons.check) : null,
              minTileHeight: 0,
              onTap: () {
                if (Platform.isAndroid) {
                  ref.read(androidUsbSerialProvider.notifier).setBaudRate(rate);
                } else {
                  ref.read(desktopUsbSerialProvider.notifier).setBaudRate(rate);
                }
                Navigator.pop(context);
              },
            ),
          );
        }).toList(),
      ),
    );
  }
}
