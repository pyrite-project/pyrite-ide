import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/models/device_status.dart';
import 'package:pyrite_ide/core/services/serial/utils.dart';
import 'package:pyrite_ide/core/services/serial/device_status_provider.dart';
import 'package:pyrite_ide/shared/md3_widgets.dart';
import 'package:pyrite_ide/shared/studio_text.dart';

class DeviceStatusPanel extends ConsumerWidget {
  const DeviceStatusPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isConnected = ref.watch(getUsbSerialProvider()).isConnected;
    final statusAsync = ref.watch(deviceStatusProvider);

    return Column(
      children: [
        PaneHeader(
          title: I18nKey.devicesStatusTitle,
          subtitle: isConnected
              ? I18nKey.devicesStatusConnectedSubtitle
              : I18nKey.devicesStatusDisconnectedSubtitle,
          leadingIcon: Icons.memory,
          actions: [
            IconButton(
              tooltip: translateForWidget(
                ref,
                isConnected
                    ? I18nKey.devicesStatusRefresh
                    : I18nKey.devicesStatusDisconnectedSubtitle,
              ),
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
                  UseText(I18nKey.devicesStatusLoading),
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
                    UseText(
                      I18nKey.devicesStatusFailed,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
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
                      child: const UseText(I18nKey.devicesStatusRetry),
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
            UseText(
              isConnected
                  ? I18nKey.devicesStatusEmptyConnected
                  : I18nKey.devicesStatusEmptyDisconnected,
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
                child: const UseText(I18nKey.devicesStatusQuery),
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
            label: I18nKey.devicesStatusFirmware,
            value: status.firmwareVersion,
            icon: Icons.code,
          ),
          const SizedBox(height: 8),
          _buildInfoRow(
            context,
            label: I18nKey.devicesStatusPlatform,
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
    required Object label,
    required String value,
    required IconData icon,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        UseText(
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
