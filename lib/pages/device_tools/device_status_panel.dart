import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/models/device_status.dart';
import 'package:pyrite_ide/core/services/serial/utils.dart';
import 'package:pyrite_ide/core/services/serial/device_status_provider.dart';
import 'package:pyrite_ide/shared/md3_widgets.dart';

class DeviceStatusPanel extends ConsumerWidget {
  const DeviceStatusPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isConnected = ref.watch(getUsbSerialProvider()).isConnected;
    final statusAsync = ref.watch(deviceStatusProvider);

    return Column(
      children: [
        PaneHeader(
          title: "设备状态",
          subtitle: isConnected ? "已连接 · 点击刷新设备信息" : "请先连接设备",
          leadingIcon: Icons.memory,
          actions: [
            IconButton(
              tooltip: isConnected ? "刷新设备状态" : "请先连接设备",
              onPressed: isConnected
                  ? () => ref.read(deviceStatusProvider.notifier).refresh()
                  : null,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        Expanded(
          child: statusAsync.when(
            loading: () => const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text("正在查询设备状态..."),
                ],
              ),
            ),
            error: (err, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 36,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 8),
                    Text("查询失败", style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      err.toString(),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: () =>
                          ref.read(deviceStatusProvider.notifier).refresh(),
                      child: const Text("重试"),
                    ),
                  ],
                ),
              ),
            ),
            data: (status) {
              if (status == null) {
                return _buildEmptyState(context, ref, isConnected);
              }
              return _buildStatusContent(context, status);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    WidgetRef ref,
    bool isConnected,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.info_outline,
              size: 40,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(height: 12),
            Text(
              isConnected ? "点击上方刷新按钮查询设备状态" : "请先在设备管理中连接设备",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (isConnected) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () =>
                    ref.read(deviceStatusProvider.notifier).refresh(),
                child: const Text("查询设备状态"),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusContent(BuildContext context, DeviceStatus status) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildResourceSection(
            context,
            title: "RAM",
            icon: Icons.memory,
            used: status.ramUsedDisplay,
            total: status.ramTotalDisplay,
            usage: status.ramUsage,
          ),
          const SizedBox(height: 16),
          _buildResourceSection(
            context,
            title: "Flash",
            icon: Icons.storage,
            used: status.flashUsedDisplay,
            total: status.flashTotalDisplay,
            usage: status.flashUsage,
          ),
          const SizedBox(height: 20),
          Divider(color: scheme.outlineVariant),
          const SizedBox(height: 12),
          _buildInfoRow(
            context,
            label: "固件版本",
            value: status.firmwareVersion,
            icon: Icons.code,
          ),
          const SizedBox(height: 8),
          _buildInfoRow(
            context,
            label: "平台型号",
            value: status.platformModel,
            icon: Icons.developer_board_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildResourceSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required String used,
    required String total,
    required double usage,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final clamped = usage.clamp(0.0, 1.0);
    final color = clamped > 0.85
        ? scheme.error
        : clamped > 0.6
        ? scheme.tertiary
        : scheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Text(
              "$used / $total",
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: clamped,
            minHeight: 8,
            backgroundColor: scheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Text(
            "${(clamped * 100).toStringAsFixed(1)}%",
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}
