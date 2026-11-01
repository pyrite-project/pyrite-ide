import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/serial/serial_provider.dart';
import 'package:pyrite_ide/core/services/serial/web_repl_provider.dart';
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
    final webReplState = ref.watch(webReplProvider).state;
    final webReplActive =
        webReplState == WebReplState.waitingPassword ||
        webReplState == WebReplState.connected;
    final compact =
        widget.compact || ref.watch(themeStyle) == ThemeStyle.compact;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: buildConnectionSummary(
            context,
            state.isConnected,
            state.selectedPortName,
            compact: compact,
            onDisconnect: state.isConnected
                ? () => ref.read(serialProvider.notifier).disconnectPort()
                : null,
            onDeviceStatus: state.isConnected
                ? () => setState(() => _showDeviceStatus = !_showDeviceStatus)
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
            compact: compact,
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
              onAction: () => ref.read(serialProvider.notifier).refresh(),
            ),
          )
        else
          SliverList.builder(
            itemCount: state.portNames.length,
            itemBuilder: (context, index) {
              final portInfo = state.portInfos[index];
              final sessions = ref
                  .read(serialProvider.notifier)
                  .sessions
                  .sessions;
              final session = sessions
                  .where((item) => item.portPath == portInfo.path)
                  .firstOrNull;
              final isActive = session?.isActive ?? false;
              return ExpansionTile(
                visualDensity: compact ? VisualDensity.compact : null,
                leading: Icon(
                  isActive
                      ? Icons.check_circle
                      : session != null
                      ? Icons.usb
                      : Icons.developer_board_outlined,
                  color: isActive
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                title: Text(portInfo.path),
                subtitle: Text(
                  isActive
                      ? translateInContext(
                          context,
                          I18nKey.devicesSessionActive,
                        )
                      : session != null
                      ? translateInContext(
                          context,
                          I18nKey.devicesSessionInactive,
                        )
                      : portInfo.description,
                ),
                childrenPadding: EdgeInsetsDirectional.fromSTEB(
                  16,
                  0,
                  16,
                  compact ? 8 : 12,
                ),
                children: [
                  if (session == null)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: webReplActive
                            ? null
                            : () {
                                ref
                                    .read(serialProvider.notifier)
                                    .connectPort(portInfo.path);
                              },
                        icon: const Icon(Icons.power_settings_new),
                        label: const UseText(I18nKey.devicesConnectSerial),
                      ),
                    )
                  else
                    // The port is already open. Connecting it again would only
                    // switch to it, so the two actions are labelled for what
                    // they do instead of offering "connect" a second time.
                    Row(
                      children: [
                        if (!isActive)
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: () => ref
                                  .read(serialProvider.notifier)
                                  .activateSession(session.id),
                              icon: const Icon(Icons.swap_horiz),
                              label: Text(
                                translateInContext(
                                  context,
                                  I18nKey.devicesSessionSwitch,
                                ),
                              ),
                            ),
                          )
                        else
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                translateInContext(
                                  context,
                                  I18nKey.devicesSessionInUse,
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => ref
                              .read(serialProvider.notifier)
                              .closeSessionFor(portInfo.path),
                          icon: const Icon(Icons.link_off),
                          label: Text(
                            translateInContext(
                              context,
                              I18nKey.devicesSessionDisconnect,
                            ),
                          ),
                        ),
                      ],
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
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
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
                    if (isConnected)
                      UseText(
                        selectedPortName ?? I18nKey.devicesSerialConnected,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onPrimaryContainer,
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
