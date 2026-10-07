import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/editor/problems_provider.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/features/edit_core/lsp_location_dialog.dart';
import 'package:pyrite_ide/features/edit_core/themed_code_forge.dart';

/// Bottom-panel tab listing every diagnostic of every open file.
///
/// Rows share the status bar's severity filter (errors and warnings only) and
/// the squiggles' theme-derived colors, so the panel never disagrees with
/// what the editor underlines. Clicking a row opens the file at the
/// diagnostic's position via the shared jump-to-location flow.
class ProblemsView extends ConsumerWidget {
  const ProblemsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final problems = ref.watch(problemsProvider);
    final collapsed = ref.watch(collapsedProblemFilesProvider);
    final colors = buildDiagnosticColors(context);
    final scheme = Theme.of(context).colorScheme;
    final lineStyle = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant);

    // Errors first, then warnings; within one file, document order.
    final files = problems.toList()..sort((a, b) => a.path.compareTo(b.path));
    if (files.every((file) => file.diagnostics.isEmpty)) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, color: scheme.outline, size: 32),
            const SizedBox(height: 8),
            Text(
              translateForWidget(ref, I18nKey.problemsPanelEmpty),
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    final children = <Widget>[];
    for (final file in files) {
      final relevant = [
        for (final diagnostic in file.diagnostics)
          if (diagnostic.severity == 1 || diagnostic.severity == 2) diagnostic,
      ];
      if (relevant.isEmpty) continue;
      final displayPath = file.path.replaceAll('\\', '/');
      final name = path.basename(displayPath);
      final directory = path.dirname(displayPath);
      final isCollapsed = collapsed.contains(file.path);
      children.add(
        _ProblemFileHeader(
          title: name,
          subtitle: directory == '.' ? name : directory,
          errorCount: file.errorCount,
          warningCount: file.warningCount,
          errorColor: colors.error,
          warningColor: colors.warning,
          collapsed: isCollapsed,
          onToggle: () {
            final notifier = ref.read(collapsedProblemFilesProvider.notifier);
            final next = Set<String>.from(notifier.state);
            if (!next.remove(file.path)) next.add(file.path);
            notifier.state = next;
          },
        ),
      );
      if (isCollapsed) continue;
      relevant.sort((a, b) {
        final bySeverity = a.severity.compareTo(b.severity);
        if (bySeverity != 0) return bySeverity;
        return _startLine(a).compareTo(_startLine(b));
      });
      for (final diagnostic in relevant) {
        final isError = diagnostic.severity == 1;
        final start = diagnostic.range['start'];
        final line = start is Map ? (start['line'] as num?)?.toInt() : null;
        final column = start is Map
            ? (start['character'] as num?)?.toInt()
            : null;
        children.add(
          _ProblemTile(
            message: diagnostic.message,
            icon: isError ? Icons.error_outline : Icons.warning_amber_rounded,
            iconColor: isError ? colors.error : colors.warning,
            location: line == null
                ? null
                : '${line + 1}${column == null ? '' : ':${column + 1}'}',
            locationStyle: lineStyle,
            onTap: () =>
                revealLspLocation(context, ref, file.path, line, column),
          ),
        );
      }
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  static int _startLine(LspErrors diagnostic) {
    final start = diagnostic.range['start'];
    if (start is! Map) return 0;
    return (start['line'] as num?)?.toInt() ?? 0;
  }
}

class _ProblemFileHeader extends StatelessWidget {
  const _ProblemFileHeader({
    required this.title,
    required this.subtitle,
    required this.errorCount,
    required this.warningCount,
    required this.errorColor,
    required this.warningColor,
    required this.collapsed,
    required this.onToggle,
  });

  final String title;
  final String subtitle;
  final int errorCount;
  final int warningCount;
  final Color errorColor;
  final Color warningColor;

  /// Whether this file's diagnostic rows are currently hidden.
  final bool collapsed;

  /// Expands/collapses the group. Kept separate from the row-tap flow so a
  /// mis-click on the header never jumps into a file.
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sameName = subtitle == title;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(8, 10, 12, 4),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: scheme.outlineVariant.withAlpha(80)),
            ),
          ),
          child: Row(
            children: [
              AnimatedRotation(
                turns: collapsed ? -0.25 : 0,
                duration: const Duration(milliseconds: 120),
                child: Icon(
                  Icons.keyboard_arrow_down,
                  size: 16,
                  color: scheme.outline,
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.description_outlined, size: 14, color: scheme.outline),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  sameName ? title : '$subtitle/$title',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (errorCount > 0)
                _countBadge('$errorCount', errorColor, Icons.error_outline),
              if (warningCount > 0) ...[
                const SizedBox(width: 6),
                _countBadge(
                  '$warningCount',
                  warningColor,
                  Icons.warning_amber_rounded,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _countBadge(String label, Color color, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 2),
        Text(label, style: TextStyle(color: color, fontSize: 11)),
      ],
    );
  }
}

class _ProblemTile extends StatelessWidget {
  const _ProblemTile({
    required this.message,
    required this.icon,
    required this.iconColor,
    required this.onTap,
    this.location,
    this.locationStyle,
  });

  final String message;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;
  final String? location;
  final TextStyle? locationStyle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 12, 6),
        child: Row(
          children: [
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurface),
              ),
            ),
            if (location != null) ...[
              const SizedBox(width: 8),
              Text(location!, style: locationStyle),
            ],
          ],
        ),
      ),
    );
  }
}
