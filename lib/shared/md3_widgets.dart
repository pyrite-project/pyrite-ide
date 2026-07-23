import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/shared/studio_text.dart';

extension BuildContextRadius on BuildContext {
  BorderRadius get effectiveRadius {
    final shape = Theme.of(this).cardTheme.shape;
    if (shape is RoundedRectangleBorder) {
      return shape.borderRadius.resolve(TextDirection.ltr);
    }
    return BorderRadius.circular(12);
  }
}

class PaneHeader extends StatelessWidget {
  const PaneHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leadingIcon,
    this.actions = const [],
    this.compact = false,
  });

  final Object title;
  final Object? subtitle;
  final IconData? leadingIcon;
  final List<Widget> actions;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          minHeight: compact ? 44 : (subtitle == null ? 44 : 56),
        ),
        padding: EdgeInsetsDirectional.fromSTEB(12, compact ? 4 : 6, 8, 6),

        child: Row(
          children: [
            if (leadingIcon != null) ...[
              Icon(leadingIcon, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  UseText(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null && !compact)
                    UseText(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(width: 8),
              Wrap(spacing: 2, children: actions),
            ],
          ],
        ),
      ),
    );
  }
}

class WorkspaceEmptyState extends StatelessWidget {
  const WorkspaceEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.secondaryAction,
  });

  final IconData icon;
  final Object title;
  final Object message;
  final Object actionLabel;
  final VoidCallback onAction;
  final Widget? secondaryAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: scheme.secondary),
              const SizedBox(height: 16),
              UseText(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              UseText(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(onPressed: onAction, child: UseText(actionLabel)),
              if (secondaryAction != null) ...[
                const SizedBox(height: 8),
                secondaryAction!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class PillBadge extends StatelessWidget {
  const PillBadge({
    super.key,
    required this.label,
    this.icon,
    this.containerColor,
    this.foregroundColor,
  });

  final Object label;
  final IconData? icon;
  final Color? containerColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = foregroundColor ?? scheme.onSecondaryContainer;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: containerColor ?? scheme.secondaryContainer,
        borderRadius: context.effectiveRadius,
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(8, 3, 8, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: foreground),
              const SizedBox(width: 4),
            ],
            UseText(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StatusBarButton extends StatelessWidget {
  const StatusBarButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.statusColor,
    this.tooltip,
    this.compact = false,
  });

  final Object label;
  final IconData icon;
  final VoidCallback onPressed;
  final Color? statusColor;
  final String? tooltip;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusIcon = Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon, size: 16),
        if (statusColor != null)
          PositionedDirectional(
            end: -3,
            bottom: -3,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: scheme.surfaceContainer, width: 1.5),
              ),
              child: const SizedBox(width: 8, height: 8),
            ),
          ),
      ],
    );

    final child = LayoutBuilder(
      builder: (context, constraints) {
        final hasBoundedWidth = constraints.maxWidth.isFinite;
        final minLabelWidth = compact ? 72.0 : 96.0;
        final showLabel =
            !hasBoundedWidth || constraints.maxWidth >= minLabelWidth;
        final availableWidth = hasBoundedWidth ? constraints.maxWidth : 24.0;
        final iconSize = availableWidth.clamp(0.0, 16.0).toDouble();
        final iconOnlyChild = Center(child: Icon(icon, size: iconSize));
        final labeledChild = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            statusIcon,
            SizedBox(width: compact ? 4 : 6),
            if (hasBoundedWidth)
              Flexible(
                child: UseText(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              )
            else
              UseText(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        );
        return TextButton(
          style: TextButton.styleFrom(
            foregroundColor: scheme.onSurfaceVariant,
            minimumSize: Size(showLabel ? (compact ? 44 : 56) : 0, 32),
            padding: showLabel
                ? EdgeInsetsDirectional.only(
                    start: compact ? 8 : 10,
                    end: compact ? 8 : 12,
                  )
                : EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: context.effectiveRadius,
            ),
          ),
          onPressed: onPressed,
          child: showLabel ? labeledChild : iconOnlyChild,
        );
      },
    );

    if (tooltip == null) return child;
    return Tooltip(message: tooltip!, child: child);
  }
}

class SettingsSection extends ConsumerWidget {
  const SettingsSection({
    super.key,
    required this.title,
    this.description,
    required this.children,
  });

  final Object title;
  final Object? description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  resolveI18nText(ref, title),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    resolveI18nText(ref, description!),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Column(children: children),
        ],
      ),
    );
  }
}

class SectionDivider extends StatelessWidget {
  const SectionDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 16,
      endIndent: 16,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}
