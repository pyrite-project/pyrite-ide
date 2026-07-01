import 'package:code_forge/code_forge/code_area.dart';
import 'package:code_forge/code_forge/controller.dart';
import 'package:code_forge/code_forge/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/constants/editor_themes.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/file/local_file_items_provider.dart';
import 'package:pyrite_ide/core/services/git/git_models.dart';
import 'package:pyrite_ide/core/services/git/git_provider.dart';
import 'package:pyrite_ide/core/services/git/git_repository_service.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/shared/md3_widgets.dart';
import 'package:re_highlight/languages/diff.dart';
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
    return _ResponsiveGitPane(
      left: ListView(
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
          else
            for (final entry in snapshot.statusEntries)
              _StatusTile(entry: entry, isBusy: state.isBusy),
        ],
      ),
      right: _PreviewPanel(state: state, snapshot: snapshot),
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
    return _ResponsiveGitPane(
      left: ListView(
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
          const SizedBox(height: 12),
          for (var index = 0; index < snapshot.commits.length; index += 1)
            _CommitHistoryTile(
              commit: snapshot.commits[index],
              graphRow: graphRows[index],
              isLast: index == snapshot.commits.length - 1,
              dateLabel: _dateLabel(snapshot.commits[index].time),
            ),
        ],
      ),
      right: _PreviewPanel(state: state, snapshot: snapshot),
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
    required this.isLast,
    required this.dateLabel,
  });

  final GitCommitInfo commit;
  final _CommitGraphRow graphRow;
  final bool isLast;
  final String dateLabel;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: SizedBox(
        width: graphRow.width,
        height: double.infinity,
        child: CustomPaint(
          painter: _CommitGraphPainter(
            row: graphRow,
            isLast: isLast,
            colorScheme: Theme.of(context).colorScheme,
          ),
        ),
      ),
      title: Text(commit.summary, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${commit.shortSha} · ${commit.author} · $dateLabel',
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _CommitGraphRow {
  const _CommitGraphRow({
    required this.laneIndex,
    required this.laneCount,
    required this.parentCount,
  });

  final int laneIndex;
  final int laneCount;
  final int parentCount;

  double get width {
    return (laneCount * _graphLaneSpacing + 20).clamp(40, 112).toDouble();
  }
}

const double _graphLaneSpacing = 14;
const _graphLaneColors = [
  Color(0xFF3B82F6),
  Color(0xFF22C55E),
  Color(0xFFF97316),
  Color(0xFFE11D48),
  Color(0xFF8B5CF6),
  Color(0xFF14B8A6),
];

List<_CommitGraphRow> _buildCommitGraphRows(List<GitCommitInfo> commits) {
  final lanes = <String>[];
  final rows = <_CommitGraphRow>[];

  for (final commit in commits) {
    var laneIndex = lanes.indexOf(commit.sha);
    if (laneIndex == -1) {
      lanes.add(commit.sha);
      laneIndex = lanes.length - 1;
    }

    final laneCountBefore = lanes.length;
    if (commit.parentShas.isEmpty) {
      lanes.removeAt(laneIndex);
    } else {
      lanes[laneIndex] = commit.parentShas.first;
      for (final parentSha in commit.parentShas.skip(1)) {
        if (!lanes.contains(parentSha)) {
          lanes.insert(laneIndex + 1, parentSha);
        }
      }
    }

    rows.add(
      _CommitGraphRow(
        laneIndex: laneIndex,
        laneCount: _largestInt([laneCountBefore, lanes.length, laneIndex + 1]),
        parentCount: commit.parentShas.length,
      ),
    );
  }

  return rows;
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
    final mutedPaint = Paint()
      ..color = colorScheme.outlineVariant
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    final laneColor = _graphLaneColors[row.laneIndex % _graphLaneColors.length];
    final activePaint = Paint()
      ..color = laneColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final fillPaint = Paint()
      ..color = laneColor
      ..style = PaintingStyle.fill;
    final centerY = size.height / 2;

    for (var lane = 0; lane < row.laneCount; lane += 1) {
      final x = _laneX(lane);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), mutedPaint);
    }

    final nodeX = _laneX(row.laneIndex);
    canvas.drawLine(Offset(nodeX, 0), Offset(nodeX, centerY), activePaint);
    if (!isLast) {
      canvas.drawLine(
        Offset(nodeX, centerY),
        Offset(nodeX, size.height),
        activePaint,
      );
    }

    for (var index = 1; index < row.parentCount; index += 1) {
      final targetX = _laneX(row.laneIndex + index);
      canvas.drawLine(
        Offset(nodeX, centerY),
        Offset(targetX, size.height),
        activePaint,
      );
    }

    canvas.drawCircle(Offset(nodeX, centerY), 4.5, fillPaint);
    canvas.drawCircle(
      Offset(nodeX, centerY),
      4.5,
      Paint()
        ..color = colorScheme.surface
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  double _laneX(int index) {
    return 10 + index * _graphLaneSpacing;
  }

  @override
  bool shouldRepaint(covariant _CommitGraphPainter oldDelegate) {
    return oldDelegate.row != row ||
        oldDelegate.isLast != isLast ||
        oldDelegate.colorScheme != colorScheme;
  }
}

class _StatusTile extends ConsumerWidget {
  const _StatusTile({required this.entry, required this.isBusy});

  final GitStatusEntry entry;
  final bool isBusy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canDiscard = entry.isUnstaged && !entry.isConflicted;
    final notifier = ref.read(gitProvider.notifier);
    final tile = ListTile(
      dense: true,
      leading: Icon(_statusIcon),
      title: Text(entry.path, overflow: TextOverflow.ellipsis),
      subtitle: Text(entry.summary, overflow: TextOverflow.ellipsis),
      onTap: () => notifier.selectPath(
        entry.path,
        staged: entry.isStaged && !canDiscard,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canDiscard)
            IconButton(
              tooltip: '放弃更改',
              onPressed: isBusy ? null : () => _confirmDiscard(context, ref),
              icon: const Icon(Icons.restore_outlined),
            ),
          IconButton(
            tooltip: entry.isStaged && !canDiscard ? '取消暂存' : '暂存',
            onPressed: isBusy ? null : () => _toggleStage(ref),
            icon: Icon(
              entry.isStaged && !canDiscard
                  ? Icons.remove_done_outlined
                  : Icons.add_task_outlined,
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
              callback: () => notifier.selectPath(
                entry.path,
                staged: entry.isStaged && !canDiscard,
              ),
              attributes: MenuActionAttributes(disabled: isBusy),
            ),
            MenuAction(
              title: 'Blame',
              callback: () => _blame(ref),
              attributes: MenuActionAttributes(disabled: isBusy),
            ),
            MenuSeparator(),
            MenuAction(
              title: entry.isStaged && !canDiscard ? '取消暂存' : '暂存',
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
    if (entry.isStaged) return Icons.task_alt;
    if (entry.isUntracked) return Icons.note_add_outlined;
    return Icons.edit_outlined;
  }

  Future<void> _blame(WidgetRef ref) async {
    await ref.read(gitProvider.notifier).selectPath(entry.path);
    await ref.read(gitProvider.notifier).blameSelected();
  }

  void _toggleStage(WidgetRef ref) {
    if (entry.isStaged && !entry.isUnstaged) {
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

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({required this.state, required this.snapshot});

  final GitViewState state;
  final GitRepositorySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final selectedPath = state.selectedPath;
    return Column(
      children: [
        PaneHeader(
          title: selectedPath ?? 'Diff',
          subtitle: selectedPath == null ? snapshot.rootPath : '文件预览',
          leadingIcon: Icons.difference_outlined,
          compact: true,
        ),
        Expanded(
          child: state.blame.isNotEmpty
              ? _BlameView(lines: state.blame)
              : _DiffEditor(
                  text: selectedPath == null
                      ? _combinedPatch(snapshot)
                      : state.selectedPatch,
                ),
        ),
      ],
    );
  }

  String _combinedPatch(GitRepositorySnapshot snapshot) {
    final parts = [
      if (snapshot.stagedPatch.isNotEmpty) snapshot.stagedPatch,
      if (snapshot.unstagedPatch.isNotEmpty) snapshot.unstagedPatch,
    ];
    return parts.isEmpty ? 'No diff.' : parts.join('\n');
  }
}

class _DiffEditor extends ConsumerStatefulWidget {
  const _DiffEditor({required this.text});

  final String text;

  @override
  ConsumerState<_DiffEditor> createState() => _DiffEditorState();
}

class _DiffEditorState extends ConsumerState<_DiffEditor> {
  late final CodeForgeController _controller;

  @override
  void initState() {
    super.initState();
    _controller = CodeForgeController()
      ..text = _displayText(widget.text)
      ..readOnly = true;
  }

  @override
  void didUpdateWidget(covariant _DiffEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextText = _displayText(widget.text);
    if (_controller.text != nextText) {
      _controller.text = nextText;
    }
    _controller.readOnly = true;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeKey = ref.watch(editorThemeKey);
    final entry = findEditorThemeByKey(themeKey) ?? editorThemes.first;
    final brightness = Theme.of(context).brightness;
    final surface = Theme.of(context).scaffoldBackgroundColor;
    final resolvedTheme = applySurfaceBackground(
      resolveEditorTheme(entry, brightness),
      surface,
    );

    return CodeForge(
      key: ValueKey('git_diff_${themeKey}_${brightness.name}'),
      controller: _controller,
      filePath: 'git.diff',
      readOnly: true,
      editorTheme: resolvedTheme,
      language: langDiff,
      textStyle: TextStyle(
        fontSize: ref.watch(editorFontSize),
        fontFamily: editorTextFonts[ref.watch(editorTextFontProvider)],
      ),
      lineWrap: ref.watch(editorWordWrap),
      useSpaceAsTab: true,
      tabSize: 4,
      gutterBuilder: GutterBuilder(
        builder: (lineNumber, lineText) => '$lineNumber',
        includeReplacedIndex: false,
      ),
    );
  }

  String _displayText(String text) {
    return text.isEmpty ? 'No diff.' : text;
  }
}

class _BlameView extends StatelessWidget {
  const _BlameView({required this.lines});

  final List<GitBlameLine> lines;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: lines.length,
      itemBuilder: (context, index) {
        final line = lines[index];
        return ListTile(
          dense: true,
          leading: Text('${line.lineStart}'),
          title: Text(
            '${line.commitSha.substring(0, 7)} · ${line.author}',
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text('${line.lineCount} 行 · ${line.email}'),
        );
      },
    );
  }
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

class _ResponsiveGitPane extends StatelessWidget {
  const _ResponsiveGitPane({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            children: [
              Expanded(flex: 3, child: left),
              const Divider(height: 1),
              Expanded(flex: 2, child: right),
            ],
          );
        }
        return Row(
          children: [
            SizedBox(width: 360, child: left),
            const VerticalDivider(width: 1),
            Expanded(child: right),
          ],
        );
      },
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
