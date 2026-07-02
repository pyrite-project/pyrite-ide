import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/local_file_items_provider.dart';
import 'package:pyrite_ide/core/services/git/git_models.dart';
import 'package:pyrite_ide/core/services/git/git_provider.dart';
import 'package:pyrite_ide/core/services/git/git_repository_service.dart';
import 'package:pyrite_ide/shared/md3_widgets.dart';
import 'package:super_context_menu/super_context_menu.dart';

const _fallbackAuthorName = 'Pyrite User';
const _fallbackAuthorEmail = 'pyrite@example.local';

class GitPage extends ConsumerStatefulWidget {
  const GitPage({super.key});

  @override
  ConsumerState<GitPage> createState() => _GitPageState();
}

class _GitPageState extends ConsumerState<GitPage> {
  late final TextEditingController _messageController;
  late final TextEditingController _authorController;
  late final TextEditingController _emailController;
  late final TextEditingController _usernameController;
  late final TextEditingController _tokenController;
  late final TextEditingController _publicKeyController;
  late final TextEditingController _privateKeyController;
  late final TextEditingController _passphraseController;

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController();
    _authorController = TextEditingController(text: _fallbackAuthorName);
    _emailController = TextEditingController(text: _fallbackAuthorEmail);
    _usernameController = TextEditingController();
    _tokenController = TextEditingController();
    _publicKeyController = TextEditingController();
    _privateKeyController = TextEditingController();
    _passphraseController = TextEditingController();

    Future.microtask(() => ref.read(gitProvider.notifier).refresh());
  }

  @override
  void dispose() {
    _messageController.dispose();
    _authorController.dispose();
    _emailController.dispose();
    _usernameController.dispose();
    _tokenController.dispose();
    _publicKeyController.dispose();
    _privateKeyController.dispose();
    _passphraseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(gitProvider.select((value) => value.error), (
      previous,
      next,
    ) {
      if (next != null && next != previous) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    });
    ref.listen<String?>(gitProvider.select((value) => value.lastMessage), (
      previous,
      next,
    ) {
      if (next != null && next != previous) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next)));
      }
    });
    final state = ref.watch(gitProvider);
    final snapshot = state.snapshot;
    if (snapshot == null) {
      final workspacePath = state.workspacePath;
      final hasWorkspace = workspacePath != null && workspacePath.isNotEmpty;
      return WorkspaceEmptyState(
        icon: Icons.account_tree_outlined,
        title: '没有检测到 Git 仓库',
        message: hasWorkspace
            ? '当前文件夹没有 .git。可以初始化仓库后开始管理更改。'
            : '打开一个本地项目后，这里会显示源代码管理工作台。',
        actionLabel: hasWorkspace ? '初始化 Git 仓库' : '打开文件夹',
        onAction: hasWorkspace
            ? () => ref.read(gitProvider.notifier).initRepository()
            : () => ref.read(localFileItemsProvider.notifier).openFolder(),
        secondaryAction: Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () =>
                  ref.read(localFileItemsProvider.notifier).openFolder(),
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('打开文件夹'),
            ),
            OutlinedButton.icon(
              onPressed: state.isBusy
                  ? null
                  : () => ref.read(gitProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh),
              label: const Text('重新检测'),
            ),
          ],
        ),
      );
    }
    _syncCommitIdentity(snapshot);

    return DefaultTabController(
      length: 7,
      child: Column(
        children: [
          _GitHeader(snapshot: snapshot, isBusy: state.isBusy),
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: '更改'),
              Tab(text: '分支'),
              Tab(text: '远端'),
              Tab(text: '冲突'),
              Tab(text: '历史'),
              Tab(text: '高级'),
              Tab(text: '凭据'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _changesTab(context, state, snapshot),
                _branchesTab(state, snapshot),
                _remotesTab(state, snapshot),
                _conflictsTab(state, snapshot),
                _historyTab(state, snapshot),
                _advancedTab(state, snapshot),
                _credentialsTab(state),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _changesTab(
    BuildContext context,
    GitViewState state,
    GitRepositorySnapshot snapshot,
  ) {
    final diffFiles = _diffFilesFromSnapshot(snapshot);
    final stagedItems = _changeItemsForSide(
      snapshot.statusEntries,
      diffFiles,
      staged: true,
    );
    final unstagedItems = _changeItemsForSide(
      snapshot.statusEntries,
      diffFiles,
      staged: false,
    );

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _CommitBox(
          messageController: _messageController,
          authorController: _authorController,
          emailController: _emailController,
          onCommit: () => _commit(),
          onStash: () => _stash(),
          isBusy: state.isBusy,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: state.isBusy || snapshot.unstagedCount == 0
                  ? null
                  : () => ref.read(gitProvider.notifier).stageAll(),
              icon: const Icon(Icons.add_task),
              label: const Text('全部暂存'),
            ),
            OutlinedButton.icon(
              onPressed: state.isBusy || snapshot.stagedCount == 0
                  ? null
                  : () => ref.read(gitProvider.notifier).unstageAll(),
              icon: const Icon(Icons.remove_done_outlined),
              label: const Text('全部取消暂存'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (snapshot.statusEntries.isEmpty)
          const _EmptyPanel(
            icon: Icons.check_circle_outline,
            title: '工作区干净',
            message: '没有暂存或未暂存的更改。',
          )
        else ...[
          if (stagedItems.isNotEmpty) ...[
            _ChangeSectionHeader(title: '已暂存的更改', count: stagedItems.length),
            for (final item in stagedItems)
              _StatusTile(
                entry: item.entry,
                diffFile: item.diffFile,
                stagedSide: true,
                isBusy: state.isBusy,
                onOpenDiff: () => _openChangeItemDiff(item, diffFiles),
              ),
          ],
          if (unstagedItems.isNotEmpty) ...[
            _ChangeSectionHeader(title: '更改', count: unstagedItems.length),
            for (final item in unstagedItems)
              _StatusTile(
                entry: item.entry,
                diffFile: item.diffFile,
                stagedSide: false,
                isBusy: state.isBusy,
                onOpenDiff: () => _openChangeItemDiff(item, diffFiles),
              ),
          ],
        ],
      ],
    );
  }

  Future<void> _openChangeItemDiff(
    _ChangeListItem item,
    List<_DiffFileItem> diffFiles,
  ) async {
    final file = item.diffFile;
    if (file != null) {
      _openDiffFile(file);
      await ref
          .read(gitProvider.notifier)
          .selectPath(file.path, staged: file.staged);
      return;
    }

    await _openStatusEntryDiff(item.entry, diffFiles);
  }

  Future<void> _openStatusEntryDiff(
    GitStatusEntry entry,
    List<_DiffFileItem> diffFiles,
  ) async {
    final preferredStaged = _preferredStagedForStatusEntry(entry);
    final file = _findDiffFileForStatusEntry(
      diffFiles,
      entry.path,
      preferredStaged,
    );
    if (file != null) {
      _openDiffFile(file);
      await ref
          .read(gitProvider.notifier)
          .selectPath(entry.path, staged: file.staged);
      return;
    }

    await ref
        .read(gitProvider.notifier)
        .selectPath(entry.path, staged: preferredStaged);
    final selected = ref.read(gitProvider);
    if (selected.selectedPath == entry.path &&
        selected.selectedPatch.trim().isNotEmpty) {
      ref
          .read(tabbedViewControllerProvider.notifier)
          .openReadOnlyGitDiff(
            filePath: entry.path,
            staged: selected.selectedStaged,
            patch: selected.selectedPatch,
          );
    }
  }

  void _openDiffFile(_DiffFileItem file) {
    ref
        .read(tabbedViewControllerProvider.notifier)
        .openReadOnlyGitDiff(
          filePath: file.path,
          staged: file.staged,
          patch: file.patch,
        );
  }

  Widget _branchesTab(GitViewState state, GitRepositorySnapshot snapshot) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: state.isBusy
                  ? null
                  : () => _textDialog(
                      title: '创建分支',
                      label: '分支名称',
                      onSubmit: ref.read(gitProvider.notifier).createBranch,
                    ),
              icon: const Icon(Icons.call_split),
              label: const Text('创建分支'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final branch in snapshot.branches)
          ListTile(
            leading: Icon(
              branch.isRemote ? Icons.cloud_outlined : Icons.account_tree,
            ),
            title: Text(branch.name, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              [
                branch.targetSha.length > 7
                    ? branch.targetSha.substring(0, 7)
                    : branch.targetSha,
                if (branch.upstream.isNotEmpty) branch.upstream,
              ].join(' · '),
              overflow: TextOverflow.ellipsis,
            ),
            trailing: branch.isCurrent
                ? const PillBadge(label: '当前')
                : TextButton(
                    onPressed: state.isBusy
                        ? null
                        : () => ref
                              .read(gitProvider.notifier)
                              .checkoutBranch(
                                branch.name,
                                remote: branch.isRemote,
                              ),
                    child: const Text('切换'),
                  ),
          ),
      ],
    );
  }

  Widget _remotesTab(GitViewState state, GitRepositorySnapshot snapshot) {
    final addRemoteButton = FilledButton.tonalIcon(
      onPressed: state.isBusy ? null : () => _remoteDialog(),
      icon: const Icon(Icons.add_link_outlined),
      label: const Text('添加远端'),
    );
    if (snapshot.remotes.isEmpty) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: addRemoteButton,
            ),
          ),
          const Expanded(
            child: _EmptyPanel(
              icon: Icons.cloud_off_outlined,
              title: '没有远端',
              message: '当前仓库没有配置 remote。',
            ),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [addRemoteButton]),
        const SizedBox(height: 12),
        for (final remote in snapshot.remotes)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.cloud_queue, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          remote.name,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(remote.url, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: state.isBusy
                            ? null
                            : () => ref
                                  .read(gitProvider.notifier)
                                  .fetch(remote.name),
                        icon: const Icon(Icons.cloud_download_outlined),
                        label: const Text('Fetch'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: state.isBusy
                            ? null
                            : () => ref
                                  .read(gitProvider.notifier)
                                  .pull(remote.name),
                        icon: const Icon(Icons.download_for_offline_outlined),
                        label: const Text('Pull'),
                      ),
                      OutlinedButton.icon(
                        onPressed: state.isBusy
                            ? null
                            : () => ref
                                  .read(gitProvider.notifier)
                                  .push(remote.name),
                        icon: const Icon(Icons.cloud_upload_outlined),
                        label: const Text('Push'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _conflictsTab(GitViewState state, GitRepositorySnapshot snapshot) {
    final conflicts = snapshot.conflicts;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (snapshot.stateLabel.contains('Rebase'))
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: state.isBusy ? null : () => _continueRebase(),
                icon: const Icon(Icons.play_arrow),
                label: const Text('继续 rebase'),
              ),
              OutlinedButton.icon(
                onPressed: state.isBusy
                    ? null
                    : () => ref.read(gitProvider.notifier).abortRebase(),
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('中止 rebase'),
              ),
            ],
          ),
        if (conflicts.isEmpty)
          const _EmptyPanel(
            icon: Icons.merge_type_outlined,
            title: '没有冲突',
            message: 'merge、rebase、cherry-pick 的冲突会显示在这里。',
          )
        else
          for (final conflict in conflicts)
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conflict.path,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: state.isBusy
                              ? null
                              : () => ref
                                    .read(gitProvider.notifier)
                                    .acceptConflictSide(
                                      conflict.path,
                                      GitConflictSide.ours,
                                    ),
                          icon: const Icon(Icons.looks_one_outlined),
                          label: const Text('采用 ours'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: state.isBusy
                              ? null
                              : () => ref
                                    .read(gitProvider.notifier)
                                    .acceptConflictSide(
                                      conflict.path,
                                      GitConflictSide.theirs,
                                    ),
                          icon: const Icon(Icons.looks_two_outlined),
                          label: const Text('采用 theirs'),
                        ),
                        OutlinedButton.icon(
                          onPressed: state.isBusy
                              ? null
                              : () => ref
                                    .read(gitProvider.notifier)
                                    .markResolved(conflict.path),
                          icon: const Icon(Icons.add_task),
                          label: const Text('标记已解决'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _ThreeWayConflictPreview(conflict: conflict),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  Widget _historyTab(GitViewState state, GitRepositorySnapshot snapshot) {
    final graphRows = _buildCommitGraphRows(snapshot.commits);
    final graphWidth = graphRows.fold<double>(
      32,
      (width, row) => row.width > width ? row.width : width,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
      children: [
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: [
            FilledButton.tonalIcon(
              onPressed: state.isBusy
                  ? null
                  : () => _textDialog(
                      title: '创建标签',
                      label: '标签名称',
                      onSubmit: ref.read(gitProvider.notifier).createTag,
                    ),
              icon: const Icon(Icons.sell_outlined),
              label: const Text('Tag HEAD'),
            ),
            OutlinedButton.icon(
              onPressed: state.isBusy
                  ? null
                  : () => _textDialog(
                      title: 'Merge',
                      label: '分支、标签或提交',
                      onSubmit: ref.read(gitProvider.notifier).merge,
                    ),
              icon: const Icon(Icons.merge_type),
              label: const Text('Merge'),
            ),
            OutlinedButton.icon(
              onPressed: state.isBusy ? null : () => _rebaseDialog(),
              icon: const Icon(Icons.linear_scale),
              label: const Text('Rebase'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (var index = 0; index < snapshot.commits.length; index += 1)
          _CommitHistoryTile(
            commit: snapshot.commits[index],
            graphRow: graphRows[index],
            graphWidth: graphWidth,
            isLast: index == snapshot.commits.length - 1,
            dateLabel: _dateLabel(snapshot.commits[index].time),
          ),
      ],
    );
  }

  Widget _advancedTab(GitViewState state, GitRepositorySnapshot snapshot) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _SectionTitle(title: '高级 Git 操作'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: state.isBusy
                  ? null
                  : () => _textDialog(
                      title: 'Cherry-pick',
                      label: '提交 SHA、标签或引用',
                      onSubmit: ref.read(gitProvider.notifier).cherryPick,
                    ),
              icon: const Icon(Icons.control_point_duplicate_outlined),
              label: const Text('Cherry-pick'),
            ),
            OutlinedButton.icon(
              onPressed: state.isBusy
                  ? null
                  : () => ref.read(gitProvider.notifier).writeCommitGraph(),
              icon: const Icon(Icons.hub_outlined),
              label: const Text('写入 commit graph'),
            ),
          ],
        ),
        const SectionDivider(),
        _SectionTitle(
          title: 'Stash',
          action: snapshot.stashes.isEmpty
              ? null
              : '${snapshot.stashes.length}',
        ),
        for (final stash in snapshot.stashes)
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: Text(stash.message, overflow: TextOverflow.ellipsis),
            subtitle: Text(stash.sha.substring(0, 7)),
            trailing: Wrap(
              spacing: 4,
              children: [
                IconButton(
                  tooltip: '应用',
                  onPressed: state.isBusy
                      ? null
                      : () => ref
                            .read(gitProvider.notifier)
                            .applyStash(stash.index),
                  icon: const Icon(Icons.file_download_outlined),
                ),
                IconButton(
                  tooltip: '弹出',
                  onPressed: state.isBusy
                      ? null
                      : () => ref
                            .read(gitProvider.notifier)
                            .applyStash(stash.index, pop: true),
                  icon: const Icon(Icons.unarchive_outlined),
                ),
                IconButton(
                  tooltip: '删除',
                  onPressed: state.isBusy
                      ? null
                      : () => ref
                            .read(gitProvider.notifier)
                            .dropStash(stash.index),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
        const SectionDivider(),
        _SectionTitle(
          title: 'Submodule',
          action: snapshot.submodules.isEmpty
              ? null
              : '${snapshot.submodules.length}',
        ),
        for (final submodule in snapshot.submodules)
          ListTile(
            leading: const Icon(Icons.account_tree_outlined),
            title: Text(submodule.path, overflow: TextOverflow.ellipsis),
            subtitle: Text(submodule.url, overflow: TextOverflow.ellipsis),
            trailing: TextButton(
              onPressed: state.isBusy
                  ? null
                  : () => ref
                        .read(gitProvider.notifier)
                        .updateSubmodule(submodule.name),
              child: const Text('更新'),
            ),
          ),
        const SectionDivider(),
        _SectionTitle(
          title: 'Worktree',
          action: snapshot.worktrees.isEmpty
              ? null
              : '${snapshot.worktrees.length}',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: state.isBusy ? null : () => _worktreeDialog(),
              icon: const Icon(Icons.library_add_outlined),
              label: const Text('创建 worktree'),
            ),
          ],
        ),
        for (final worktree in snapshot.worktrees)
          ListTile(
            leading: const Icon(Icons.folder_copy_outlined),
            title: Text(worktree.name, overflow: TextOverflow.ellipsis),
            subtitle: Text(worktree.path, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              tooltip: '清理',
              onPressed: state.isBusy
                  ? null
                  : () => ref
                        .read(gitProvider.notifier)
                        .pruneWorktree(worktree.name),
              icon: const Icon(Icons.cleaning_services_outlined),
            ),
          ),
        const SectionDivider(),
        _SectionTitle(
          title: 'Tag',
          action: snapshot.tags.isEmpty ? null : '${snapshot.tags.length}',
        ),
        for (final tag in snapshot.tags.take(50))
          ListTile(
            dense: true,
            leading: const Icon(Icons.sell_outlined),
            title: Text(tag.name, overflow: TextOverflow.ellipsis),
            subtitle: Text(tag.targetSha, overflow: TextOverflow.ellipsis),
          ),
      ],
    );
  }

  Widget _credentialsTab(GitViewState state) {
    final draft = state.credentials;
    _syncCredentialControllers(draft);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<GitCredentialMode>(
          segments: const [
            ButtonSegment(
              value: GitCredentialMode.none,
              icon: Icon(Icons.no_encryption_outlined),
              label: Text('无'),
            ),
            ButtonSegment(
              value: GitCredentialMode.httpsToken,
              icon: Icon(Icons.token_outlined),
              label: Text('HTTPS Token'),
            ),
            ButtonSegment(
              value: GitCredentialMode.sshAgent,
              icon: Icon(Icons.key_outlined),
              label: Text('SSH Agent'),
            ),
            ButtonSegment(
              value: GitCredentialMode.sshKey,
              icon: Icon(Icons.vpn_key_outlined),
              label: Text('SSH Key'),
            ),
          ],
          selected: {draft.mode},
          onSelectionChanged: state.isBusy
              ? null
              : (selection) {
                  ref
                      .read(gitProvider.notifier)
                      .updateCredentials(draft.copyWith(mode: selection.first));
                },
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _usernameController,
          decoration: const InputDecoration(
            labelText: '用户名',
            border: OutlineInputBorder(),
          ),
          onChanged: _updateCredentialDraft,
        ),
        if (draft.mode == GitCredentialMode.httpsToken) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _tokenController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Token',
              border: OutlineInputBorder(),
            ),
            onChanged: _updateCredentialDraft,
          ),
        ],
        if (draft.mode == GitCredentialMode.sshKey) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _publicKeyController,
            decoration: const InputDecoration(
              labelText: '公钥路径',
              border: OutlineInputBorder(),
            ),
            onChanged: _updateCredentialDraft,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _privateKeyController,
            decoration: const InputDecoration(
              labelText: '私钥路径',
              border: OutlineInputBorder(),
            ),
            onChanged: _updateCredentialDraft,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passphraseController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Passphrase',
              border: OutlineInputBorder(),
            ),
            onChanged: _updateCredentialDraft,
          ),
        ],
      ],
    );
  }

  GitCommitInput _commitInput({String? message}) {
    return GitCommitInput(
      message: message ?? _messageController.text,
      authorName: _authorController.text,
      authorEmail: _emailController.text,
    );
  }

  Future<void> _commit() async {
    await ref.read(gitProvider.notifier).commit(_commitInput());
    if (mounted && ref.read(gitProvider).error == null) {
      _messageController.clear();
    }
  }

  Future<void> _stash() async {
    await ref.read(gitProvider.notifier).stash(_commitInput(message: 'WIP'));
  }

  Future<void> _continueRebase() async {
    await ref.read(gitProvider.notifier).continueRebase(_commitInput());
  }

  Future<void> _rebaseDialog() async {
    await _textDialog(
      title: 'Rebase',
      label: '目标分支、标签或提交',
      onSubmit: (value) => ref
          .read(gitProvider.notifier)
          .rebase(value, _commitInput(message: 'rebase')),
    );
  }

  Future<void> _worktreeDialog() async {
    final name = TextEditingController();
    final path = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('创建 worktree'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: '名称'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: path,
                decoration: const InputDecoration(labelText: '路径'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                ref
                    .read(gitProvider.notifier)
                    .createWorktree(name.text, path.text);
                Navigator.of(context).pop();
              },
              child: const Text('创建'),
            ),
          ],
        );
      },
    );
    name.dispose();
    path.dispose();
  }

  Future<void> _remoteDialog() async {
    final name = TextEditingController(text: 'origin');
    final url = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('添加远端'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: '远端名称'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: url,
                autofocus: true,
                decoration: const InputDecoration(labelText: '远端 URL'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                ref.read(gitProvider.notifier).addRemote(name.text, url.text);
                Navigator.of(context).pop();
              },
              child: const Text('添加'),
            ),
          ],
        );
      },
    );
    name.dispose();
    url.dispose();
  }

  Future<void> _textDialog({
    required String title,
    required String label,
    required Future<void> Function(String value) onSubmit,
  }) async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(labelText: label),
            onSubmitted: (value) {
              onSubmit(value);
              Navigator.of(context).pop();
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                onSubmit(controller.text);
                Navigator.of(context).pop();
              },
              child: const Text('确认'),
            ),
          ],
        );
      },
    );
    controller.dispose();
  }

  void _syncCredentialControllers(GitCredentialDraft draft) {
    _syncController(_usernameController, draft.username);
    _syncController(_tokenController, draft.token);
    _syncController(_publicKeyController, draft.publicKeyPath);
    _syncController(_privateKeyController, draft.privateKeyPath);
    _syncController(_passphraseController, draft.passphrase);
  }

  void _syncCommitIdentity(GitRepositorySnapshot snapshot) {
    if (_authorController.text.isEmpty ||
        _authorController.text == _fallbackAuthorName) {
      _syncController(_authorController, snapshot.authorName);
    }
    if (_emailController.text.isEmpty ||
        _emailController.text == _fallbackAuthorEmail) {
      _syncController(_emailController, snapshot.authorEmail);
    }
  }

  void _syncController(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.text = value;
  }

  void _updateCredentialDraft(String _) {
    final current = ref.read(gitProvider).credentials;
    ref
        .read(gitProvider.notifier)
        .updateCredentials(
          current.copyWith(
            username: _usernameController.text,
            token: _tokenController.text,
            publicKeyPath: _publicKeyController.text,
            privateKeyPath: _privateKeyController.text,
            passphrase: _passphraseController.text,
          ),
        );
  }

  String _dateLabel(DateTime value) {
    return '${value.year}-${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }
}

class _GitHeader extends ConsumerWidget {
  const _GitHeader({required this.snapshot, required this.isBusy});

  final GitRepositorySnapshot snapshot;
  final bool isBusy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PaneHeader(
      title: '源代码管理',
      subtitle:
          '${snapshot.branchLabel} · ${snapshot.stateLabel} · ${snapshot.rootPath}',
      leadingIcon: Icons.account_tree_outlined,
      actions: [
        if (snapshot.ahead > 0 || snapshot.behind > 0)
          PillBadge(label: '↑${snapshot.ahead} ↓${snapshot.behind}'),
        IconButton(
          tooltip: '刷新',
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
      ],
    );
  }
}

class _CommitBox extends StatelessWidget {
  const _CommitBox({
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
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: messageController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '提交信息',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: authorController,
                    decoration: const InputDecoration(labelText: '作者'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: emailController,
                    decoration: const InputDecoration(labelText: '邮箱'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: isBusy ? null : onCommit,
                    icon: const Icon(Icons.check),
                    label: const Text('提交'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'Stash',
                  onPressed: isBusy ? null : onStash,
                  icon: const Icon(Icons.inventory_2_outlined),
                ),
              ],
            ),
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
                    style: textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.06,
                    ),
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

const double _commitHistoryRowHeight = 36;

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
        var parentLaneIndex = lanesAfter.indexWhere(
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
            lanesAfter.removeAt(laneIndex);
            targetLaneIndex = parentLaneIndex > laneIndex
                ? parentLaneIndex - 1
                : parentLaneIndex;
            lanesAfter[targetLaneIndex] = _CommitGraphLane(
              sha: parentSha,
              colorIndex: nodeLane.colorIndex,
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

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(4, 12, 4, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
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
    final brightness = Theme.of(context).brightness;
    final addColor = brightness == Brightness.dark
        ? Colors.greenAccent.shade200
        : Colors.green.shade700;
    final removeColor = scheme.error;
    final canDiscard = !stagedSide && entry.isUnstaged && !entry.isConflicted;
    final stageActionLabel = stagedSide ? '取消暂存' : '暂存';
    final tile = ListTile(
      dense: true,
      leading: Icon(_statusIcon),
      title: Text(entry.path, overflow: TextOverflow.ellipsis),
      subtitle: _StatusTileSubtitle(entry: entry, diffFile: diffFile),
      onTap: isBusy ? null : onOpenDiff,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (diffFile != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: _ChangeSummary(
                file: diffFile!,
                addColor: addColor,
                removeColor: removeColor,
              ),
            ),
          if (canDiscard)
            IconButton(
              tooltip: '放弃更改',
              onPressed: isBusy ? null : () => _confirmDiscard(context, ref),
              icon: const Icon(Icons.restore_outlined),
            ),
          IconButton(
            tooltip: stageActionLabel,
            onPressed: isBusy ? null : () => _toggleStage(ref),
            icon: Icon(
              stagedSide ? Icons.remove_done_outlined : Icons.add_task_outlined,
            ),
          ),
        ],
      ),
    );

    return ContextMenuWidget(
      child: tile,
      menuProvider: (request) {
        return Menu(
          children: [
            MenuAction(
              title: '查看 Diff',
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
              title: '放弃更改',
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
          title: const Text('放弃更改'),
          content: Text('将丢弃 ${entry.path} 的工作区更改。此操作不可撤销。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('放弃'),
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

class _StatusTileSubtitle extends StatelessWidget {
  const _StatusTileSubtitle({required this.entry, required this.diffFile});

  final GitStatusEntry entry;
  final _DiffFileItem? diffFile;

  @override
  Widget build(BuildContext context) {
    final file = diffFile;
    if (file == null) {
      return Text(entry.summary, overflow: TextOverflow.ellipsis);
    }

    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _DiffInfoPill(
          label: file.stageLabel,
          color: file.staged ? scheme.primary : scheme.tertiary,
        ),
        if (entry.summary.isNotEmpty)
          Text(
            entry.summary,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        if (file.isBinary)
          _DiffInfoPill(label: 'Binary', color: scheme.onSurfaceVariant),
      ],
    );
  }
}

class _ChangeSummary extends StatelessWidget {
  const _ChangeSummary({
    required this.file,
    required this.addColor,
    required this.removeColor,
  });

  final _DiffFileItem file;
  final Color addColor;
  final Color removeColor;

  @override
  Widget build(BuildContext context) {
    if (file.isBinary) {
      return Text(
        'Binary',
        textAlign: TextAlign.end,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return SizedBox(
      width: 48,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '+${file.additions}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: addColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            '-${file.deletions}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: removeColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DiffInfoPill extends StatelessWidget {
  const _DiffInfoPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(6, 2, 6, 3),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
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

  String get stageLabel => staged ? '已暂存' : '未暂存';

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
  return deduped;
}

List<_DiffFileItem> _diffFilesFromPatch(String patch, {required bool staged}) {
  if (patch.trim().isEmpty) return const [];
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

class _ThreeWayConflictPreview extends StatelessWidget {
  const _ThreeWayConflictPreview({required this.conflict});

  final GitConflictInfo conflict;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 320,
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

  final String title;
  final String? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(4, 16, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
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
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: scheme.secondary),
            const SizedBox(height: 10),
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
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
