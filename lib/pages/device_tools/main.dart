import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/serial/android_usb_serial_provider.dart';
import 'package:pyrite_ide/core/services/serial/desktop_usb_serial_provider.dart';
import 'package:pyrite_ide/pages/device_tools/device_status_panel.dart';
import 'package:pyrite_ide/shared/md3_widgets.dart';
import 'package:pyrite_ide/shared/studio_text.dart';

class Tools extends ConsumerStatefulWidget {
  const Tools({super.key, this.compact = false});

  final bool compact;

  @override
  ConsumerState<Tools> createState() => _ToolsState();
}

class _ToolsState extends ConsumerState<Tools> {
  bool _showDeviceStatus = false;

  @override
  Widget build(BuildContext context) {
    final body = buildBoardManager(context);
    if (widget.compact) return body;
    return Scaffold(
      appBar: AppBar(title: const UseText(I18nKey.devicesTitle)),
      body: body,
    );
  }

  Widget buildBoardManager(BuildContext context) {
    if (Platform.isAndroid) {
      final state = ref.watch(androidUsbSerialProvider);
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: buildConnectionSummary(
              context,
              state.isConnected,
              state.selectedPortName,
              compact: widget.compact,
              onDisconnect: state.isConnected
                  ? () => ref
                        .read(androidUsbSerialProvider.notifier)
                        .dicconnectPort()
                  : null,
              onDeviceStatus: state.isConnected
                  ? () => setState(() => _showDeviceStatus = !_showDeviceStatus)
                  : null,
              showDeviceStatus: _showDeviceStatus,
            ),
          ),
          if (_showDeviceStatus && state.isConnected)
            SliverToBoxAdapter(
              child: SizedBox(height: 260, child: const DeviceStatusPanel()),
            ),
          SliverToBoxAdapter(
            child: PaneHeader(
              title: I18nKey.devicesAvailableUsbTitle,
              subtitle: I18nKey.devicesAvailableUsbSubtitle,
              leadingIcon: Icons.usb,
              compact: widget.compact,
            ),
          ),
          if (state.devices.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: WorkspaceEmptyState(
                icon: Icons.usb_outlined,
                title: I18nKey.devicesEmptyUsbTitle,
                message: I18nKey.devicesEmptyUsbMessage,
                actionLabel: I18nKey.devicesRefreshUsb,
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
                        label: const UseText(I18nKey.devicesConnectUsb),
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
              compact: widget.compact,
              onDisconnect: state.isConnected
                  ? () => ref
                        .read(desktopUsbSerialProvider.notifier)
                        .dicconnectPort()
                  : null,
              onDeviceStatus: state.isConnected
                  ? () => setState(() => _showDeviceStatus = !_showDeviceStatus)
                  : null,
              showDeviceStatus: _showDeviceStatus,
            ),
          ),
          if (_showDeviceStatus && state.isConnected)
            SliverToBoxAdapter(
              child: SizedBox(height: 260, child: const DeviceStatusPanel()),
            ),
          SliverToBoxAdapter(
            child: PaneHeader(
              title: I18nKey.devicesAvailableSerialTitle,
              subtitle: I18nKey.devicesAvailableSerialSubtitle,
              leadingIcon: Icons.usb,
              compact: widget.compact,
            ),
          ),
          if (state.portNames.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: WorkspaceEmptyState(
                icon: Icons.usb_outlined,
                title: I18nKey.devicesEmptySerialTitle,
                message: I18nKey.devicesEmptySerialMessage,
                actionLabel: I18nKey.devicesRefreshSerial,
                onAction: () =>
                    ref.read(desktopUsbSerialProvider.notifier).refresh(),
              ),
            )
          else
            SliverList.builder(
              itemCount: state.portNames.length,
              itemBuilder: (context, index) {
                final portInfo = state.portInfos[index];
                return ExpansionTile(
                  leading: const Icon(Icons.developer_board_outlined),
                  title: Text(portInfo.path),
                  subtitle: Text(portInfo.description),
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
                              .connectPort(portInfo.path);
                        },
                        icon: const Icon(Icons.power_settings_new),
                        label: const UseText(I18nKey.devicesConnectSerial),
                      ),
                    ),
                    buildDetailListTile(
                      context,
                      'Description',
                      portInfo.description,
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
    VoidCallback? onDeviceStatus,
    bool showDeviceStatus = false,
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
        borderRadius: context.effectiveRadius,
        border: Border.all(
          color: isConnected ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                    UseText(
                      isConnected
                          ? I18nKey.devicesConnected
                          : I18nKey.devicesDisconnected,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    UseText(
                      isConnected
                          ? selectedPortName ?? I18nKey.devicesSerialConnected
                          : I18nKey.devicesConnectionHint,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isConnected
                            ? scheme.onPrimaryContainer
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (onDeviceStatus != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 4),
                  child: Tooltip(
                    message: translateForWidget(
                      ref,
                      showDeviceStatus
                          ? I18nKey.devicesHideStatus
                          : I18nKey.devicesShowStatus,
                    ),
                    child: IconButton(
                      onPressed: onDeviceStatus,
                      icon: Icon(
                        showDeviceStatus
                            ? Icons.keyboard_arrow_up
                            : Icons.memory,
                        size: 20,
                      ),
                      style: IconButton.styleFrom(
                        foregroundColor: isConnected
                            ? scheme.onPrimaryContainer
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              if (onDisconnect != null)
                TextButton.icon(
                  onPressed: onDisconnect,
                  icon: const Icon(Icons.link_off, size: 18),
                  label: const UseText(I18nKey.devicesDisconnect),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildDetailListTile(BuildContext context, String name, String? value) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: UseText(value ?? I18nKey.devicesUnknown),
      subtitle: Text(name),
    );
  }
}
