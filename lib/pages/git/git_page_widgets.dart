part of 'git_page.dart';

class _GitHeader extends ConsumerWidget {
  const _GitHeader({required this.snapshot, required this.isBusy});

  final GitRepositorySnapshot snapshot;
  final bool isBusy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PaneHeader(
      title: I18nKey.gitSourceControl,
      subtitle:
          '${snapshot.branchLabel} · ${snapshot.stateLabel} · ${snapshot.rootPath}',
      leadingIcon: Icons.account_tree_outlined,
      compact: true,
      actions: [
        if (snapshot.ahead > 0 || snapshot.behind > 0)
          PillBadge(label: '↑${snapshot.ahead} ↓${snapshot.behind}'),
        TooltipAnchor(
          message: translateForWidget(ref, I18nKey.gitStageAll),
          child: IconButton(
            onPressed: isBusy || snapshot.unstagedCount == 0
                ? null
                : () => ref.read(gitProvider.notifier).stageAll(),
            icon: const Icon(Icons.add_task),
          ),
        ),
        TooltipAnchor(
          message: translateForWidget(ref, I18nKey.gitUnstageAll),
          child: IconButton(
            onPressed: isBusy || snapshot.stagedCount == 0
                ? null
                : () => ref.read(gitProvider.notifier).unstageAll(),
            icon: const Icon(Icons.remove_done_outlined),
          ),
        ),
        TooltipAnchor(
          message: translateForWidget(ref, I18nKey.commonRefresh),
          child: IconButton(
            onPressed: isBusy
                ? null
                : () => ref.read(gitProvider.notifier).refresh(),
            icon: isBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ),
      ],
    );
  }
}

class _BlockedPathList extends StatelessWidget {
  const _BlockedPathList({required this.paths});

  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 180),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: context.innerCorners,
        ),
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: paths.length,
          itemBuilder: (context, index) => Padding(
            padding: EdgeInsets.fromLTRB(12, index == 0 ? 10 : 4, 12, 4),
            child: Text(
              paths[index],
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ),
    );
  }
}

class _CommitBar extends ConsumerStatefulWidget {
  const _CommitBar({
    required this.messageController,
    required this.authorController,
    required this.emailController,
    required this.onCommit,
    required this.onStash,
    required this.isBusy,
  });

  final TextEditingController messageController;
  final TextEditingController authorController;
  final TextEditingController emailController;
  final VoidCallback onCommit;
  final VoidCallback onStash;
  final bool isBusy;

  @override
  ConsumerState<_CommitBar> createState() => _CommitBarState();
}

class _CommitBarState extends ConsumerState<_CommitBar> {
  bool _showIdentity = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canCommit =
        !widget.isBusy && widget.messageController.text.trim().isNotEmpty;
    return Material(
      color: scheme.surfaceContainerLow,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 10, 8),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.messageController,
                    minLines: 1,
                    maxLines: 2,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) {
                      if (canCommit) widget.onCommit();
                    },
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: translateForWidget(
                        ref,
                        I18nKey.gitCommitMessage,
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TooltipAnchor(
                  message: translateForWidget(ref, I18nKey.gitAuthor),
                  child: IconButton(
                    onPressed: () =>
                        setState(() => _showIdentity = !_showIdentity),
                    icon: Icon(
                      _showIdentity ? Icons.badge : Icons.badge_outlined,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                TooltipAnchor(
                  message: 'Stash',
                  child: IconButton.outlined(
                    onPressed: widget.isBusy ? null : widget.onStash,
                    icon: const Icon(Icons.inventory_2_outlined),
                  ),
                ),
                const SizedBox(width: 4),
                FilledButton.icon(
                  onPressed: canCommit ? widget.onCommit : null,
                  icon: const Icon(Icons.check),
                  label: const UseText(I18nKey.gitCommit),
                ),
              ],
            ),
            if (_showIdentity)
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: widget.authorController,
                        decoration: const InputDecoration(
                          isDense: true,
                          label: UseText(I18nKey.gitAuthor),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: widget.emailController,
                        decoration: const InputDecoration(
                          isDense: true,
                          label: UseText(I18nKey.gitEmail),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BranchTile extends ConsumerWidget {
  const _BranchTile({
    required this.branch,
    required this.isBusy,
    required this.onCheckout,
    required this.onDelete,
    this.onRename,
  });

  final GitBranchInfo branch;
  final bool isBusy;
  final VoidCallback onCheckout;
  final VoidCallback onDelete;
  final VoidCallback? onRename;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final details = <String>[
      branch.targetSha.length > 7
          ? branch.targetSha.substring(0, 7)
          : branch.targetSha,
      if (branch.upstream.isNotEmpty) branch.upstream,
      if (branch.trackingLabel.isNotEmpty) branch.trackingLabel,
    ];
    final row = SizedBox(
      height: 40,
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 4),
        child: Row(
          children: [
            Icon(
              branch.isRemote ? Icons.cloud_outlined : Icons.account_tree,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    branch.name,
                    style: textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    details.join(' · '),
                    style: textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (branch.trackingLabel.isNotEmpty)
              PillBadge(label: branch.trackingLabel),
            _BranchActionSlot(
              isCurrent: branch.isCurrent,
              onCheckout: isBusy ? null : onCheckout,
            ),
            if (!branch.isRemote)
              TooltipAnchor(
                message: translateInContext(
                  context,
                  I18nKey.gitTooltipRenameBranch,
                ),
                child: IconButton(
                  onPressed: isBusy || onRename == null ? null : onRename,
                  icon: const Icon(Icons.drive_file_rename_outline),
                ),
              ),
            TooltipAnchor(
              message: translateInContext(
                context,
                I18nKey.gitTooltipDeleteBranch,
              ),
              child: IconButton(
                onPressed: isBusy ? null : onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ),
          ],
        ),
      ),
    );

    return PyriteContextMenuWidget(
      child: row,
      menuProvider: (request) {
        return Menu(
          children: [
            MenuAction(
              title: translateForWidget(ref, I18nKey.gitCheckout),
              callback: onCheckout,
              attributes: MenuActionAttributes(
                disabled: isBusy || branch.isCurrent,
              ),
            ),
            if (!branch.isRemote)
              MenuAction(
                title: translateInContext(context, I18nKey.gitMenuRenameBranch),
                callback: onRename ?? () {},
                attributes: MenuActionAttributes(
                  disabled: isBusy || onRename == null,
                ),
              ),
            MenuSeparator(),
            MenuAction(
              title: translateInContext(context, I18nKey.gitMenuDeleteBranch),
              callback: onDelete,
              attributes: MenuActionAttributes(disabled: isBusy),
            ),
          ],
        );
      },
    );
  }
}

/// 分支行右侧动作位的居中槽位：「切换」按钮与「当前」徽标共用。
///
/// 两种状态互斥，但盒子宽度不同（按钮有 12dp 内边距、徽标只有 8dp），
/// 直接相邻排列会让右边缘对齐、文字中心错开。这里让两个候选子节点都参与
/// 布局（只绘制其中一个），槽位宽度取二者较大值并把内容居中，于是两种
/// 状态的文字中心始终落在同一条竖线上；宽度也随文案自适应，换成更长的
/// 语言不会被裁切。
class _BranchActionSlot extends StatelessWidget {
  const _BranchActionSlot({required this.isCurrent, required this.onCheckout});

  final bool isCurrent;
  final VoidCallback? onCheckout;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        _reserve(
          visible: !isCurrent,
          child: TextButton(
            onPressed: onCheckout,
            child: const UseText(I18nKey.gitCheckout),
          ),
        ),
        _reserve(
          visible: isCurrent,
          child: const PillBadge(label: I18nKey.gitCurrentBranch),
        ),
      ],
    );
  }

  /// 隐藏时仍保留占位与布局，只是不绘制、不响应点击。
  Widget _reserve({required bool visible, required Widget child}) {
    return Visibility(
      visible: visible,
      maintainSize: true,
      maintainAnimation: true,
      maintainState: true,
      child: child,
    );
  }
}

class _RemoteTile extends ConsumerWidget {
  const _RemoteTile({
    required this.remote,
    required this.isBusy,
    required this.onFetch,
    required this.onPull,
    required this.onPush,
    required this.onEditUrl,
    required this.onRename,
    required this.onDelete,
  });

  final GitRemoteInfo remote;
  final bool isBusy;
  final VoidCallback onFetch;
  final VoidCallback onPull;
  final VoidCallback onPush;
  final VoidCallback onEditUrl;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsetsDirectional.only(bottom: 4),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 2, 4),
        child: Row(
          children: [
            Icon(Icons.cloud_queue, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    remote.name,
                    style: textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    remote.url,
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            TooltipAnchor(
              message: translateForWidget(ref, I18nKey.gitFetch),
              child: IconButton(
                onPressed: isBusy ? null : onFetch,
                icon: const Icon(Icons.cloud_download_outlined),
              ),
            ),
            TooltipAnchor(
              message: translateForWidget(ref, I18nKey.gitPull),
              child: IconButton(
                onPressed: isBusy ? null : onPull,
                icon: const Icon(Icons.download_for_offline_outlined),
              ),
            ),
            TooltipAnchor(
              message: translateForWidget(ref, I18nKey.gitPush),
              child: IconButton(
                onPressed: isBusy ? null : onPush,
                icon: const Icon(Icons.cloud_upload_outlined),
              ),
            ),
            PyriteContextMenuWidget(
              child: TooltipAnchor(
                message: translateInContext(
                  context,
                  I18nKey.gitTooltipRemoteSettings,
                ),
                child: IconButton(
                  onPressed: isBusy ? null : onEditUrl,
                  icon: const Icon(Icons.more_vert),
                ),
              ),
              menuProvider: (request) => Menu(
                children: [
                  MenuAction(
                    title: translateInContext(context, I18nKey.gitMenuEditUrl),
                    callback: onEditUrl,
                    attributes: MenuActionAttributes(disabled: isBusy),
                  ),
                  MenuAction(
                    title: translateInContext(
                      context,
                      I18nKey.gitMenuRenameRemote,
                    ),
                    callback: onRename,
                    attributes: MenuActionAttributes(disabled: isBusy),
                  ),
                  MenuSeparator(),
                  MenuAction(
                    title: translateForWidget(ref, I18nKey.gitDelete),
                    callback: onDelete,
                    attributes: MenuActionAttributes(disabled: isBusy),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RebaseActions extends StatelessWidget {
  const _RebaseActions({
    required this.isBusy,
    required this.onContinue,
    required this.onAbort,
  });

  final bool isBusy;
  final VoidCallback onContinue;
  final VoidCallback onAbort;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.tonalIcon(
            onPressed: isBusy ? null : onContinue,
            icon: const Icon(Icons.play_arrow),
            label: const UseText(I18nKey.gitContinueRebase),
          ),
          OutlinedButton.icon(
            onPressed: isBusy ? null : onAbort,
            icon: const Icon(Icons.cancel_outlined),
            label: const UseText(I18nKey.gitAbortRebase),
          ),
        ],
      ),
    );
  }
}

class _ThreeWayConflictCard extends StatelessWidget {
  const _ThreeWayConflictCard({
    required this.title,
    required this.isBusy,
    required this.onAcceptOurs,
    required this.onAcceptTheirs,
    required this.onMarkResolved,
    required this.child,
  });

  final Object title;
  final bool isBusy;
  final VoidCallback onAcceptOurs;
  final VoidCallback onAcceptTheirs;
  final VoidCallback? onMarkResolved;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.warning_amber_outlined,
                  size: 18,
                  color: scheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: UseText(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: isBusy ? null : onAcceptOurs,
                  icon: const Icon(Icons.looks_one_outlined),
                  label: const UseText(I18nKey.gitAcceptOurs),
                ),
                FilledButton.tonalIcon(
                  onPressed: isBusy ? null : onAcceptTheirs,
                  icon: const Icon(Icons.looks_two_outlined),
                  label: const UseText(I18nKey.gitAcceptTheirs),
                ),
                OutlinedButton.icon(
                  onPressed: isBusy ? null : onMarkResolved,
                  icon: const Icon(Icons.add_task),
                  label: const UseText(I18nKey.gitMarkResolved),
                ),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _CommitHistoryTile extends StatelessWidget {
  const _CommitHistoryTile({
    required this.commit,
    required this.graphRow,
    required this.graphWidth,
    required this.isLast,
    required this.dateLabel,
  });

  final GitCommitInfo commit;
  final _CommitGraphRow graphRow;
  final double graphWidth;
  final bool isLast;
  final String dateLabel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: _commitHistoryRowHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RepaintBoundary(
            child: SizedBox(
              width: graphWidth,
              child: CustomPaint(
                painter: _CommitGraphPainter(
                  row: graphRow,
                  isLast: isLast,
                  colorScheme: scheme,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    commit.summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(height: 1.06),
                  ),
                  Text(
                    '${commit.shortSha} · ${commit.author} · $dateLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelSmall?.copyWith(
                      height: 1.02,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const double _commitHistoryRowHeight = 32;

class _CommitGraphRow {
  const _CommitGraphRow({
    required this.nodeLane,
    required this.nodeColorIndex,
    required this.hasIncoming,
    required this.laneCount,
    required this.passThroughEdges,
    required this.parentEdges,
  });

  final int nodeLane;
  final int nodeColorIndex;
  final bool hasIncoming;
  final int laneCount;
  final List<_CommitGraphEdge> passThroughEdges;
  final List<_CommitGraphEdge> parentEdges;

  double get width {
    return (((laneCount - 1) * _graphLaneSpacing) + 24)
        .clamp(32, 144)
        .toDouble();
  }

  @override
  bool operator ==(Object other) {
    return other is _CommitGraphRow &&
        nodeLane == other.nodeLane &&
        nodeColorIndex == other.nodeColorIndex &&
        hasIncoming == other.hasIncoming &&
        laneCount == other.laneCount &&
        _listEquals(passThroughEdges, other.passThroughEdges) &&
        _listEquals(parentEdges, other.parentEdges);
  }

  @override
  int get hashCode {
    return Object.hash(
      nodeLane,
      nodeColorIndex,
      hasIncoming,
      laneCount,
      Object.hashAll(passThroughEdges),
      Object.hashAll(parentEdges),
    );
  }
}

class _CommitGraphLane {
  const _CommitGraphLane({required this.sha, required this.colorIndex});

  final String sha;
  final int colorIndex;
}

class _CommitGraphEdge {
  const _CommitGraphEdge({
    required this.fromLane,
    required this.toLane,
    required this.colorIndex,
  });

  final int fromLane;
  final int toLane;
  final int colorIndex;

  @override
  bool operator ==(Object other) {
    return other is _CommitGraphEdge &&
        fromLane == other.fromLane &&
        toLane == other.toLane &&
        colorIndex == other.colorIndex;
  }

  @override
  int get hashCode => Object.hash(fromLane, toLane, colorIndex);
}

@visibleForTesting
class GitCommitGraphDebugRow {
  const GitCommitGraphDebugRow({
    required this.nodeLane,
    required this.nodeColorIndex,
    required this.hasIncoming,
    required this.laneCount,
    required this.passThroughEdges,
    required this.parentEdges,
  });

  final int nodeLane;
  final int nodeColorIndex;
  final bool hasIncoming;
  final int laneCount;
  final List<GitCommitGraphDebugEdge> passThroughEdges;
  final List<GitCommitGraphDebugEdge> parentEdges;

  @override
  bool operator ==(Object other) {
    return other is GitCommitGraphDebugRow &&
        nodeLane == other.nodeLane &&
        nodeColorIndex == other.nodeColorIndex &&
        hasIncoming == other.hasIncoming &&
        laneCount == other.laneCount &&
        _listEquals(passThroughEdges, other.passThroughEdges) &&
        _listEquals(parentEdges, other.parentEdges);
  }

  @override
  int get hashCode {
    return Object.hash(
      nodeLane,
      nodeColorIndex,
      hasIncoming,
      laneCount,
      Object.hashAll(passThroughEdges),
      Object.hashAll(parentEdges),
    );
  }

  @override
  String toString() {
    return 'GitCommitGraphDebugRow('
        'nodeLane: $nodeLane, '
        'nodeColorIndex: $nodeColorIndex, '
        'hasIncoming: $hasIncoming, '
        'laneCount: $laneCount, '
        'passThroughEdges: $passThroughEdges, '
        'parentEdges: $parentEdges'
        ')';
  }
}

@visibleForTesting
class GitCommitGraphDebugEdge {
  const GitCommitGraphDebugEdge({
    required this.fromLane,
    required this.toLane,
    this.colorIndex = 0,
  });

  final int fromLane;
  final int toLane;
  final int colorIndex;

  @override
  bool operator ==(Object other) {
    return other is GitCommitGraphDebugEdge &&
        fromLane == other.fromLane &&
        toLane == other.toLane &&
        colorIndex == other.colorIndex;
  }

  @override
  int get hashCode => Object.hash(fromLane, toLane, colorIndex);

  @override
  String toString() {
    return 'GitCommitGraphDebugEdge('
        'fromLane: $fromLane, '
        'toLane: $toLane, '
        'colorIndex: $colorIndex'
        ')';
  }
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

const double _graphLaneSpacing = 12;
const _graphLaneColors = [
  Color(0xFF3B82F6),
  Color(0xFF22C55E),
  Color(0xFFF97316),
  Color(0xFFE11D48),
  Color(0xFF8B5CF6),
  Color(0xFF14B8A6),
];

@visibleForTesting
List<GitCommitGraphDebugRow> buildGitCommitGraphRowsForTesting(
  List<GitCommitInfo> commits,
) {
  return [
    for (final row in _buildCommitGraphRows(commits))
      GitCommitGraphDebugRow(
        nodeLane: row.nodeLane,
        nodeColorIndex: row.nodeColorIndex,
        hasIncoming: row.hasIncoming,
        laneCount: row.laneCount,
        passThroughEdges: [
          for (final edge in row.passThroughEdges) _debugGraphEdge(edge),
        ],
        parentEdges: [
          for (final edge in row.parentEdges) _debugGraphEdge(edge),
        ],
      ),
  ];
}

GitCommitGraphDebugEdge _debugGraphEdge(_CommitGraphEdge edge) {
  return GitCommitGraphDebugEdge(
    fromLane: edge.fromLane,
    toLane: edge.toLane,
    colorIndex: edge.colorIndex,
  );
}

List<_CommitGraphRow> _buildCommitGraphRows(List<GitCommitInfo> commits) {
  final commitIndexesBySha = _commitIndexesBySha(commits);
  var nextColorIndex = 0;
  var lanes = <_CommitGraphLane>[];
  final rows = <_CommitGraphRow>[];

  for (var rowIndex = 0; rowIndex < commits.length; rowIndex += 1) {
    final commit = commits[rowIndex];
    lanes = _pruneCommitGraphLanes(lanes, rowIndex, commitIndexesBySha);

    var laneIndex = lanes.indexWhere((lane) => lane.sha == commit.sha);
    final hasIncoming = laneIndex != -1;
    if (laneIndex == -1) {
      lanes.add(_CommitGraphLane(sha: commit.sha, colorIndex: nextColorIndex));
      nextColorIndex += 1;
      laneIndex = lanes.length - 1;
    }

    final lanesBefore = List<_CommitGraphLane>.of(lanes);
    final nodeLane = lanesBefore[laneIndex];
    final lanesAfter = List<_CommitGraphLane>.of(lanesBefore);
    final parentEdges = <_CommitGraphEdge>[];
    final visibleParents = _visibleParentShas(
      commit.parentShas,
      rowIndex,
      commitIndexesBySha,
    );

    if (visibleParents.isEmpty) {
      lanesAfter.removeAt(laneIndex);
    } else {
      var anchorLaneIndex = laneIndex;
      for (
        var parentIndex = 0;
        parentIndex < visibleParents.length;
        parentIndex += 1
      ) {
        final parentSha = visibleParents[parentIndex];
        final parentLaneIndex = lanesAfter.indexWhere(
          (lane) => lane.sha == parentSha,
        );
        var targetLaneIndex = parentLaneIndex;
        var edgeColorIndex = parentIndex == 0
            ? nodeLane.colorIndex
            : nextColorIndex;

        if (parentIndex == 0) {
          if (parentLaneIndex == -1 || parentLaneIndex == laneIndex) {
            lanesAfter[laneIndex] = _CommitGraphLane(
              sha: parentSha,
              colorIndex: nodeLane.colorIndex,
            );
            targetLaneIndex = laneIndex;
            anchorLaneIndex = targetLaneIndex;
          } else {
            edgeColorIndex = nodeLane.colorIndex;
            final parentLane = lanesAfter[parentLaneIndex];
            final parentColorIndex = _mainlineColorIndex(
              parentLane.colorIndex,
              nodeLane.colorIndex,
            );
            lanesAfter.removeAt(laneIndex);
            targetLaneIndex = parentLaneIndex > laneIndex
                ? parentLaneIndex - 1
                : parentLaneIndex;
            lanesAfter[targetLaneIndex] = _CommitGraphLane(
              sha: parentSha,
              colorIndex: parentColorIndex,
            );
            anchorLaneIndex = targetLaneIndex;
          }
        } else if (parentLaneIndex == -1) {
          targetLaneIndex = (anchorLaneIndex + parentIndex)
              .clamp(0, lanesAfter.length)
              .toInt();
          lanesAfter.insert(
            targetLaneIndex,
            _CommitGraphLane(sha: parentSha, colorIndex: edgeColorIndex),
          );
          nextColorIndex += 1;
        } else {
          edgeColorIndex = lanesAfter[parentLaneIndex].colorIndex;
        }
        _addCommitGraphEdge(
          parentEdges,
          _CommitGraphEdge(
            fromLane: laneIndex,
            toLane: targetLaneIndex,
            colorIndex: edgeColorIndex,
          ),
        );
      }
    }

    final passThroughEdges = <_CommitGraphEdge>[];
    for (var index = 0; index < lanesBefore.length; index += 1) {
      if (index == laneIndex) continue;
      final lane = lanesBefore[index];
      final targetIndex = lanesAfter.indexWhere((item) => item.sha == lane.sha);
      if (targetIndex == -1) continue;
      _addCommitGraphEdge(
        passThroughEdges,
        _CommitGraphEdge(
          fromLane: index,
          toLane: targetIndex,
          colorIndex: lane.colorIndex,
        ),
      );
    }

    rows.add(
      _CommitGraphRow(
        nodeLane: laneIndex,
        nodeColorIndex: nodeLane.colorIndex,
        hasIncoming: hasIncoming,
        laneCount: _largestInt([
          lanesBefore.length,
          lanesAfter.length,
          laneIndex + 1,
          for (final edge in passThroughEdges) edge.fromLane + 1,
          for (final edge in passThroughEdges) edge.toLane + 1,
          for (final edge in parentEdges) edge.toLane + 1,
        ]),
        passThroughEdges: passThroughEdges,
        parentEdges: parentEdges,
      ),
    );
    lanes = lanesAfter;
  }

  return rows;
}

Map<String, List<int>> _commitIndexesBySha(List<GitCommitInfo> commits) {
  final indexesBySha = <String, List<int>>{};
  for (var index = 0; index < commits.length; index += 1) {
    indexesBySha.putIfAbsent(commits[index].sha, () => <int>[]).add(index);
  }
  return indexesBySha;
}

List<_CommitGraphLane> _pruneCommitGraphLanes(
  List<_CommitGraphLane> lanes,
  int rowIndex,
  Map<String, List<int>> commitIndexesBySha,
) {
  final seenShas = <String>{};
  final pruned = <_CommitGraphLane>[];
  for (final lane in lanes) {
    if (!seenShas.add(lane.sha)) continue;
    if (!_hasVisibleCommitAtOrAfter(commitIndexesBySha, lane.sha, rowIndex)) {
      continue;
    }
    pruned.add(lane);
  }
  return pruned;
}

List<String> _visibleParentShas(
  List<String> parentShas,
  int rowIndex,
  Map<String, List<int>> commitIndexesBySha,
) {
  final seenShas = <String>{};
  final visibleParents = <String>[];
  for (final parentSha in parentShas) {
    if (!seenShas.add(parentSha)) continue;
    if (_hasVisibleCommitAfter(commitIndexesBySha, parentSha, rowIndex)) {
      visibleParents.add(parentSha);
    }
  }
  return visibleParents;
}

bool _hasVisibleCommitAtOrAfter(
  Map<String, List<int>> commitIndexesBySha,
  String sha,
  int rowIndex,
) {
  final indexes = commitIndexesBySha[sha];
  if (indexes == null) return false;
  for (final index in indexes) {
    if (index >= rowIndex) return true;
  }
  return false;
}

bool _hasVisibleCommitAfter(
  Map<String, List<int>> commitIndexesBySha,
  String sha,
  int rowIndex,
) {
  final indexes = commitIndexesBySha[sha];
  if (indexes == null) return false;
  for (final index in indexes) {
    if (index > rowIndex) return true;
  }
  return false;
}

void _addCommitGraphEdge(List<_CommitGraphEdge> edges, _CommitGraphEdge edge) {
  if (!edges.contains(edge)) {
    edges.add(edge);
  }
}

int _mainlineColorIndex(int left, int right) => left < right ? left : right;

int _largestInt(List<int> values) {
  return values.reduce((value, element) => value > element ? value : element);
}

class _CommitGraphPainter extends CustomPainter {
  const _CommitGraphPainter({
    required this.row,
    required this.isLast,
    required this.colorScheme,
  });

  final _CommitGraphRow row;
  final bool isLast;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    final nodeColor = _laneColor(row.nodeColorIndex);
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.round;
    final fillPaint = Paint()
      ..color = nodeColor
      ..style = PaintingStyle.fill;
    final centerY = size.height / 2;
    final bottomY = isLast ? centerY : size.height;

    for (final edge in row.passThroughEdges) {
      _drawEdge(canvas, edge, startY: 0, endY: bottomY, paint: linePaint);
    }

    final nodeX = _laneX(row.nodeLane);
    if (row.hasIncoming) {
      linePaint.color = nodeColor;
      canvas.drawLine(Offset(nodeX, 0), Offset(nodeX, centerY), linePaint);
    }

    for (final edge in row.parentEdges) {
      _drawEdge(canvas, edge, startY: centerY, endY: bottomY, paint: linePaint);
    }

    canvas.drawCircle(Offset(nodeX, centerY), 3.5, fillPaint);
    canvas.drawCircle(
      Offset(nodeX, centerY),
      3.5,
      Paint()
        ..color = colorScheme.surface
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
  }

  void _drawEdge(
    Canvas canvas,
    _CommitGraphEdge edge, {
    required double startY,
    required double endY,
    required Paint paint,
  }) {
    paint.color = _laneColor(edge.colorIndex);
    final startX = _laneX(edge.fromLane);
    final endX = _laneX(edge.toLane);
    if (startX == endX || startY == endY) {
      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), paint);
      return;
    }

    final middleY = startY + (endY - startY) * 0.6;
    final path = Path()
      ..moveTo(startX, startY)
      ..cubicTo(startX, middleY, endX, middleY, endX, endY);
    canvas.drawPath(path, paint);
  }

  Color _laneColor(int colorIndex) {
    if (colorIndex == 0) return _graphLaneColors.first;
    return _graphLaneColors[1 +
        ((colorIndex - 1) % (_graphLaneColors.length - 1))];
  }

  double _laneX(int index) {
    return 8 + index * _graphLaneSpacing;
  }

  @override
  bool shouldRepaint(covariant _CommitGraphPainter oldDelegate) {
    return oldDelegate.row != row ||
        oldDelegate.isLast != isLast ||
        oldDelegate.colorScheme != colorScheme;
  }
}

class _ChangeSectionHeader extends StatelessWidget {
  const _ChangeSectionHeader({required this.title, required this.count});

  final Object title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(4, 8, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: UseText(
              title,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          PillBadge(
            label: '$count',
            icon: Icons.list_alt_outlined,
            containerColor: scheme.surfaceContainerHighest,
            foregroundColor: scheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _StatusTile extends ConsumerWidget {
  const _StatusTile({
    required this.entry,
    required this.diffFile,
    required this.stagedSide,
    required this.isBusy,
    required this.onOpenDiff,
  });

  final GitStatusEntry entry;
  final _DiffFileItem? diffFile;
  final bool stagedSide;
  final bool isBusy;
  final VoidCallback onOpenDiff;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final file = diffFile;
    final changeSummary = switch (file) {
      null => null,
      _ when file.isBinary => 'Binary',
      _ => [
        if (file.additions > 0) '+${file.additions}',
        if (file.deletions > 0) '-${file.deletions}',
      ].join(' '),
    };
    final canDiscard = !stagedSide && entry.isUnstaged && !entry.isConflicted;
    final stageActionKey = stagedSide ? I18nKey.gitUnstage : I18nKey.gitStage;
    final stageActionLabel = translateForWidget(ref, stageActionKey);
    final row = SizedBox(
      height: 28,
      child: InkWell(
        onTap: isBusy ? null : onOpenDiff,
        borderRadius: context.innerCorners,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 6),
          child: Row(
            children: [
              Icon(_statusIcon, size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              if (changeSummary != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: Text(
                    changeSummary,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (canDiscard)
                TooltipAnchor(
                  message: translateForWidget(ref, I18nKey.gitDiscardChanges),
                  child: IconButton(
                    onPressed: isBusy
                        ? null
                        : () => _confirmDiscard(context, ref),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(22, 22),
                      padding: EdgeInsets.zero,
                      iconSize: 15,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.restore_outlined),
                  ),
                ),
              TooltipAnchor(
                message: stageActionLabel,
                child: IconButton(
                  onPressed: isBusy ? null : () => _toggleStage(ref),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(22, 22),
                    padding: EdgeInsets.zero,
                    iconSize: 15,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: Icon(
                    stagedSide
                        ? Icons.remove_done_outlined
                        : Icons.add_task_outlined,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return PyriteContextMenuWidget(
      child: row,
      menuProvider: (request) {
        return Menu(
          children: [
            MenuAction(
              title: translateForWidget(ref, I18nKey.gitViewDiff),
              callback: onOpenDiff,
              attributes: MenuActionAttributes(disabled: isBusy),
            ),
            MenuSeparator(),
            MenuAction(
              title: stageActionLabel,
              callback: () => _toggleStage(ref),
              attributes: MenuActionAttributes(disabled: isBusy),
            ),
            MenuAction(
              title: translateForWidget(ref, I18nKey.gitDiscardChanges),
              callback: () => _confirmDiscard(context, ref),
              attributes: MenuActionAttributes(disabled: isBusy || !canDiscard),
            ),
          ],
        );
      },
    );
  }

  IconData get _statusIcon {
    if (entry.isConflicted) return Icons.warning_amber_outlined;
    if (stagedSide) return Icons.task_alt;
    if (entry.isUntracked) return Icons.note_add_outlined;
    return Icons.edit_outlined;
  }

  void _toggleStage(WidgetRef ref) {
    if (stagedSide) {
      ref.read(gitProvider.notifier).unstage(entry.path);
    } else {
      ref.read(gitProvider.notifier).stage(entry.path);
    }
  }

  Future<void> _confirmDiscard(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const UseText(I18nKey.gitDiscardChanges),
          content: Text(
            translateForWidget(
              ref,
              I18nKey.gitDiscardChangesMessage,
            ).replaceAll('{path}', entry.path),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const UseText(I18nKey.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const UseText(I18nKey.gitDiscard),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await ref.read(gitProvider.notifier).discardChanges(entry);
    }
  }
}

class _DiffFileItem {
  const _DiffFileItem({
    required this.path,
    required this.staged,
    required this.patch,
    required this.additions,
    required this.deletions,
    required this.isBinary,
  });

  final String path;
  final bool staged;
  final String patch;
  final int additions;
  final int deletions;
  final bool isBinary;

  I18nKey get stageLabelKey =>
      staged ? I18nKey.gitStageStaged : I18nKey.gitStageUnstaged;

  String get changeSummary {
    if (isBinary) return 'Binary';
    final parts = <String>[
      if (additions > 0) '+$additions',
      if (deletions > 0) '-$deletions',
    ];
    return parts.isEmpty ? 'No line changes' : parts.join(' ');
  }

  bool get hasContentChange => isBinary || additions > 0 || deletions > 0;
}

class _ChangeListItem {
  const _ChangeListItem({required this.entry, required this.diffFile});

  final GitStatusEntry entry;
  final _DiffFileItem? diffFile;
}

List<_ChangeListItem> _changeItemsForSide(
  List<GitStatusEntry> entries,
  List<_DiffFileItem> diffFiles, {
  required bool staged,
}) {
  final items = <_ChangeListItem>[];
  final seenPaths = <String>{};

  for (final file in diffFiles.where((file) => file.staged == staged)) {
    final entry = _statusEntryForPath(entries, file.path);
    if (entry == null) continue;
    items.add(_ChangeListItem(entry: entry, diffFile: file));
    seenPaths.add(file.path);
  }

  for (final entry in entries) {
    final include = staged
        ? entry.isStaged
        : entry.isUnstaged || entry.isConflicted;
    if (!include || seenPaths.contains(entry.path)) continue;
    items.add(_ChangeListItem(entry: entry, diffFile: null));
  }

  return items;
}

GitStatusEntry? _statusEntryForPath(List<GitStatusEntry> entries, String path) {
  for (final entry in entries) {
    if (entry.path == path) return entry;
  }
  return null;
}

List<_DiffFileItem> _diffFilesFromSnapshot(GitRepositorySnapshot snapshot) {
  if (GitDebugLog.enabled) {
    GitDebugLog.log(
      'GitPage._diffFilesFromSnapshot start stagedPatch=${snapshot.stagedPatch.length} '
      'unstagedPatch=${snapshot.unstagedPatch.length}',
    );
  }
  final files = <_DiffFileItem>[
    ..._diffFilesFromPatch(snapshot.stagedPatch, staged: true),
    ..._diffFilesFromPatch(snapshot.unstagedPatch, staged: false),
  ];
  final seen = <String>{};
  final deduped = <_DiffFileItem>[];
  for (final file in files) {
    final key = '${file.staged}\u0000${file.path}';
    if (seen.add(key)) deduped.add(file);
  }
  if (GitDebugLog.enabled) {
    GitDebugLog.log(
      'GitPage._diffFilesFromSnapshot end files=${files.length} '
      'deduped=${deduped.length}',
    );
  }
  return deduped;
}

List<_DiffFileItem> _diffFilesFromPatch(String patch, {required bool staged}) {
  if (patch.trim().isEmpty) return const [];
  if (GitDebugLog.enabled) {
    GitDebugLog.log(
      'GitPage._diffFilesFromPatch start staged=$staged bytes=${patch.length}',
    );
  }
  final files = <_DiffFileItem>[];
  final lines = patch
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  var section = <String>[];

  void flushSection() {
    final file = _diffFileFromSection(section, staged: staged);
    if (file != null && file.hasContentChange) files.add(file);
    section = <String>[];
  }

  for (final line in lines) {
    if (line.startsWith('diff --git ')) {
      flushSection();
      section = [line];
    } else if (section.isNotEmpty) {
      section.add(line);
    }
  }
  flushSection();

  if (GitDebugLog.enabled) {
    GitDebugLog.log(
      'GitPage._diffFilesFromPatch end staged=$staged files=${files.length}',
    );
  }
  return files;
}

_DiffFileItem? _diffFileFromSection(
  List<String> lines, {
  required bool staged,
}) {
  if (lines.isEmpty) return null;
  final path = _pathFromDiffSection(lines);
  if (path == null || path.isEmpty) return null;

  var additions = 0;
  var deletions = 0;
  var isBinary = false;
  for (final line in lines) {
    if (line.startsWith('Binary files ') || line == 'GIT binary patch') {
      isBinary = true;
    }
    if (line.startsWith('+') && !line.startsWith('+++')) {
      additions += 1;
    } else if (line.startsWith('-') && !line.startsWith('---')) {
      deletions += 1;
    }
  }

  return _DiffFileItem(
    path: path,
    staged: staged,
    patch: lines.join('\n').trimRight(),
    additions: additions,
    deletions: deletions,
    isBinary: isBinary,
  );
}

String? _pathFromDiffSection(List<String> lines) {
  final newPath = _firstDiffPath(lines, '+++ ');
  if (newPath != null) return newPath;
  final oldPath = _firstDiffPath(lines, '--- ');
  if (oldPath != null) return oldPath;

  final header = lines.firstWhere(
    (line) => line.startsWith('diff --git '),
    orElse: () => '',
  );
  if (header.isEmpty) return null;
  final bPathIndex = header.lastIndexOf(' b/');
  if (bPathIndex != -1) {
    return _cleanDiffPath(header.substring(bPathIndex + 1));
  }
  final parts = header.split(' ');
  return parts.isEmpty ? null : _cleanDiffPath(parts.last);
}

String? _firstDiffPath(List<String> lines, String prefix) {
  for (final line in lines) {
    if (line.startsWith(prefix)) {
      final path = _cleanDiffPath(line.substring(prefix.length));
      if (path.isNotEmpty && path != '/dev/null') return path;
    }
  }
  return null;
}

String _cleanDiffPath(String value) {
  var path = value.trim();
  if (path == '/dev/null') return path;
  if (path.length > 1 && path.startsWith('"') && path.endsWith('"')) {
    path = path.substring(1, path.length - 1).replaceAll(r'\"', '"');
  }
  if (path.startsWith('a/') || path.startsWith('b/')) {
    return path.substring(2);
  }
  return path;
}

bool _preferredStagedForStatusEntry(GitStatusEntry entry) {
  final canDiscard = entry.isUnstaged && !entry.isConflicted;
  return entry.isStaged && !canDiscard;
}

_DiffFileItem? _findDiffFileForStatusEntry(
  List<_DiffFileItem> files,
  String path,
  bool preferredStaged,
) {
  for (final file in files) {
    if (file.path == path && file.staged == preferredStaged) return file;
  }
  for (final file in files) {
    if (file.path == path) return file;
  }
  return null;
}

String _gitPageBuildSignature(
  GitViewState state,
  GitRepositorySnapshot? snapshot,
) {
  if (snapshot == null) {
    return 'snapshot=null busy=${state.isBusy} workspace=${state.workspacePath} '
        'error=${state.error != null} message=${state.lastMessage != null}';
  }
  return 'root=${snapshot.rootPath} branch=${snapshot.branchLabel} '
      'busy=${state.isBusy} status=${snapshot.statusEntries.length} '
      'branches=${snapshot.branches.length} commits=${snapshot.commits.length} '
      'selected=${state.selectedPath} stagedPatch=${snapshot.stagedPatch.length} '
      'unstagedPatch=${snapshot.unstagedPatch.length} '
      'error=${state.error != null} message=${state.lastMessage != null}';
}

class _ThreeWayConflictPreview extends StatelessWidget {
  const _ThreeWayConflictPreview({required this.conflict});

  final GitConflictInfo conflict;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: DefaultTabController(
        length: 4,
        child: Column(
          children: [
            const TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: 'Base'),
                Tab(text: 'Ours'),
                Tab(text: 'Theirs'),
                Tab(text: 'Merged'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _CodeBlock(text: conflict.basePreview),
                  _CodeBlock(text: conflict.oursPreview),
                  _CodeBlock(text: conflict.theirsPreview),
                  _CodeBlock(text: conflict.mergedPreview),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Text(
          text.isEmpty ? 'No diff.' : text,
          style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.action});

  final Object title;
  final String? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(4, 12, 4, 6),
      child: Row(
        children: [
          Expanded(
            child: UseText(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (action != null) PillBadge(label: action!),
        ],
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final Object title;
  final Object message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: scheme.secondary),
            const SizedBox(height: 8),
            UseText(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            UseText(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
