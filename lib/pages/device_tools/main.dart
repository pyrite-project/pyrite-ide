import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/device/board_identity.dart';
import 'package:pyrite_ide/core/services/device/board_identity_provider.dart';
import 'package:pyrite_ide/core/services/serial/serial_provider.dart';
import 'package:pyrite_ide/core/services/serial/web_repl_provider.dart';
import 'package:flserial/serial_scanner.dart';
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
              final identity = identifyPort(portInfo);
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
                      : identity.isKnown
                      ? Icons.memory
                      : Icons.developer_board_outlined,
                  color: isActive
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                title: Text(portInfo.path),
                subtitle: Text(
                  isActive
                      ? '已连接 · 当前设备'
                      : session != null
                      ? '已连接 · 点击切换'
                      : identity.isKnown
                      ? identity.label
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
                              label: const Text('切换到此设备'),
                            ),
                          )
                        else
                          const Expanded(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text('当前正在使用此设备'),
                            ),
                          ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => ref
                              .read(serialProvider.notifier)
                              .closeSessionFor(portInfo.path),
                          icon: const Icon(Icons.link_off),
                          label: const Text('断开'),
                        ),
                      ],
                    ),
                  buildBoardIdentityTile(context, identity, portInfo),
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

  /// Shows the USB VID/PID identification result for one port.
  ///
  /// Unknown ids are displayed as "未知" with a hint that the IDE will fall
  /// back to the persisted defaults, instead of hiding the row: a missing
  /// answer is information too, because it explains why no board defaults
  /// were applied on connect.
  Widget buildBoardIdentityTile(
    BuildContext context,
    BoardIdentity identity,
    SerialPortInfo portInfo,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final vidPid = identifyUsbIdLabel(portInfo.vid, portInfo.pid);
    final resetLabel = boardResetStrategyLabel(identity.resetStrategy);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                identity.isKnown
                    ? Icons.check_circle_outline
                    : Icons.help_outline,
                size: 16,
                color: identity.isKnown
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  identity.label,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'VID/PID: $vidPid',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '芯片家族: ${boardFamilyLabel(identity.family)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            '建议波特率: ${identity.likelyBaud} · 复位方式: $resetLabel',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            '识别来源: ${boardIdentityConfidenceLabel(identity.confidence)}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (!identity.isKnown)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '未匹配到已知板卡，连接时使用已保存的波特率与复位设置。',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

/// Formats USB ids for display, keeping an unknown value explicit.
String identifyUsbIdLabel(int? vid, int? pid) {
  final vidText = vid == null
      ? '未知'
      : '0x${vid.toRadixString(16).padLeft(4, '0').toUpperCase()}';
  final pidText = pid == null
      ? '未知'
      : '0x${pid.toRadixString(16).padLeft(4, '0').toUpperCase()}';
  return '$vidText / $pidText';
}

/// Chinese label for a chip family.
String boardFamilyLabel(BoardFamily family) {
  switch (family) {
    case BoardFamily.esp32:
      return 'ESP32';
    case BoardFamily.esp32s2:
      return 'ESP32-S2';
    case BoardFamily.esp32s3:
      return 'ESP32-S3';
    case BoardFamily.esp32c3:
      return 'ESP32-C3';
    case BoardFamily.esp32c6:
      return 'ESP32-C6';
    case BoardFamily.esp8266:
      return 'ESP8266';
    case BoardFamily.rp2040:
      return 'RP2040 / Pico';
    case BoardFamily.stm32:
      return 'STM32 / pyboard';
    case BoardFamily.k230:
      return 'K230';
    case BoardFamily.unknown:
      return '未知';
  }
}

/// Chinese label for a reset strategy.
String boardResetStrategyLabel(BoardResetStrategy strategy) {
  switch (strategy) {
    case BoardResetStrategy.none:
      return '不自动复位';
    case BoardResetStrategy.dtrPulse:
      return 'DTR 脉冲';
    case BoardResetStrategy.rtsPulse:
      return 'RTS 脉冲';
    case BoardResetStrategy.esp32:
      return 'ESP32 自动复位';
    case BoardResetStrategy.reopenPort:
      return '重开端口';
  }
}

/// Chinese label for how a board was identified.
String boardIdentityConfidenceLabel(BoardIdentityConfidence confidence) {
  switch (confidence) {
    case BoardIdentityConfidence.exact:
      return 'USB VID/PID 精确匹配';
    case BoardIdentityConfidence.description:
      return '端口描述匹配';
    case BoardIdentityConfidence.transportOnly:
      return '仅识别到 USB 转串口芯片';
    case BoardIdentityConfidence.unknown:
      return '未识别';
  }
}
