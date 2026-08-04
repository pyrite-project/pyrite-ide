import 'package:flutter/material.dart';
import 'package:pyrite_ide/core/sdk/component_schema.dart';

/// Renders schema problems inline instead of letting a malformed component tree
/// take down the surrounding IDE page.
///
/// A plugin that sends an unknown component or a mistyped property gets a
/// diagnosable panel listing each problem with its path, which is far more
/// useful than a red screen or a silently blank view.
class ComponentErrorBoundary extends StatelessWidget {
  const ComponentErrorBoundary({
    super.key,
    required this.diagnostics,
    this.title,
    this.compact = false,
  });

  final List<ComponentDiagnostic> diagnostics;
  final String? title;

  /// Compact mode is used when the failure is nested inside an otherwise valid
  /// tree, so only the offending subtree is replaced.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: EdgeInsets.all(compact ? 8 : 12),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.35),
        border: Border.all(color: scheme.error.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 16, color: scheme.error),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  title ?? 'Plugin view could not be rendered',
                  style: textTheme.labelLarge?.copyWith(color: scheme.error),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final diagnostic in diagnostics.take(compact ? 3 : 20))
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SelectableText(
                '${diagnostic.path}: ${diagnostic.message}',
                style: textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          if (diagnostics.length > (compact ? 3 : 20))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '… and ${diagnostics.length - (compact ? 3 : 20)} more',
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
