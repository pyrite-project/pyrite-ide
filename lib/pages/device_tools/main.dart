import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/serial/serial_provider.dart';
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
    final state = ref.watch(serialProvider);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: buildConnectionSummary(
            context,
            state.isConnected,
            state.selectedPortName,
            compact: widget.compact,
            onDisconnect: state.isConnected
                ? () =>
                      ref.read(serialProvider.notifier).disconnectPort()
                : null,
            onDeviceStatus: state.isConnected
                ? () =>
                      setState(() => _showDeviceStatus = !_showDeviceStatus)
                : null,
            showDeviceStatus: _showDeviceStatus,
          ),
        ),
        if (_showDeviceStatus && state.isConnected)
          SliverToBoxAdapter(
            child: SizedBox(height: 270, child: const DeviceStatusPanel()),
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
                  ref.read(serialProvider.notifier).refresh(),
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
                            .read(serialProvider.notifier)
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
                isConnected
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
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
                          ? selectedPortName ??
                                I18nKey.devicesSerialConnected
                          : I18nKey.devicesConnectionHint,
                      style:
                          Theme.of(context).textTheme.bodySmall?.copyWith(
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

  Widget buildDetailListTile(
    BuildContext context,
    String name,
    String? value,
  ) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: UseText(value ?? I18nKey.devicesUnknown),
      subtitle: Text(name),
    );
  }
}
