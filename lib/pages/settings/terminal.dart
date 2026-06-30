import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/serial/android_usb_serial_provider.dart';
import 'package:pyrite_ide/core/services/serial/desktop_usb_serial_provider.dart';
import 'package:pyrite_ide/core/services/serial/web_repl_provider.dart';
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
    final serialProvider = Platform.isAndroid
        ? androidUsbSerialProvider
        : desktopUsbSerialProvider;
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
              onTap: () => _showBaudRateDialog(
                context,
                ref,
                serialState.baudRate as int,
              ),
            ),
            const SectionDivider(),
            SwitchListTile(
              title: const Text("自动重连"),
              subtitle: const Text("断开后自动尝试重新连接"),
              value: serialState.autoReconnect as bool,
              onChanged: (value) {
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
            const SectionDivider(),
            SwitchListTile(
              title: const Text("信号检测断开"),
              subtitle: const Text("通过串口信号线检测设备是否断开，兼容常见 USB 串口芯片"),
              value: ref.watch(enableSignalDetection),
              onChanged: (value) {
                ref.read(enableSignalDetection.notifier).state = value;
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
          description: "通过 WiFi WebSocket 连接 MicroPython 设备。",
          children: [
            SwitchListTile(
              title: const Text("启用 WebREPL"),
              subtitle: const Text("通过 WiFi 连接到设备的 WebREPL 服务"),
              value: ref.watch(webReplProvider).state != WebReplState.disconnected,
              onChanged: (value) {
                if (value) {
                  ref.read(webReplProvider.notifier).connect();
                } else {
                  ref.read(webReplProvider.notifier).disconnect();
                }
              },
            ),
            const SectionDivider(),
            ListTile(
              leading: const Icon(Icons.wifi),
              title: const Text("设备 IP 地址"),
              subtitle: Text(ref.watch(webReplHost).isEmpty
                  ? "未设置"
                  : ref.watch(webReplHost)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showInputDialog(
                context,
                ref,
                "设备 IP 地址",
                "例如 192.168.1.100",
                ref.read(webReplHost),
                (value) =>
                    ref.read(webReplHost.notifier).state = value.trim(),
              ),
            ),
            const SectionDivider(),
            ListTile(
              leading: const Icon(Icons.numbers),
              title: const Text("端口"),
              subtitle: Text("${ref.watch(webReplPort)}"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showPortDialog(context, ref),
            ),
            const SectionDivider(),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text("密码"),
              subtitle: Text(ref.watch(webReplPassword).isEmpty
                  ? "未设置"
                  : "已设置"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showInputDialog(
                context,
                ref,
                "WebREPL 密码",
                "设备的 WebREPL 访问密码",
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

  void _showInputDialog(
    BuildContext context,
    WidgetRef ref,
    String title,
    String hint,
    String currentValue,
    void Function(String) onSaved,
  ) {
    final controller = TextEditingController(text: currentValue);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("取消"),
          ),
          FilledButton(
            onPressed: () {
              onSaved(controller.text);
              Navigator.pop(context);
            },
            child: const Text("保存"),
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
        title: const Text("WebREPL 端口"),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: "默认 8266",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("取消"),
          ),
          FilledButton(
            onPressed: () {
              final port = int.tryParse(controller.text.trim());
              if (port != null && port > 0 && port <= 65535) {
                ref.read(webReplPort.notifier).state = port;
                Navigator.pop(context);
              }
            },
            child: const Text("保存"),
          ),
        ],
      ),
    );
  }
}
