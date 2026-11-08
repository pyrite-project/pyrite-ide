import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/services/search/search_provider.dart';
import 'package:pyrite_ide/core/services/search/search_service.dart';

/// Renders grouped, collapsible search results and routes row taps through
/// [onOpenMatch] so the host page can point the current-match cursor at the
/// tapped occurrence and jump to it.
class SearchResultsView extends ConsumerWidget {
  const SearchResultsView({
    super.key,
    required this.results,
    required this.root,
    required this.currentMatch,
    required this.onOpenMatch,
  });

  final List<FileSearchResult> results;
  final Directory root;
  final FlatSearchMatch? currentMatch;
  final void Function(String filePath, int lineIndex, int rangeIndex)
  onOpenMatch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final collapsed = ref.watch(searchCollapsedProvider);
    final textTheme = Theme.of(context).textTheme;

    final files = results.toList()
      ..sort((a, b) => a.filePath.compareTo(b.filePath));

    final children = <Widget>[];
    for (final fileResult in files) {
      final relativePath = path.relative(fileResult.filePath, from: root.path);
      final name = path.basename(relativePath);
      final directory = path.dirname(relativePath);
      final isCollapsed = collapsed.contains(fileResult.filePath);

      children.add(
        _FileHeader(
          name: name,
          directory: directory == '.' ? '' : directory,
          matchCount: fileResult.matchCount,
          collapsed: isCollapsed,
          onToggle: () {
            final notifier = ref.read(searchCollapsedProvider.notifier);
            final next = Set<String>.from(notifier.state);
            if (!next.remove(fileResult.filePath)) {
              next.add(fileResult.filePath);
            }
            notifier.state = next;
          },
        ),
      );

      if (isCollapsed) continue;

      for (final match in fileResult.matches) {
        final isCurrent =
            currentMatch != null &&
            currentMatch!.filePath == fileResult.filePath &&
            currentMatch!.match.lineIndex == match.lineIndex;
        children.add(
          _MatchRow(
            match: match,
            scheme: scheme,
            isCurrent: isCurrent,
            currentRangeIndex: isCurrent ? currentMatch!.rangeIndex : -1,
            baseStyle:
                textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface,
                  fontFamily: 'monospace',
                ) ??
                const TextStyle(),
            onTap: () => onOpenMatch(fileResult.filePath, match.lineIndex, 0),
          ),
        );
      }
    }

    return ListView.builder(
      itemCount: children.length,
      itemBuilder: (context, index) => children[index],
    );
  }
}

class _FileHeader extends StatelessWidget {
  const _FileHeader({
    required this.name,
    required this.directory,
    required this.matchCount,
    required this.collapsed,
    required this.onToggle,
  });

  final String name;
  final String directory;
  final int matchCount;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
                  directory.isEmpty ? name : '$directory/$name',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$matchCount',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({
    required this.match,
    required this.scheme,
    required this.isCurrent,
    required this.currentRangeIndex,
    required this.baseStyle,
    required this.onTap,
  });

  final SearchMatch match;
  final ColorScheme scheme;
  final bool isCurrent;
  final int currentRangeIndex;
  final TextStyle baseStyle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: onTap,
        child: Container(
          // The current match gets a row-wide tint so it stands out even when
          // its line holds several occurrences.
          color: isCurrent ? scheme.primary.withAlpha(24) : null,
          padding: const EdgeInsetsDirectional.fromSTEB(28, 5, 12, 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  '${match.lineIndex + 1}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: isCurrent ? scheme.primary : scheme.onSurfaceVariant,
                    fontWeight: isCurrent ? FontWeight.w700 : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: baseStyle,
                    children: _highlightSpans(match.ranges),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<TextSpan> _highlightSpans(List<(int start, int end)> ranges) {
    if (ranges.isEmpty) return [TextSpan(text: match.lineText)];
    final spans = <TextSpan>[];
    var cursor = 0;
    for (var i = 0; i < ranges.length; i++) {
      final (start, end) = ranges[i];
      if (start < cursor) continue; // overlapping guard
      if (start > cursor) {
        spans.add(TextSpan(text: match.lineText.substring(cursor, start)));
      }
      if (end > start) {
        // The current occurrence is emphasized over the other hits on the
        // same line, mirroring the editor's find highlighting.
        final isCurrentRange = isCurrent && i == currentRangeIndex;
        spans.add(
          TextSpan(
            text: match.lineText.substring(start, end),
            style: TextStyle(
              backgroundColor: isCurrentRange
                  ? scheme.primary
                  : scheme.primaryContainer,
              color: isCurrentRange
                  ? scheme.onPrimary
                  : scheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }
      cursor = end;
    }
    if (cursor < match.lineText.length) {
      spans.add(TextSpan(text: match.lineText.substring(cursor)));
    }
    return spans;
  }
}
