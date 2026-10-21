import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/git/git_models.dart';
import 'package:pyrite_ide/core/services/git/git_provider.dart';

/// Git blame gutter：按行显示 author / 时间 / 短 sha，可折叠。
///
/// 取舍说明：
/// - 做成独立 widget 而不是塞进 2688 行的 `main.dart`，页面里只留一个入口；
/// - 用 `ListView.builder` + 单行高度固定值，避免为每行建 blame hunk 子控件；
/// - 默认折叠，只有用户显式展开才发 `blame` 请求，因此不会给现有 Diff 视图
///   带来额外延迟；折叠状态由本 widget 自己持有，不污染 [GitViewState]。
class GitBlameGutter extends ConsumerStatefulWidget {
  const GitBlameGutter({
    super.key,
    required this.filePath,
    this.maxHeight = 260,
  });

  /// 需要展示 blame 的文件（相对仓库根的路径）。
  final String filePath;

  /// 展开后列表的最大高度，超出后内部滚动。
  final double maxHeight;

  @override
  ConsumerState<GitBlameGutter> createState() => _GitBlameGutterState();
}

class _GitBlameGutterState extends ConsumerState<GitBlameGutter> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gitProvider);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isForThisFile = state.blamePath == widget.filePath;
    final lines = isForThisFile ? state.blame : const <GitBlameLine>[];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: state.isBusy ? null : _toggle,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 6, 6),
              child: Row(
                children: [
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.person_outline,
                    size: 15,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _headerLabel(lines),
                      style: textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_expanded && lines.isNotEmpty)
                    Text(
                      '${lines.length} 行',
                      style: textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  if (state.isBusy && _expanded)
                    const Padding(
                      padding: EdgeInsetsDirectional.only(start: 6),
                      child: SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_expanded)
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: widget.maxHeight),
              child: lines.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(30, 0, 10, 10),
                      child: Text(
                        '${widget.filePath} 还没有 commit 可以归因。',
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: lines.length,
                      itemExtent: 20,
                      itemBuilder: (context, index) =>
                          _BlameRow(line: lines[index], isEven: index.isEven),
                    ),
            ),
        ],
      ),
    );
  }

  String _headerLabel(List<GitBlameLine> lines) {
    // i18n key 表不在本次改动范围内，这里沿用页面既有做法用中文字面量；
    // 后续统一抽 key 时只需要替换这两处文案。
    final label = _expanded ? '隐藏 blame' : '显示 blame';
    if (lines.isEmpty && !_expanded) return label;
    return '$label · ${widget.filePath}';
  }

  void _toggle() {
    final next = !_expanded;
    setState(() => _expanded = next);
    final notifier = ref.read(gitProvider.notifier);
    if (!next) {
      // 折叠时保留已取到的数据，避免重复请求；只清掉“正在为别的文件展示”。
      return;
    }
    notifier.showBlame(widget.filePath);
  }
}

class _BlameRow extends StatelessWidget {
  const _BlameRow({required this.line, required this.isEven});

  final GitBlameLine line;
  final bool isEven;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
      color: line.commitSha.isEmpty
          ? scheme.onSurfaceVariant.withValues(alpha: 0.6)
          : scheme.onSurfaceVariant,
    );
    return ColoredBox(
      color: isEven
          ? Colors.transparent
          : scheme.surfaceContainerHighest.withValues(alpha: 0.25),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 30, end: 10),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Text(
                '${line.lineStart}',
                textAlign: TextAlign.right,
                style: style,
                overflow: TextOverflow.clip,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 62,
              child: Text(
                line.commitSha.isEmpty ? '—' : line.shortSha,
                style: style?.copyWith(fontFamily: 'monospace'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                line.author.isEmpty ? '—' : line.author,
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 84,
              child: Text(
                _dateLabel(line.time),
                style: style,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _dateLabel(DateTime? time) {
    if (time == null) return '';
    final local = time.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}
