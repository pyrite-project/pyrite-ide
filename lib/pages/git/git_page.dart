import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/constants/corner_radius.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/local_tree.dart';
import 'package:pyrite_ide/core/services/git/git_blame_gutter.dart';
import 'package:pyrite_ide/core/services/git/git_debug_log.dart';
import 'package:pyrite_ide/core/services/git/git_models.dart';
import 'package:pyrite_ide/core/services/git/git_provider.dart';
import 'package:pyrite_ide/core/services/git/git_repository_service.dart';
import 'package:pyrite_ide/core/services/message/ide_message.dart';
import 'package:pyrite_ide/shared/dialog_form_fields.dart';
import 'package:pyrite_ide/shared/md3_widgets.dart';
import 'package:pyrite_ide/shared/pyrite_context_menu.dart';
import 'package:pyrite_ide/shared/studio_text.dart';
import 'package:super_context_menu/super_context_menu.dart';

part 'git_page_widgets.dart';

const _fallbackAuthorName = 'Pyrite User';
const _fallbackAuthorEmail = 'pyrite@example.local';

enum _CheckoutBlockedAction { stash, merge, force }

enum _ForceCheckoutAction { all, listedTracked }

/// 删除本地分支时用户的选择：是否强制、是否连同名远端一起删。
class _BranchDeleteChoice {
  const _BranchDeleteChoice({required this.force, required this.includeRemote});

  final bool force;
  final bool includeRemote;
}

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
  String? _lastLoggedBuildSignature;

  @override
  void initState() {
    super.initState();
    GitDebugLog.log('GitPage.initState');
    _messageController = TextEditingController();
    _authorController = TextEditingController(text: _fallbackAuthorName);
    _emailController = TextEditingController(text: _fallbackAuthorEmail);
    _usernameController = TextEditingController();
    _tokenController = TextEditingController();
    _publicKeyController = TextEditingController();
    _privateKeyController = TextEditingController();
    _passphraseController = TextEditingController();
  }

  @override
  void dispose() {
    GitDebugLog.log('GitPage.dispose');
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
        showIdeError(context, next);
      }
    });
    ref.listen<String?>(gitProvider.select((value) => value.lastMessage), (
      previous,
      next,
    ) {
      if (next != null && next != previous) {
        showIdeSuccess(context, next);
      }
    });
    final state = ref.watch(gitProvider);
    final snapshot = state.snapshot;
    if (GitDebugLog.enabled) {
      final buildSignature = _gitPageBuildSignature(state, snapshot);
      if (buildSignature != _lastLoggedBuildSignature) {
        _lastLoggedBuildSignature = buildSignature;
        GitDebugLog.log('GitPage.build $buildSignature');
      }
    }
    if (snapshot == null) {
      if (state.isBusy) {
        return const Center(child: CircularProgressIndicator());
      }
      final workspacePath = state.workspacePath;
      final hasWorkspace = workspacePath != null && workspacePath.isNotEmpty;
      return WorkspaceEmptyState(
        icon: Icons.account_tree_outlined,
        title: I18nKey.gitEmptyTitle,
        message: hasWorkspace
            ? I18nKey.gitEmptyNoGitMessage
            : I18nKey.gitEmptyNoWorkspaceMessage,
        actionLabel: hasWorkspace
            ? I18nKey.gitInitRepository
            : I18nKey.gitOpenFolder,
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
              label: const UseText(I18nKey.gitOpenFolder),
            ),
            OutlinedButton.icon(
              onPressed: state.isBusy
                  ? null
                  : () => ref.read(gitProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh),
              label: const UseText(I18nKey.gitRedetect),
            ),
          ],
        ),
      );
    }
    GitDebugLog.log('GitPage.syncCommitIdentity start');
    _syncCommitIdentity(snapshot);
    GitDebugLog.log('GitPage.syncCommitIdentity end');

    return Theme(
      data: _compactChromeTheme(context),
      child: Scaffold(
        body: DefaultTabController(
          length: 5,
          child: Column(
            children: [
              _GitHeader(snapshot: snapshot, isBusy: state.isBusy),
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                dividerHeight: 0,
                // Same compact strip as the plugin view tabs: 38px tabs with
                // labelMedium text, not Material's 46px titleSmall default.
                labelStyle: Theme.of(context).textTheme.labelMedium,
                // labelPadding: EdgeInsets.symmetric(horizontal: 10),
                tabs: const [
                  Tab(height: 38, child: UseText(I18nKey.gitTabChanges)),
                  Tab(height: 38, child: UseText(I18nKey.gitTabBranches)),
                  Tab(height: 38, child: UseText(I18nKey.gitTabRemotes)),
                  Tab(height: 38, child: UseText(I18nKey.gitTabHistory)),
                  Tab(height: 38, child: UseText(I18nKey.gitTabAdvanced)),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _changesTab(context, state, snapshot),
                    Builder(builder: (_) => _branchesTab(state, snapshot)),
                    Builder(builder: (_) => _remotesTab(state, snapshot)),
                    Builder(builder: (_) => _historyTab(state, snapshot)),
                    Builder(builder: (_) => _advancedTab(state, snapshot)),
                  ],
                ),
              ),
            ],
          ),
        ),
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
    final conflicts = snapshot.conflicts;
    final empty = snapshot.statusEntries.isEmpty && conflicts.isEmpty;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
            children: [
              if (snapshot.stateLabel.contains('Rebase'))
                _RebaseActions(
                  isBusy: state.isBusy,
                  onContinue: _continueRebase,
                  onAbort: () => ref.read(gitProvider.notifier).abortRebase(),
                ),
              if (empty)
                const _EmptyPanel(
                  icon: Icons.check_circle_outline,
                  title: I18nKey.gitCleanTitle,
                  message: I18nKey.gitCleanMessage,
                )
              else ...[
                if (stagedItems.isNotEmpty) ...[
                  _ChangeSectionHeader(
                    title: I18nKey.gitStagedChanges,
                    count: stagedItems.length,
                  ),
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
                  _ChangeSectionHeader(
                    title: I18nKey.gitChanges,
                    count: unstagedItems.length,
                  ),
                  for (final item in unstagedItems)
                    _StatusTile(
                      entry: item.entry,
                      diffFile: item.diffFile,
                      stagedSide: false,
                      isBusy: state.isBusy,
                      onOpenDiff: () => _openChangeItemDiff(item, diffFiles),
                    ),
                ],
                if (conflicts.isNotEmpty) ...[
                  _ChangeSectionHeader(
                    title: I18nKey.gitTabConflicts,
                    count: conflicts.length,
                  ),
                  for (final conflict in conflicts)
                    _ThreeWayConflictCard(
                      title: conflict.path,
                      isBusy: state.isBusy,
                      onAcceptOurs: () => ref
                          .read(gitProvider.notifier)
                          .acceptConflictSide(
                            conflict.path,
                            GitConflictSide.ours,
                          ),
                      onAcceptTheirs: () => ref
                          .read(gitProvider.notifier)
                          .acceptConflictSide(
                            conflict.path,
                            GitConflictSide.theirs,
                          ),
                      onMarkResolved: state.isBusy
                          ? null
                          : () => ref
                                .read(gitProvider.notifier)
                                .markResolved(conflict.path),
                      child: _ThreeWayConflictPreview(conflict: conflict),
                    ),
                ],
              ],
            ],
          ),
        ),
        // blame 折叠条：只有选中文件时才出现，默认折叠、零额外请求。
        if (state.selectedPath != null)
          GitBlameGutter(filePath: state.selectedPath!),
        _CommitBar(
          messageController: _messageController,
          authorController: _authorController,
          emailController: _emailController,
          onCommit: _commit,
          onStash: _stash,
          isBusy: state.isBusy,
        ),
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
    final localBranches = snapshot.branches
        .where((branch) => !branch.isRemote)
        .toList();
    final remoteBranches = snapshot.branches
        .where((branch) => branch.isRemote)
        .toList();
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
                      title: I18nKey.gitCreateBranch,
                      label: I18nKey.gitBranchName,
                      onSubmit: ref.read(gitProvider.notifier).createBranch,
                    ),
              icon: const Icon(Icons.call_split),
              label: const UseText(I18nKey.gitCreateBranch),
            ),
          ],
        ),
        if (localBranches.isNotEmpty) ...[
          const SizedBox(height: 10),
          const _SectionTitle(title: I18nKey.gitTabBranches),
        ],
        for (final branch in localBranches)
          _BranchTile(
            branch: branch,
            isBusy: state.isBusy,
            onCheckout: () => _checkoutBranch(branch),
            onRename: () => _renameBranchDialog(branch),
            onDelete: () => _deleteBranchDialog(branch),
          ),
        if (remoteBranches.isNotEmpty) ...[
          const SectionDivider(),
          const _SectionTitle(title: I18nKey.gitTabRemotes),
        ],
        for (final branch in remoteBranches)
          _BranchTile(
            branch: branch,
            isBusy: state.isBusy,
            onCheckout: () => _checkoutBranch(branch),
            onDelete: () => _deleteBranchDialog(branch),
          ),
      ],
    );
  }

  /// 重命名分支：预填当前名称并全选，当前分支也能重命名（HEAD 会被 libgit2
  /// 一起迁移到新名字）。
  Future<void> _renameBranchDialog(GitBranchInfo branch) async {
    await _textDialog(
      title: translateForWidget(ref, I18nKey.gitDialogRenameBranch),
      label: I18nKey.gitBranchName,
      initialValue: branch.name,
      selectAll: true,
      onSubmit: (value) =>
          ref.read(gitProvider.notifier).renameBranch(branch, value),
    );
  }

  /// 删除分支：本地分支在同一个对话框里一次问清“是否强制”“是否连远端”。
  ///
  /// 取舍：不在删除失败后再弹“要不要强制”——失败信息要经 state 绕一圈，
  /// 很容易读到上一次操作的陈旧 error。把选项前置到确认对话框，逻辑线性，
  /// 也符合“操作前必须二次确认”的要求。
  Future<void> _deleteBranchDialog(GitBranchInfo branch) async {
    final notifier = ref.read(gitProvider.notifier);
    if (branch.isRemote) {
      final confirmed = await _confirmDeletion(
        title: translateForWidget(ref, I18nKey.gitDialogDeleteRemoteBranch),
        message: translateForWidgetWithReplacements(
          ref,
          I18nKey.gitDialogDeleteRemoteBranchBody,
          {'branch': branch.name},
        ),
        confirmKey: I18nKey.gitDelete,
      );
      if (!mounted || !confirmed) return;
      await notifier.deleteBranch(branch);
      return;
    }

    final target = await notifier.inspectBranchDeletionTarget(branch.name);
    if (!mounted) return;
    if (target != null && target.isCurrent) {
      showIdeError(
        context,
        translateForWidgetWithReplacements(
          ref,
          I18nKey.gitErrorBranchIsCurrent,
          {'name': branch.name},
        ),
      );
      return;
    }
    final hasRemote = target?.hasRemote ?? false;
    final choice = await _branchDeleteDialog(
      branch: branch,
      hasRemote: hasRemote,
      remoteBranchName: target?.remoteBranchName ?? '',
    );
    if (!mounted || choice == null) return;
    await notifier.deleteBranch(
      branch,
      includeRemote: choice.includeRemote,
      force: choice.force,
    );
  }

  Future<_BranchDeleteChoice?> _branchDeleteDialog({
    required GitBranchInfo branch,
    required bool hasRemote,
    required String remoteBranchName,
  }) {
    return showDialog<_BranchDeleteChoice>(
      context: context,
      builder: (context) {
        var force = false;
        var includeRemote = false;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            icon: const Icon(Icons.warning_amber_outlined),
            title: Text(
              translateForWidgetWithReplacements(
                ref,
                I18nKey.gitDialogDeleteLocalBranch,
                {'branch': branch.name},
              ),
            ),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    translateForWidget(
                      ref,
                      I18nKey.gitDialogDeleteLocalBranchBody,
                    ),
                  ),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: force,
                    onChanged: (value) =>
                        setDialogState(() => force = value ?? false),
                    title: Text(
                      translateForWidget(
                        ref,
                        I18nKey.gitDialogDeleteLocalBranchForce,
                      ),
                    ),
                  ),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: includeRemote,
                    onChanged: hasRemote
                        ? (value) => setDialogState(
                            () => includeRemote = value ?? false,
                          )
                        : null,
                    title: Text(
                      hasRemote
                          ? translateForWidgetWithReplacements(
                              ref,
                              I18nKey.gitDialogDeleteAlsoRemote,
                              {'branch': remoteBranchName},
                            )
                          : translateForWidget(
                              ref,
                              I18nKey.gitDialogDeleteNoRemote,
                            ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const UseText(I18nKey.commonCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(
                  _BranchDeleteChoice(
                    force: force,
                    includeRemote: hasRemote && includeRemote,
                  ),
                ),
                child: const UseText(I18nKey.gitDelete),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<bool> _confirmDeletion({
    required String title,
    required String message,
    required I18nKey confirmKey,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_outlined),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const UseText(I18nKey.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: UseText(confirmKey),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Widget _remotesTab(GitViewState state, GitRepositorySnapshot snapshot) {
    final addRemoteButton = FilledButton.tonalIcon(
      onPressed: state.isBusy ? null : _remoteDialog,
      icon: const Icon(Icons.add_link_outlined),
      label: const UseText(I18nKey.gitAddRemote),
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
              title: I18nKey.gitNoRemotesTitle,
              message: I18nKey.gitNoRemotesMessage,
            ),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      children: [
        addRemoteButton,
        const SizedBox(height: 6),
        for (final remote in snapshot.remotes)
          _RemoteTile(
            remote: remote,
            isBusy: state.isBusy,
            onFetch: () => ref.read(gitProvider.notifier).fetch(remote.name),
            onPull: () => ref.read(gitProvider.notifier).pull(remote.name),
            onPush: () => ref.read(gitProvider.notifier).push(remote.name),
            onEditUrl: () => _editRemoteUrlDialog(remote),
            onRename: () => _renameRemoteDialog(remote),
            onDelete: () => _deleteRemoteDialog(remote),
          ),
      ],
    );
  }

  /// 创建 tag：message 留空 => 保持原有 lightweight 路径；填写则创建 annotated。
  Future<void> _createTagDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return DialogFormFields(
          initialValues: const ['', ''],
          builder: (context, c) => AlertDialog(
            title: const UseText(I18nKey.gitCreateTag),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: c[0],
                  autofocus: true,
                  decoration: const InputDecoration(
                    label: UseText(I18nKey.gitTagName),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: c[1],
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(
                    label: Text(
                      translateForWidget(ref, I18nKey.gitDialogTagMessage),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const UseText(I18nKey.commonCancel),
              ),
              FilledButton(
                onPressed: () {
                  ref
                      .read(gitProvider.notifier)
                      .createTag(c[0].text, message: c[1].text);
                  Navigator.of(context).pop();
                },
                child: const UseText(I18nKey.gitCreateTag),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 删除 tag：先确认本地删除，若存在同名远端 tag 再单独确认删除远端。
  Future<void> _deleteTagDialog(
    GitTagInfo tag,
    GitRepositorySnapshot snapshot,
  ) async {
    final confirmed = await _confirmDeletion(
      title: translateForWidget(ref, I18nKey.gitDialogDeleteTag),
      message: translateForWidgetWithReplacements(
        ref,
        I18nKey.gitDialogDeleteTagBody,
        {'name': tag.name},
      ),
      confirmKey: I18nKey.gitDelete,
    );
    if (!confirmed) return;

    final remoteConfirmed = snapshot.remotes.isNotEmpty
        ? await _confirmDeletion(
            title: translateForWidget(ref, I18nKey.gitDialogDeleteTagRemote),
            message: translateForWidgetWithReplacements(
              ref,
              I18nKey.gitDialogDeleteTagRemoteBody,
              {
                'remotes': snapshot.remotes.map((r) => r.name).join(' / '),
                'name': tag.name,
              },
            ),
            confirmKey: I18nKey.gitDelete,
          )
        : false;
    if (!mounted) return;
    final remoteName = remoteConfirmed ? snapshot.remotes.first.name : null;
    await ref
        .read(gitProvider.notifier)
        .deleteTag(tag.name, remoteName: remoteName);
  }

  /// 编辑远端 URL。保存前二次确认：URL 会影响后续 fetch/push 的目标。
  Future<void> _editRemoteUrlDialog(GitRemoteInfo remote) async {
    await _textDialog(
      title: translateForWidget(ref, I18nKey.gitDialogEditRemoteUrl),
      label: I18nKey.gitRemoteUrl,
      initialValue: remote.url,
      selectAll: true,
      onSubmit: (value) async {
        final confirmed = await _confirmDeletion(
          title: translateForWidget(ref, I18nKey.gitDialogEditRemoteUrlConfirm),
          message: translateForWidgetWithReplacements(
            ref,
            I18nKey.gitDialogEditRemoteUrlBody,
            {'remote': remote.name, 'from': remote.url, 'to': value},
          ),
          confirmKey: I18nKey.commonConfirm,
        );
        if (!confirmed) return;
        // provider 会把失败写入 state.error，由页面顶层 ref.listen 弹错误提示；
        // 这里 await 是为了让失败发生在对话框流程内，不会被当成静默丢弃。
        await ref.read(gitProvider.notifier).setRemoteUrl(remote.name, value);
      },
    );
  }

  /// 重命名远端：libgit2 会同步迁移 remote-tracking 分支与配置。
  Future<void> _renameRemoteDialog(GitRemoteInfo remote) async {
    await _textDialog(
      title: translateForWidget(ref, I18nKey.gitDialogRenameRemote),
      label: I18nKey.gitRemoteName,
      initialValue: remote.name,
      selectAll: true,
      onSubmit: (value) async {
        final confirmed = await _confirmDeletion(
          title: translateForWidget(ref, I18nKey.gitDialogRenameRemote),
          message: translateForWidgetWithReplacements(
            ref,
            I18nKey.gitDialogRenameRemoteBody,
            {'from': remote.name, 'to': value},
          ),
          confirmKey: I18nKey.commonConfirm,
        );
        if (!confirmed) return;
        await ref.read(gitProvider.notifier).renameRemote(remote.name, value);
      },
    );
  }

  /// 删除远端：明确提示会移除 tracking 分支与配置，二次确认后才执行。
  Future<void> _deleteRemoteDialog(GitRemoteInfo remote) async {
    final confirmed = await _confirmDeletion(
      title: translateForWidget(ref, I18nKey.gitDialogDeleteRemote),
      message: translateForWidgetWithReplacements(
        ref,
        I18nKey.gitDialogDeleteRemoteBody,
        {'name': remote.name},
      ),
      confirmKey: I18nKey.gitDelete,
    );
    if (!confirmed) return;
    await ref.read(gitProvider.notifier).deleteRemote(remote.name);
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
              onPressed: state.isBusy ? null : _createTagDialog,
              icon: const Icon(Icons.sell_outlined),
              label: const UseText(I18nKey.gitTagHead),
            ),
            OutlinedButton.icon(
              onPressed: state.isBusy
                  ? null
                  : () => _textDialog(
                      title: I18nKey.gitMerge,
                      label: I18nKey.gitRefLabel,
                      onSubmit: ref.read(gitProvider.notifier).merge,
                    ),
              icon: const Icon(Icons.merge_type),
              label: const UseText(I18nKey.gitMerge),
            ),
            OutlinedButton.icon(
              onPressed: state.isBusy ? null : _rebaseDialog,
              icon: const Icon(Icons.linear_scale),
              label: const UseText(I18nKey.gitRebase),
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
        _SectionTitle(title: I18nKey.gitAdvancedOperations),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: state.isBusy
                  ? null
                  : () => _textDialog(
                      title: I18nKey.gitCherryPick,
                      label: I18nKey.gitShaTagOrRef,
                      onSubmit: ref.read(gitProvider.notifier).cherryPick,
                    ),
              icon: const Icon(Icons.control_point_duplicate_outlined),
              label: const UseText(I18nKey.gitCherryPick),
            ),
            OutlinedButton.icon(
              onPressed: state.isBusy
                  ? null
                  : () => ref.read(gitProvider.notifier).writeCommitGraph(),
              icon: const Icon(Icons.hub_outlined),
              label: const UseText(I18nKey.gitWriteCommitGraph),
            ),
          ],
        ),
        const SectionDivider(),
        _SectionTitle(
          title: I18nKey.gitStash,
          action: snapshot.stashes.isEmpty
              ? null
              : '${snapshot.stashes.length}',
        ),
        for (final stash in snapshot.stashes)
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            contentPadding: const EdgeInsetsDirectional.only(start: 4),
            leading: const Icon(Icons.inventory_2_outlined),
            title: Text(stash.message, overflow: TextOverflow.ellipsis),
            subtitle: Text(stash.sha.substring(0, 7)),
            trailing: Wrap(
              spacing: 4,
              children: [
                TooltipAnchor(
                  message: translateForWidget(ref, I18nKey.gitApply),
                  child: IconButton(
                    onPressed: state.isBusy
                        ? null
                        : () => ref
                              .read(gitProvider.notifier)
                              .applyStash(stash.index),
                    icon: const Icon(Icons.file_download_outlined),
                  ),
                ),
                TooltipAnchor(
                  message: translateForWidget(ref, I18nKey.gitPop),
                  child: IconButton(
                    onPressed: state.isBusy
                        ? null
                        : () => ref
                              .read(gitProvider.notifier)
                              .applyStash(stash.index, pop: true),
                    icon: const Icon(Icons.unarchive_outlined),
                  ),
                ),
                TooltipAnchor(
                  message: translateForWidget(ref, I18nKey.gitDelete),
                  child: IconButton(
                    onPressed: state.isBusy
                        ? null
                        : () => ref
                              .read(gitProvider.notifier)
                              .dropStash(stash.index),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              ],
            ),
          ),
        const SectionDivider(),
        _SectionTitle(
          title: I18nKey.gitSubmodule,
          action: snapshot.submodules.isEmpty
              ? null
              : '${snapshot.submodules.length}',
        ),
        for (final submodule in snapshot.submodules)
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            contentPadding: const EdgeInsetsDirectional.only(start: 4),
            leading: const Icon(Icons.account_tree_outlined),
            title: Text(submodule.path, overflow: TextOverflow.ellipsis),
            subtitle: Text(submodule.url, overflow: TextOverflow.ellipsis),
            trailing: TextButton(
              onPressed: state.isBusy
                  ? null
                  : () => ref
                        .read(gitProvider.notifier)
                        .updateSubmodule(submodule.name),
              child: const UseText(I18nKey.gitUpdate),
            ),
          ),
        const SectionDivider(),
        _SectionTitle(
          title: I18nKey.gitWorktree,
          action: snapshot.worktrees.isEmpty
              ? null
              : '${snapshot.worktrees.length}',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: state.isBusy ? null : _worktreeDialog,
              icon: const Icon(Icons.library_add_outlined),
              label: const UseText(I18nKey.gitCreateWorktree),
            ),
          ],
        ),
        for (final worktree in snapshot.worktrees)
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            contentPadding: const EdgeInsetsDirectional.only(start: 4),
            leading: const Icon(Icons.folder_copy_outlined),
            title: Text(worktree.name, overflow: TextOverflow.ellipsis),
            subtitle: Text(worktree.path, overflow: TextOverflow.ellipsis),
            trailing: TooltipAnchor(
              message: translateForWidget(ref, I18nKey.gitPrune),
              child: IconButton(
                onPressed: state.isBusy
                    ? null
                    : () => ref
                          .read(gitProvider.notifier)
                          .pruneWorktree(worktree.name),
                icon: const Icon(Icons.cleaning_services_outlined),
              ),
            ),
          ),
        const SectionDivider(),
        _SectionTitle(
          title: I18nKey.gitTag,
          action: snapshot.tags.isEmpty ? null : '${snapshot.tags.length}',
        ),
        for (final tag in snapshot.tags.take(50))
          ListTile(
            dense: true,
            leading: Icon(
              tag.isAnnotated ? Icons.local_offer : Icons.sell_outlined,
            ),
            title: Text(tag.name, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              [
                tag.targetSha,
                if (tag.isAnnotated)
                  tag.message.isEmpty ? 'annotated' : tag.message,
              ].join(' · '),
              overflow: TextOverflow.ellipsis,
            ),
            contentPadding: const EdgeInsetsDirectional.only(start: 4),
            trailing: TooltipAnchor(
              message: translateForWidget(ref, I18nKey.gitDelete),
              child: IconButton(
                onPressed: state.isBusy
                    ? null
                    : () => _deleteTagDialog(tag, snapshot),
                icon: const Icon(Icons.delete_outline),
              ),
            ),
          ),
        const SectionDivider(),
        _SectionTitle(title: I18nKey.gitTabCredentials),
        _credentialsSection(state),
      ],
    );
  }

  Widget _credentialsSection(GitViewState state) {
    final draft = state.credentials;
    _syncCredentialControllers(draft);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<GitCredentialMode>(
          segments: const [
            ButtonSegment(
              value: GitCredentialMode.none,
              icon: Icon(Icons.no_encryption_outlined),
              label: UseText(I18nKey.gitCredentialNone),
            ),
            ButtonSegment(
              value: GitCredentialMode.httpsToken,
              icon: Icon(Icons.token_outlined),
              label: UseText(I18nKey.gitHttpsToken),
            ),
            ButtonSegment(
              value: GitCredentialMode.sshAgent,
              icon: Icon(Icons.key_outlined),
              label: UseText(I18nKey.gitSshAgent),
            ),
            ButtonSegment(
              value: GitCredentialMode.sshKey,
              icon: Icon(Icons.vpn_key_outlined),
              label: UseText(I18nKey.gitSshKey),
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
            label: UseText(I18nKey.gitUsername),
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
              label: UseText(I18nKey.gitToken),
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
              label: UseText(I18nKey.gitPublicKeyPath),
              border: OutlineInputBorder(),
            ),
            onChanged: _updateCredentialDraft,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _privateKeyController,
            decoration: const InputDecoration(
              label: UseText(I18nKey.gitPrivateKeyPath),
              border: OutlineInputBorder(),
            ),
            onChanged: _updateCredentialDraft,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passphraseController,
            obscureText: true,
            decoration: const InputDecoration(
              label: UseText(I18nKey.gitPassphrase),
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

  Future<void> _checkoutBranch(GitBranchInfo branch) async {
    final blocked = await ref
        .read(gitProvider.notifier)
        .checkoutBranch(branch.name, remote: branch.isRemote);
    if (!mounted || blocked == null) return;

    final action = await _checkoutBlockedDialog(blocked);
    if (!mounted || action == null) return;

    final notifier = ref.read(gitProvider.notifier);
    switch (action) {
      case _CheckoutBlockedAction.stash:
        await notifier.checkoutBranchWithStash(
          blocked.branchName,
          remote: blocked.remote,
        );
      case _CheckoutBlockedAction.merge:
        await notifier.checkoutBranchWithMerge(
          blocked.branchName,
          remote: blocked.remote,
        );
      case _CheckoutBlockedAction.force:
        final forceAction = await _forceCheckoutDialog(blocked);
        if (!mounted || forceAction == null) return;
        switch (forceAction) {
          case _ForceCheckoutAction.all:
            await notifier.forceCheckoutBranch(
              blocked.branchName,
              remote: blocked.remote,
            );
          case _ForceCheckoutAction.listedTracked:
            await notifier.discardPathsAndCheckoutBranch(
              blocked.branchName,
              blocked.paths,
              remote: blocked.remote,
            );
        }
    }
  }

  Future<_CheckoutBlockedAction?> _checkoutBlockedDialog(
    GitCheckoutBlocked blocked,
  ) {
    return showDialog<_CheckoutBlockedAction>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_outlined),
        title: const UseText(I18nKey.gitCheckoutBlockedTitle),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                translateForWidget(
                  ref,
                  I18nKey.gitTargetBranch,
                ).replaceAll('{branch}', blocked.branchName),
              ),
              const SizedBox(height: 12),
              const UseText(I18nKey.gitCheckoutBlockedFiles),
              const SizedBox(height: 8),
              _BlockedPathList(paths: blocked.paths),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const UseText(I18nKey.commonCancel),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_CheckoutBlockedAction.force),
            child: const UseText(I18nKey.gitForceCheckout),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_CheckoutBlockedAction.merge),
            child: const UseText(I18nKey.gitMergeChanges),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(_CheckoutBlockedAction.stash),
            child: const UseText(I18nKey.gitStashAndCheckout),
          ),
        ],
      ),
    );
  }

  Future<_ForceCheckoutAction?> _forceCheckoutDialog(
    GitCheckoutBlocked blocked,
  ) {
    return showDialog<_ForceCheckoutAction>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          Icons.delete_sweep_outlined,
          color: Theme.of(context).colorScheme.error,
        ),
        title: const UseText(I18nKey.gitForceCheckoutScopeTitle),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const UseText(I18nKey.gitForceCheckoutWarning),
              const SizedBox(height: 12),
              const UseText(I18nKey.gitBlockedFiles),
              const SizedBox(height: 8),
              _BlockedPathList(paths: blocked.paths),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const UseText(I18nKey.commonCancel),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_ForceCheckoutAction.listedTracked),
            child: const UseText(I18nKey.gitDiscardTrackedFiles),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () =>
                Navigator.of(context).pop(_ForceCheckoutAction.all),
            child: const UseText(I18nKey.gitDiscardAllFiles),
          ),
        ],
      ),
    );
  }

  Future<void> _continueRebase() async {
    await ref.read(gitProvider.notifier).continueRebase(_commitInput());
  }

  Future<void> _rebaseDialog() async {
    await _textDialog(
      title: I18nKey.gitRebase,
      label: I18nKey.gitTargetRef,
      onSubmit: (value) => ref
          .read(gitProvider.notifier)
          .rebase(value, _commitInput(message: 'rebase')),
    );
  }

  Future<void> _worktreeDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return DialogFormFields(
          initialValues: const ['', ''],
          builder: (context, c) => AlertDialog(
            title: const UseText(I18nKey.gitCreateWorktree),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: c[0],
                  decoration: const InputDecoration(
                    label: UseText(I18nKey.gitName),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: c[1],
                  decoration: const InputDecoration(
                    label: UseText(I18nKey.gitPath),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const UseText(I18nKey.commonCancel),
              ),
              FilledButton(
                onPressed: () {
                  ref
                      .read(gitProvider.notifier)
                      .createWorktree(c[0].text, c[1].text);
                  Navigator.of(context).pop();
                },
                child: const UseText(I18nKey.commonCreate),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _remoteDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return DialogFormFields(
          initialValues: const ['origin', ''],
          builder: (context, c) => AlertDialog(
            title: const UseText(I18nKey.gitAddRemote),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: c[0],
                  decoration: const InputDecoration(
                    label: UseText(I18nKey.gitRemoteName),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: c[1],
                  autofocus: true,
                  decoration: const InputDecoration(
                    label: UseText(I18nKey.gitRemoteUrl),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const UseText(I18nKey.commonCancel),
              ),
              FilledButton(
                onPressed: () {
                  ref
                      .read(gitProvider.notifier)
                      .addRemote(c[0].text, c[1].text);
                  Navigator.of(context).pop();
                },
                child: const UseText(I18nKey.commonAdd),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _textDialog({
    required Object title,
    required Object label,
    required Future<void> Function(String value) onSubmit,
    String initialValue = '',
    bool selectAll = false,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return DialogFormFields(
          initialValues: [initialValue],
          selectAll: selectAll,
          builder: (context, c) => AlertDialog(
            title: UseText(title),
            content: TextField(
              controller: c[0],
              autofocus: true,
              decoration: InputDecoration(label: UseText(label)),
              onSubmitted: (value) {
                onSubmit(value);
                Navigator.of(context).pop();
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const UseText(I18nKey.commonCancel),
              ),
              FilledButton(
                onPressed: () {
                  onSubmit(c[0].text);
                  Navigator.of(context).pop();
                },
                child: const UseText(I18nKey.commonConfirm),
              ),
            ],
          ),
        );
      },
    );
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

/// Page-scoped theme that tightens git action buttons while keeping a
/// comfortable 40px height (not flat): buttons use tight horizontal padding
/// and shrink-wrap tap targets, and icon buttons are 30px with 18px icons.
ThemeData _compactChromeTheme(BuildContext context) {
  final base = Theme.of(context);
  return base.copyWith(
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 14),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 14),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(30, 30)),
        padding: const WidgetStatePropertyAll(
          EdgeInsetsDirectional.symmetric(horizontal: 2),
        ),
        iconSize: const WidgetStatePropertyAll(18),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
  );
}
