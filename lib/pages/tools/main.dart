import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/board_manager/android_usb_serial_provider.dart';
import 'package:pyrite_ide/core/services/board_manager/desktop_usb_serial_provider.dart';
import 'package:pyrite_ide/shared/md3_widgets.dart';

class Tools extends ConsumerWidget {
  const Tools({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final body = buildBoardManager(context, ref);
    if (compact) return body;
    return Scaffold(
      appBar: AppBar(title: const Text("设备管理")),
      body: body,
    );
  }

  Widget buildBoardManager(BuildContext context, WidgetRef ref) {
    if (Platform.isAndroid) {
      final state = ref.watch(androidUsbSerialProvider);
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: buildConnectionSummary(
              context,
              state.isConnected,
              state.selectedPortName,
              compact: compact,
              onDisconnect: state.isConnected
                  ? () => ref
                        .read(androidUsbSerialProvider.notifier)
                        .dicconnectPort()
                  : null,
            ),
          ),
          SliverToBoxAdapter(
            child: PaneHeader(
              title: "可用设备",
              subtitle: "选择一个 USB 串口设备连接到 REPL",
              leadingIcon: Icons.usb,
              compact: compact,
            ),
          ),
          if (state.devices.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: WorkspaceEmptyState(
                icon: Icons.usb_outlined,
                title: "未发现 USB 设备",
                message: "插入 MicroPython 开发板后，Pyrite IDE 会自动刷新设备列表。",
                actionLabel: "刷新设备列表",
                onAction: () =>
                    ref.read(androidUsbSerialProvider.notifier).refresh(),
              ),
            )
          else
            SliverList.builder(
              itemCount: state.devices.length,
              itemBuilder: (context, index) {
                final port = state.devices[index];
                return ExpansionTile(
                  leading: const Icon(Icons.developer_board_outlined),
                  title: Text(port.deviceName),
                  subtitle: Text(port.productName ?? "USB Serial"),
                  childrenPadding: const EdgeInsetsDirectional.fromSTEB(
                    16,
                    0,
                    16,
                    12,
                  ),
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          ref
                              .read(androidUsbSerialProvider.notifier)
                              .connectPort(port);
                        },
                        icon: const Icon(Icons.power_settings_new),
                        label: const Text("连接此设备"),
                      ),
                    ),
                    buildDetailListTile(
                      context,
                      'USB Device',
                      port.deviceId.toString(),
                    ),
                    buildDetailListTile(
                      context,
                      'Vendor ID',
                      port.vid?.toString(),
                    ),
                    buildDetailListTile(
                      context,
                      'Product ID',
                      port.pid?.toString(),
                    ),
                    buildDetailListTile(
                      context,
                      'Manufacturer',
                      port.manufacturerName,
                    ),
                    buildDetailListTile(
                      context,
                      'Product Name',
                      port.productName,
                    ),
                    buildDetailListTile(context, 'Serial', port.serial),
                  ],
                );
              },
            ),
        ],
      );
    } else {
      final state = ref.watch(desktopUsbSerialProvider);
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: buildConnectionSummary(
              context,
              state.isConnected,
              state.selectedPortName,
              compact: compact,
              onDisconnect: state.isConnected
                  ? () => ref
                        .read(desktopUsbSerialProvider.notifier)
                        .dicconnectPort()
                  : null,
            ),
          ),
          SliverToBoxAdapter(
            child: PaneHeader(
              title: "可用串口",
              subtitle: "选择开发板对应的串口连接到 REPL",
              leadingIcon: Icons.usb,
              compact: compact,
            ),
          ),
          if (state.portNames.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: WorkspaceEmptyState(
                icon: Icons.usb_outlined,
                title: "未发现串口",
                message: "插入 MicroPython 开发板，或检查系统串口权限后再试。",
                actionLabel: "刷新串口列表",
                onAction: () =>
                    ref.read(desktopUsbSerialProvider.notifier).refresh(),
              ),
            )
          else
            SliverList.builder(
              itemCount: state.portNames.length,
              itemBuilder: (context, index) {
                final portName = state.portNames[index];
                final port = SerialPort(portName);
                return ExpansionTile(
                  leading: const Icon(Icons.developer_board_outlined),
                  title: Text(portName),
                  subtitle: Text(port.description ?? "Serial Port"),
                  childrenPadding: const EdgeInsetsDirectional.fromSTEB(
                    16,
                    0,
                    16,
                    12,
                  ),
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          ref
                              .read(desktopUsbSerialProvider.notifier)
                              .connectPort(portName);
                        },
                        icon: const Icon(Icons.power_settings_new),
                        label: const Text("连接此串口"),
                      ),
                    ),
                    buildDetailListTile(
                      context,
                      'Description',
                      port.description,
                    ),
                    buildDetailListTile(
                      context,
                      'Transport',
                      port.transport.toString(),
                    ),
                  ],
                );
              },
            ),
        ],
      );
    }
  }

  Widget buildConnectionSummary(
    BuildContext context,
    bool isConnected,
    String? selectedPortName, {
    VoidCallback? onDisconnect,
    bool compact = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: EdgeInsets.all(compact ? 8 : 16),
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: isConnected
            ? scheme.primaryContainer
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isConnected ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isConnected ? Icons.check_circle : Icons.radio_button_unchecked,
            color: isConnected
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isConnected ? "设备已连接" : "暂未连接设备",
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  isConnected
                      ? selectedPortName ?? "已建立串口连接"
                      : "选择下方串口后，REPL 与文件同步会使用该设备。",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isConnected
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (onDisconnect != null)
            TextButton.icon(
              onPressed: onDisconnect,
              icon: const Icon(Icons.link_off, size: 18),
              label: const Text("断开"),
            ),
        ],
      ),
    );
  }

  Widget buildDetailListTile(BuildContext context, String name, String? value) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(value ?? "未知"),
      subtitle: Text(name),
    );
  }
}
