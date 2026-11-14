import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:git2dart/git2dart.dart';
import 'package:path/path.dart' as p;
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/git/git_debug_log.dart';
import 'package:pyrite_ide/core/services/git/git_isolate_runner.dart';
import 'package:pyrite_ide/core/services/git/git_models.dart';

const _maxUntrackedScanEntries = 20000;
const _maxUntrackedStatusEntries = 1000;
const _maxSnapshotUntrackedPatches = 20;
const _maxUntrackedPatchBytes = 256 * 1024;

class GitCommitInput {
  const GitCommitInput({
    required this.message,
    required this.authorName,
    required this.authorEmail,
  });

  final String message;
  final String authorName;
  final String authorEmail;
}

/// 本地分支 + 可选的同名远端分支。
///
/// 删除分支时 UI 需要知道“是否还有同名远端分支”，才能分别走本地删除和远端
/// 删除两条确认流程，所以这里把两侧信息放在一起返回，而不是让页面自己猜。
class GitBranchDeletionTarget {
  const GitBranchDeletionTarget({
    required this.name,
    required this.hasLocal,
    required this.hasRemote,
    this.remoteName = '',
    this.isCurrent = false,
  });

  final String name;
  final bool hasLocal;
  final bool hasRemote;

  /// 同名远端分支所在的 remote，例如 `origin`。
  final String remoteName;

  final bool isCurrent;

  /// 远端分支的完整名，例如 `origin/feature/demo`。
  String get remoteBranchName => remoteName.isEmpty ? '' : '$remoteName/$name';
}

class GitRepositoryService {
  GitRepositoryService({
    Duration commandTimeout = const Duration(seconds: 20),
    I18nTranslate? translate,
  }) : _commandTimeout = commandTimeout,
       // Defaulting to the fallback keeps the service testable without a
       // live data registry; the provider wires real translations in.
       _tr = translate ?? fallbackTranslate;

  /// 单次 Git 操作（含后台 isolate 调度）的超时。
  ///
  /// 由构造函数注入：测试里可以缩短它来验证超时路径，生产默认 20 秒。
  final Duration _commandTimeout;

  /// Renders a status/state label in the active locale.
  final I18nTranslate _tr;

  Duration get commandTimeout => _commandTimeout;

  Future<GitRepositorySnapshot?> loadSnapshot(String? workspacePath) async {
    GitDebugLog.log(
      'GitRepositoryService.loadSnapshot start workspace=$workspacePath',
    );
    final rootPath = await discoverRoot(workspacePath);
    if (rootPath == null) {
      GitDebugLog.log('GitRepositoryService.loadSnapshot no repository found');
      return null;
    }
    return _runInIsolate('loadSnapshot', () async {
      try {
        return await _withRepository(rootPath, _buildSnapshot);
      } catch (error, stackTrace) {
        GitDebugLog.log(
          'GitRepositoryService.loadSnapshot error root=$rootPath',
          error: error,
          stackTrace: stackTrace,
        );
        rethrow;
      }
    });
  }

  Future<String?> discoverRoot(String? workspacePath) async {
    if (workspacePath == null || workspacePath.isEmpty) return null;
    return _runInIsolate(
      'discoverRoot',
      () => _discoverRootSync(workspacePath),
      swallowErrors: true,
    );
  }

  Future<void> initRepository(String workspacePath) async {
    final path = workspacePath.trim();
    if (path.isEmpty) throw ArgumentError('工作区路径不能为空。');
    if (!Directory(path).existsSync()) {
      throw ArgumentError('工作区文件夹不存在：$path');
    }
    await _runInIsolate<void>('initRepository', () async {
      final repo = Repository.init(path: path);
      repo.free();
    });
  }

  Future<String> diffForPath(
    String rootPath,
    String filePath, {
    bool staged = false,
  }) {
    return _runInIsolate(
      'diffForPath',
      () => _withRepository(rootPath, (repo) async {
        final patch = staged
            ? _stagedPatch(repo, filePath: filePath)
            : _trackedUnstagedPatch(repo, filePath: filePath);
        if (patch.isNotEmpty || staged) return patch;
        return _untrackedFilePatch(_normalizeWorkdir(repo.workdir), filePath);
      }),
    );
  }

  Future<String> diffForEntry(
    String rootPath,
    GitStatusEntry entry, {
    bool staged = false,
  }) {
    if (entry.isUntracked && !staged) {
      return _runInIsolate(
        'diffForEntry',
        () => _untrackedFilePatch(rootPath, entry.path),
      );
    }
    return diffForPath(rootPath, entry.path, staged: staged);
  }

  Future<List<GitCommitInfo>> fileHistory(
    String rootPath,
    String filePath,
  ) async {
    return _runInIsolate(
      'fileHistory',
      () => _withRepository(
        rootPath,
        (repo) => _commits(repo, limit: 200, pathspec: filePath),
      ),
    );
  }

  Future<List<GitBlameLine>> blame(String rootPath, String filePath) async {
    return _runInIsolate(
      'blame',
      () => _withRepository(rootPath, (repo) {
        final blame = Blame.file(repo: repo, path: filePath);
        try {
          return [
            for (final hunk in blame)
              GitBlameLine(
                lineStart: hunk.finalStartLineNumber,
                lineCount: hunk.linesCount,
                commitSha: hunk.finalCommitOid.sha,
                author: hunk.finalCommitter?.name ?? '',
                email: hunk.finalCommitter?.email ?? '',
                time: _signatureTime(hunk.finalCommitter),
              ),
          ];
        } finally {
          blame.free();
        }
      }),
    );
  }

  Future<void> stage(String rootPath, Iterable<String> paths) async {
    final cleanPaths = _cleanPaths(paths).toList();
    await _runInIsolate<void>('stage', () async {
      await _withRepository(rootPath, (repo) {
        final index = repo.index;
        try {
          for (final rawPath in cleanPaths) {
            final absolutePath = p.join(
              _normalizeWorkdir(repo.workdir),
              rawPath,
            );
            if (Directory(absolutePath).existsSync()) {
              index.addAll([_gitPath(rawPath)]);
            } else if (File(absolutePath).existsSync()) {
              index.add(_gitPath(rawPath));
            } else {
              index.remove(_gitPath(rawPath));
            }
          }
          index.write();
        } finally {
          index.free();
        }
      });
    });
  }

  Future<void> unstage(String rootPath, Iterable<String> paths) async {
    final cleanPaths = _cleanPaths(paths).toList();
    if (cleanPaths.isEmpty) return;
    await _runInIsolate<void>('unstage', () async {
      await _withRepository(rootPath, (repo) {
        final headOid = _headOidOrNull(repo);
        if (headOid != null) {
          repo.resetDefault(
            oid: headOid,
            pathspec: cleanPaths.map(_gitPath).toList(),
          );
          return;
        }

        final index = repo.index;
        try {
          for (final path in cleanPaths) {
            index.remove(_gitPath(path));
          }
          index.write();
        } finally {
          index.free();
        }
      });
    });
  }

  Future<void> discardChanges(String rootPath, GitStatusEntry entry) async {
    await _runInIsolate<void>('discardChanges', () async {
      await _withRepository(rootPath, (repo) async {
        if (entry.isUntracked) {
          await _deleteUntrackedPath(
            _normalizeWorkdir(repo.workdir),
            entry.path,
          );
          return;
        }
        // 用户点“放弃改动”只应丢掉工作区里未暂存的编辑，已暂存内容必须
        // 保留。Checkout.head 会连 index 一起重置到 HEAD，因此这里以 index
        // 为源回填工作区，并禁止 checkout 写回 index。
        Checkout.index(
          repo: repo,
          strategy: const {
            GitCheckout.force,
            GitCheckout.recreateMissing,
            GitCheckout.dontUpdateIndex,
          },
          paths: [_gitPath(entry.path)],
        );
      });
    });
  }

  Future<void> commit(String rootPath, GitCommitInput input) async {
    await _runInIsolate<void>('commit', () async {
      await _withRepository(rootPath, (repo) {
        if (repo.index.hasConflicts) {
          throw StateError('仍有冲突未解决，不能提交。');
        }
        final message = input.message.trim();
        if (message.isEmpty) {
          throw ArgumentError('提交信息不能为空。');
        }

        final index = repo.index;
        try {
          final tree = Tree.lookup(repo: repo, oid: index.writeTree(repo));
          try {
            final signature = _signature(input);
            final parents = _commitParents(repo);
            Commit.create(
              repo: repo,
              updateRef: 'HEAD',
              author: signature,
              committer: signature,
              messageEncoding: 'UTF-8',
              message: message,
              tree: tree,
              parents: parents,
            );
            if (repo.state != GitRepositoryState.none &&
                repo.state != GitRepositoryState.rebase &&
                repo.state != GitRepositoryState.rebaseMerge) {
              repo.stateCleanup();
            }
          } finally {
            tree.free();
          }
        } finally {
          index.free();
        }
      });
    });
  }

  Future<void> createBranch(String rootPath, String name) async {
    final branchName = name.trim();
    await _runInIsolate<void>('createBranch', () async {
      await _withRepository(rootPath, (repo) {
        if (branchName.isEmpty) throw ArgumentError('分支名称不能为空。');
        final head = _headCommit(repo);
        Branch.create(repo: repo, name: branchName, target: head);
      });
    });
  }

  /// 删除本地分支。
  ///
  /// 使用 `git_branch_delete` 语义（等价 `git branch -d`），未合并的分支会被
  /// libgit2 拒绝；当前分支也无法删除，两种情况都会以可读的中文错误抛出。
  /// 需要丢弃未合并提交时显式传 [force]（等价 `git branch -D`）。
  Future<void> deleteBranch(
    String rootPath,
    String name, {
    bool force = false,
  }) async {
    final branchName = name.trim();
    if (branchName.isEmpty) throw ArgumentError('分支名称不能为空。');
    await _runInIsolate<void>('deleteBranch', () async {
      await _withRepository(rootPath, (repo) {
        final current = _currentBranch(repo);
        if (current == branchName) {
          throw StateError('不能删除当前分支 $branchName，请先切换到其他分支。');
        }
        try {
          Branch.lookup(repo: repo, name: branchName).free();
        } catch (_) {
          throw ArgumentError('分支不存在：$branchName');
        }
        if (!force) {
          final head = _headCommitOrNull(repo);
          if (head != null) {
            final target = Branch.lookup(repo: repo, name: branchName).target;
            if (!_isMergedInto(repo, head, target)) {
              throw StateError('分支 $branchName 尚未合并到当前分支；请使用强制删除。');
            }
          }
        }
        Branch.delete(repo: repo, name: branchName);
      });
    });
  }

  /// 删除远端分支。
  ///
  /// 通过 push 一个空 refspec（`git push <remote> :<branch>`）实现；这是
  /// libgit2 唯一稳定的远端分支删除方式。[branchName] 是远端上的分支短名
  /// （例如 `feature/demo`），不要带 `remote/` 前缀。
  Future<String> deleteRemoteBranch(
    String rootPath,
    String remoteName,
    String branchName,
    GitCredentialDraft draft,
  ) async {
    final remote = remoteName.trim();
    final branch = branchName.trim();
    if (remote.isEmpty) throw ArgumentError('远端名称不能为空。');
    if (branch.isEmpty) throw ArgumentError('远端分支名称不能为空。');
    return _runInIsolate(
      'deleteRemoteBranch',
      () => _withRepository(rootPath, (repo) {
        final handle = Remote.lookup(repo: repo, name: remote);
        try {
          handle.push(
            refspecs: [':refs/heads/$branch'],
            callbacks: _callbacks(draft),
          );
        } finally {
          handle.free();
        }
        _pruneRemoteTrackingBranch(repo, remote, branch);
        return applyI18nFallback(I18nKey.gitMessageRemoteBranchDeletedFull, {
          'remote': remote,
          'branch': branch,
        });
      }),
    );
  }

  /// 重命名分支（含当前分支场景）。
  ///
  /// `git_branch_move` 在 HEAD 指向旧分支时会自动把 HEAD 迁移到新分支，
  /// 因此当前分支重命名不需要额外处理；重命名后统一刷新 UI snapshot。
  Future<void> renameBranch(
    String rootPath,
    String oldName,
    String newName, {
    bool force = false,
  }) async {
    final from = oldName.trim();
    final to = newName.trim();
    if (from.isEmpty) throw ArgumentError('原分支名称不能为空。');
    if (to.isEmpty) throw ArgumentError('新分支名称不能为空。');
    if (from == to) return;
    await _runInIsolate<void>('renameBranch', () async {
      await _withRepository(rootPath, (repo) {
        if (!Branch.isNameValid(to)) {
          throw ArgumentError('分支名称不合法：$to');
        }
        try {
          Branch.lookup(repo: repo, name: from).free();
        } catch (_) {
          throw ArgumentError('分支不存在：$from');
        }
        Branch.rename(repo: repo, oldName: from, newName: to, force: force);
      });
    });
  }

  /// 删除 tag（本地 + 可选远端）。
  ///
  /// [remoteName] 为空时只删除本地 tag；非空时先推送删除远端同名 tag，
  /// 成功后再删除本地，避免出现“本地没了、远端还在”的静默不一致。
  Future<String> deleteTag(
    String rootPath,
    String name, {
    String? remoteName,
    GitCredentialDraft draft = const GitCredentialDraft(),
  }) async {
    final tagName = name.trim();
    if (tagName.isEmpty) throw ArgumentError('标签名称不能为空。');
    final remote = remoteName?.trim() ?? '';
    return _runInIsolate(
      'deleteTag',
      () => _withRepository(rootPath, (repo) {
        if (remote.isNotEmpty) {
          final handle = Remote.lookup(repo: repo, name: remote);
          try {
            handle.push(
              refspecs: [':refs/tags/$tagName'],
              callbacks: _callbacks(draft),
            );
          } finally {
            handle.free();
          }
        }
        Tag.delete(repo: repo, tagName: tagName);
        return remote.isEmpty
            ? applyI18nFallback(I18nKey.gitMessageTagDeleted, {'name': tagName})
            : applyI18nFallback(I18nKey.gitMessageTagDeletedLocalAndRemote, {
                'remote': remote,
                'name': tagName,
              });
      }),
    );
  }

  /// 把某个 tag 推送到远端（`git push <remote> refs/tags/<name>`）。
  Future<String> pushTag(
    String rootPath,
    String remoteName,
    String tagName,
    GitCredentialDraft draft,
  ) async {
    final remote = remoteName.trim();
    final tag = tagName.trim();
    if (remote.isEmpty) throw ArgumentError('远端名称不能为空。');
    if (tag.isEmpty) throw ArgumentError('标签名称不能为空。');
    return _runInIsolate(
      'pushTag',
      () => _withRepository(rootPath, (repo) {
        final handle = Remote.lookup(repo: repo, name: remote);
        try {
          handle.push(
            refspecs: ['refs/tags/$tag:refs/tags/$tag'],
            callbacks: _callbacks(draft),
          );
        } finally {
          handle.free();
        }
        return applyI18nFallback(I18nKey.gitMessageTagPushed, {
          'tag': tag,
          'remote': remote,
        });
      }),
    );
  }

  Future<void> checkoutBranch(
    String rootPath,
    String name, {
    bool remote = false,
  }) async {
    await _runInIsolate<void>('checkoutBranch', () async {
      await _withRepository(rootPath, (repo) {
        _checkoutBranch(repo, name, remote: remote);
      });
    });
  }

  Future<void> checkoutBranchWithStash(
    String rootPath,
    String name, {
    bool remote = false,
  }) async {
    await _runInIsolate<void>('checkoutBranchWithStash', () async {
      await _withRepository(rootPath, (repo) {
        final signature = _defaultSignature(repo);
        Stash.create(
          repo: repo,
          stasher: signature,
          message: 'PyriteIDE: stash before switching to ${name.trim()}',
          flags: const {GitStash.includeUntracked},
        );
        _checkoutBranch(repo, name, remote: remote);
      });
    });
  }

  Future<void> checkoutBranchWithMerge(
    String rootPath,
    String name, {
    bool remote = false,
  }) async {
    await _runInIsolate<void>('checkoutBranchWithMerge', () async {
      await _withRepository(rootPath, (repo) {
        _checkoutBranch(
          repo,
          name,
          remote: remote,
          strategy: const {
            GitCheckout.safe,
            GitCheckout.recreateMissing,
            GitCheckout.allowConflicts,
            GitCheckout.conflictStyleMerge,
          },
        );
      });
    });
  }

  Future<void> forceCheckoutBranch(
    String rootPath,
    String name, {
    bool remote = false,
  }) async {
    await _runInIsolate<void>('forceCheckoutBranch', () async {
      await _withRepository(rootPath, (repo) {
        final headOid = _headOidOrNull(repo);
        if (headOid != null) {
          repo.reset(
            oid: headOid,
            resetType: GitReset.hard,
            strategy: const {
              GitCheckout.force,
              GitCheckout.removeUntracked,
              GitCheckout.recreateMissing,
            },
          );
        }
        _checkoutBranch(
          repo,
          name,
          remote: remote,
          strategy: const {
            GitCheckout.force,
            GitCheckout.removeUntracked,
            GitCheckout.recreateMissing,
          },
        );
      });
    });
  }

  Future<void> discardTrackedPathsAndCheckoutBranch(
    String rootPath,
    String name,
    Iterable<String> paths, {
    bool remote = false,
  }) async {
    final trackedPaths = _cleanPaths(paths).map(_gitPath).toList();
    await _runInIsolate<void>('discardPathsAndCheckoutBranch', () async {
      await _withRepository(rootPath, (repo) {
        if (trackedPaths.isNotEmpty) {
          Checkout.head(
            repo: repo,
            strategy: const {GitCheckout.force, GitCheckout.recreateMissing},
            paths: trackedPaths,
          );
        }
        _checkoutBranch(repo, name, remote: remote);
      });
    });
  }

  Future<void> stash(
    String rootPath,
    GitCommitInput input, {
    bool includeUntracked = true,
  }) async {
    await _runInIsolate<void>('stash', () async {
      await _withRepository(rootPath, (repo) {
        final message = input.message.trim().isEmpty
            ? 'WIP'
            : input.message.trim();
        Stash.create(
          repo: repo,
          stasher: _signature(input),
          message: message,
          flags: includeUntracked
              ? const {GitStash.includeUntracked}
              : const {GitStash.defaults},
        );
      });
    });
  }

  Future<void> applyStash(
    String rootPath,
    int index, {
    bool pop = false,
  }) async {
    await _runInIsolate<void>('applyStash', () async {
      await _withRepository(rootPath, (repo) {
        if (pop) {
          Stash.pop(repo: repo, index: index);
        } else {
          Stash.apply(repo: repo, index: index);
        }
      });
    });
  }

  Future<void> dropStash(String rootPath, int index) async {
    await _runInIsolate<void>('dropStash', () async {
      await _withRepository(rootPath, (repo) {
        Stash.drop(repo: repo, index: index);
      });
    });
  }

  Future<String> fetch(
    String rootPath,
    String remoteName,
    GitCredentialDraft draft,
  ) async {
    return _runInIsolate(
      'fetch',
      () => _withRepository(rootPath, (repo) {
        final remote = Remote.lookup(repo: repo, name: remoteName);
        try {
          remote.fetch(callbacks: _callbacks(draft));
        } finally {
          remote.free();
        }
        return applyI18nFallback(I18nKey.gitMessageFetched, {
          'remote': remoteName,
        });
      }),
    );
  }

  Future<String> push(
    String rootPath,
    String remoteName,
    GitCredentialDraft draft,
  ) async {
    return _runInIsolate(
      'push',
      () => _withRepository(rootPath, (repo) {
        final branch = _currentBranch(repo);
        if (branch == null) {
          throw StateError('当前不是可推送的本地分支。');
        }
        final remote = Remote.lookup(repo: repo, name: remoteName);
        try {
          remote.push(
            refspecs: ['refs/heads/$branch:refs/heads/$branch'],
            callbacks: _callbacks(draft),
          );
        } finally {
          remote.free();
        }
        // 等价 `git push -u`：首次推送后记录 upstream，否则分支列表永远显示
        // 不出 ahead/behind。已有 upstream 时保持不动。
        _ensureBranchUpstream(repo, branch, remoteName);
        return applyI18nFallback(I18nKey.gitMessagePushed, {
          'branch': branch,
          'remote': remoteName,
        });
      }),
    );
  }

  Future<String> pull(
    String rootPath,
    String remoteName,
    GitCredentialDraft draft,
  ) async {
    return _runInIsolate(
      'pull',
      () => _withRepository(rootPath, (repo) {
        final branch = _currentBranch(repo);
        if (branch == null) {
          throw StateError('当前 HEAD 分离，不能自动 pull。');
        }

        final remote = Remote.lookup(repo: repo, name: remoteName);
        try {
          remote.fetch(callbacks: _callbacks(draft));
        } finally {
          remote.free();
        }

        final upstreamSpec =
            _upstreamSpec(repo, branch) ?? '$remoteName/$branch';
        _merge(repo, upstreamSpec);
        return applyI18nFallback(I18nKey.gitMessagePulled, {
          'remote': remoteName,
          'branch': branch,
        });
      }),
    );
  }

  Future<void> addRemote(String rootPath, String name, String url) async {
    final remoteName = name.trim();
    final remoteUrl = url.trim();
    if (remoteName.isEmpty) throw ArgumentError('远端名称不能为空。');
    if (remoteUrl.isEmpty) throw ArgumentError('远端 URL 不能为空。');
    await _runInIsolate<void>('addRemote', () async {
      await _withRepository(rootPath, (repo) {
        final remote = Remote.create(
          repo: repo,
          name: remoteName,
          url: remoteUrl,
        );
        remote.free();
      });
    });
  }

  /// 修改远端 URL。
  ///
  /// 同时更新 push URL（若原 push URL 与 fetch URL 不同，说明用户单独配置过
  /// push 地址，这里保留原值，避免悄悄覆盖）。
  Future<void> setRemoteUrl(String rootPath, String name, String url) async {
    final remoteName = name.trim();
    final remoteUrl = url.trim();
    if (remoteName.isEmpty) throw ArgumentError('远端名称不能为空。');
    if (remoteUrl.isEmpty) throw ArgumentError('远端 URL 不能为空。');
    await _runInIsolate<void>('setRemoteUrl', () async {
      await _withRepository(rootPath, (repo) {
        final existing = Remote.lookup(repo: repo, name: remoteName);
        final previousUrl = existing.url;
        final previousPushUrl = existing.pushUrl;
        existing.free();
        Remote.setUrl(repo: repo, remote: remoteName, url: remoteUrl);
        if (previousPushUrl.isEmpty || previousPushUrl == previousUrl) {
          Remote.setPushUrl(repo: repo, remote: remoteName, url: remoteUrl);
        }
      });
    });
  }

  /// 重命名远端，并返回 libgit2 报告无法迁移的非默认 refspec。
  Future<List<String>> renameRemote(
    String rootPath,
    String oldName,
    String newName,
  ) async {
    final from = oldName.trim();
    final to = newName.trim();
    if (from.isEmpty) throw ArgumentError('原远端名称不能为空。');
    if (to.isEmpty) throw ArgumentError('新远端名称不能为空。');
    if (from == to) return const [];
    return _runInIsolate(
      'renameRemote',
      () => _withRepository(rootPath, (repo) {
        if (!Remote.list(repo).contains(from)) {
          throw ArgumentError('远端不存在：$from');
        }
        return Remote.rename(repo: repo, oldName: from, newName: to);
      }),
    );
  }

  Future<void> deleteRemote(String rootPath, String name) async {
    final remoteName = name.trim();
    if (remoteName.isEmpty) throw ArgumentError('远端名称不能为空。');
    await _runInIsolate<void>('deleteRemote', () async {
      await _withRepository(rootPath, (repo) {
        if (!Remote.list(repo).contains(remoteName)) {
          throw ArgumentError('远端不存在：$remoteName');
        }
        Remote.delete(repo: repo, name: remoteName);
      });
    });
  }

  /// 查询某个分支名在本地/远端两侧的存在情况。
  ///
  /// 删除分支前调用，让 UI 能分别确认“删除本地分支”和“删除同名远端分支”。
  Future<GitBranchDeletionTarget> inspectBranchDeletionTarget(
    String rootPath,
    String name,
  ) async {
    final branchName = name.trim();
    if (branchName.isEmpty) throw ArgumentError('分支名称不能为空。');
    return _runInIsolate(
      'inspectBranchDeletionTarget',
      () => _withRepository(rootPath, (repo) {
        final hasLocal = _branchExists(repo, branchName);
        final current = _currentBranch(repo);
        final remoteTarget = _remoteBranchTarget(repo, branchName);
        return GitBranchDeletionTarget(
          name: branchName,
          hasLocal: hasLocal,
          hasRemote: remoteTarget != null,
          remoteName: remoteTarget?.$1 ?? '',
          isCurrent: current == branchName,
        );
      }),
    );
  }

  Future<void> merge(String rootPath, String targetSpec) async {
    await _runInIsolate<void>('merge', () async {
      await _withRepository(rootPath, (repo) {
        _merge(repo, targetSpec);
      });
    });
  }

  Future<void> rebase(
    String rootPath,
    String targetSpec,
    GitCommitInput input,
  ) async {
    await _runInIsolate<void>('rebase', () async {
      await _withRepository(rootPath, (repo) {
        final upstream = AnnotatedCommit.fromRevSpec(
          repo: repo,
          spec: targetSpec,
        );
        final rebase = Rebase.init(repo: repo, upstream: upstream);
        try {
          _advanceRebase(repo, rebase, input);
        } finally {
          rebase.free();
          upstream.free();
        }
      });
    });
  }

  Future<void> continueRebase(String rootPath, GitCommitInput input) async {
    await _runInIsolate<void>('continueRebase', () async {
      await _withRepository(rootPath, (repo) {
        if (repo.index.hasConflicts) {
          throw StateError('仍有冲突未解决，不能继续 rebase。');
        }
        final rebase = Rebase.open(repo);
        try {
          rebase.commit(committer: _signature(input));
          _advanceRebase(repo, rebase, input);
        } finally {
          rebase.free();
        }
      });
    });
  }

  Future<void> abortRebase(String rootPath) async {
    await _runInIsolate<void>('abortRebase', () async {
      await _withRepository(rootPath, (repo) {
        final rebase = Rebase.open(repo);
        try {
          rebase.abort();
        } finally {
          rebase.free();
        }
      });
    });
  }

  Future<void> cherryPick(String rootPath, String targetSpec) async {
    await _runInIsolate<void>('cherryPick', () async {
      await _withRepository(rootPath, (repo) {
        final commit = _commitFromSpec(repo, targetSpec);
        Merge.cherryPick(repo: repo, commit: commit);
        if (repo.index.hasConflicts) return;

        final index = repo.index;
        try {
          final tree = Tree.lookup(repo: repo, oid: index.writeTree(repo));
          try {
            Commit.create(
              repo: repo,
              updateRef: 'HEAD',
              author: commit.author,
              committer: _defaultSignature(repo),
              messageEncoding: commit.messageEncoding,
              message: commit.message,
              tree: tree,
              parents: _commitParents(repo),
            );
            if (repo.state != GitRepositoryState.none) repo.stateCleanup();
          } finally {
            tree.free();
          }
        } finally {
          index.free();
        }
      });
    });
  }

  Future<void> markResolved(String rootPath, String filePath) {
    return stage(rootPath, [filePath]);
  }

  Future<void> acceptConflictSide(
    String rootPath,
    String filePath,
    GitConflictSide side,
  ) async {
    await _runInIsolate<void>('acceptConflictSide', () async {
      await _withRepository(rootPath, (repo) {
        Checkout.index(
          repo: repo,
          strategy: {
            GitCheckout.force,
            side == GitConflictSide.ours
                ? GitCheckout.useOurs
                : GitCheckout.useTheirs,
          },
          paths: [_gitPath(filePath)],
        );
        final index = repo.index;
        try {
          index.add(_gitPath(filePath));
          index.write();
        } finally {
          index.free();
        }
      });
    });
  }

  /// 创建 tag。
  ///
  /// 保留原有的 lightweight 路径（无 message），新增 annotated 路径：
  /// [GitTagInput.message] 非空时用 `Tag.createAnnotated` 写入 tagger 与消息。
  Future<void> createTag(
    String rootPath,
    String name, {
    String? targetSpec,
    String? message,
  }) async {
    final tagName = name.trim();
    final tagMessage = message?.trim() ?? '';
    final spec = targetSpec?.trim().isNotEmpty == true
        ? targetSpec!.trim()
        : 'HEAD';
    if (tagName.isEmpty) throw ArgumentError('标签名称不能为空。');
    await _runInIsolate<void>('createTag', () async {
      await _withRepository(rootPath, (repo) {
        final target = _objectFromSpec(repo, spec);
        final oid = switch (target) {
          Commit(:final oid) => oid,
          Tree(:final oid) => oid,
          Blob(:final oid) => oid,
          Tag(:final oid) => oid,
          _ => throw ArgumentError('不支持的标签目标。'),
        };
        final type = _objectType(target);
        if (tagMessage.isEmpty) {
          Tag.createLightweight(
            repo: repo,
            tagName: tagName,
            target: oid,
            targetType: type,
          );
          return;
        }
        Tag.createAnnotated(
          repo: repo,
          tagName: tagName,
          target: oid,
          targetType: type,
          tagger: _defaultSignature(repo),
          message: tagMessage,
        );
      });
    });
  }

  Future<void> createWorktree(String rootPath, String name, String path) async {
    final worktreeName = name.trim();
    final worktreePath = path.trim();
    if (worktreeName.isEmpty) throw ArgumentError('worktree 名称不能为空。');
    if (worktreePath.isEmpty) throw ArgumentError('worktree 路径不能为空。');
    await _runInIsolate<void>('createWorktree', () async {
      await _withRepository(rootPath, (repo) {
        Reference? ref;
        try {
          ref = Reference.lookup(repo: repo, name: _localRefName(worktreeName));
        } catch (_) {
          ref = null;
        }
        final worktree = Worktree.create(
          repo: repo,
          name: worktreeName,
          path: worktreePath,
          ref: ref,
        );
        worktree.free();
        ref?.free();
      });
    });
  }

  Future<void> pruneWorktree(String rootPath, String name) async {
    await _runInIsolate<void>('pruneWorktree', () async {
      await _withRepository(rootPath, (repo) {
        final worktree = Worktree.lookup(repo: repo, name: name);
        try {
          worktree.prune(const {
            GitWorktree.pruneValid,
            GitWorktree.pruneLocked,
            GitWorktree.pruneWorkingTree,
          });
        } finally {
          worktree.free();
        }
      });
    });
  }

  Future<void> updateSubmodule(
    String rootPath,
    String name,
    GitCredentialDraft draft,
  ) async {
    await _runInIsolate<void>('updateSubmodule', () async {
      await _withRepository(rootPath, (repo) {
        Submodule.update(
          repo: repo,
          name: name,
          init: true,
          callbacks: _callbacks(draft),
        );
      });
    });
  }

  Future<void> writeCommitGraph(String rootPath) async {
    await _runInIsolate<void>('writeCommitGraph', () async {
      await _withRepository(rootPath, (_) {
        // git2dart/libgit2 does not expose commit-graph writing. Keep the action
        // command-free so mobile platforms do not shell out to a missing Git CLI.
      });
    });
  }

  /// 在后台 isolate 中执行 [body]，把异常还原成原始的 Dart 异常类型。
  ///
  /// [swallowErrors] 为 true 时，任何失败都返回 [fallback]（用于 discoverRoot
  /// 这类“失败即视为没有仓库”的探测型 API）；否则异常会原样抛回调用方。
  Future<T> _runInIsolate<T>(
    String label,
    FutureOr<T> Function() body, {
    bool swallowErrors = false,
    T? fallback,
  }) async {
    final stopwatch = Stopwatch()..start();
    GitDebugLog.log('GitRepositoryService.$label isolate start');
    try {
      final result = await runGitJob<T>(
        () async => body(),
        timeout: _commandTimeout,
        debugLabel: label,
        describeError: _describeJobError,
        translate: _tr,
      );
      GitDebugLog.log(
        'GitRepositoryService.$label isolate end '
        '${stopwatch.elapsedMilliseconds}ms',
      );
      return result;
    } on GitJobFailureException catch (error, stackTrace) {
      final restored = _restoreJobError(error.failure);
      GitDebugLog.log(
        'GitRepositoryService.$label isolate failed code=${error.failure.code}',
        error: restored,
        stackTrace: error.failure.stack.isEmpty ? stackTrace : null,
      );
      if (swallowErrors) return fallback as T;
      Error.throwWithStackTrace(restored, stackTrace);
    } on TimeoutException {
      GitDebugLog.log(
        'GitRepositoryService.$label isolate timeout '
        '${stopwatch.elapsedMilliseconds}ms',
      );
      if (swallowErrors) return fallback as T;
      rethrow;
    }
  }

  /// 把 [GitJobFailure] 还原成调用方可判定的具体异常类型。
  ///
  /// 只还原服务层主动抛出、且调用方会做分支处理的类型；其余（libgit2 的
  /// `Error` 子类）统一还原为 [GitJobFailureException] 文本，避免跨 isolate
  /// 伪造原生错误对象。
  Object _restoreJobError(GitJobFailure failure) {
    return switch (failure.code) {
      'blocked' => GitCheckoutBlockedException(
        message: failure.message,
        paths: failure.paths,
      ),
      'argument' => ArgumentError(failure.message),
      'state' => StateError(failure.message),
      'format' => FormatException(failure.message),
      'timeout' => TimeoutException(failure.message, _commandTimeout),
      _ =>
        failure.isError
            ? GitRepositoryFailureError(failure.message)
            : GitRepositoryFailure(failure.message),
    };
  }

  /// 工作 isolate 内的异常分类器。
  GitJobFailure _describeJobError(Object error, StackTrace stackTrace) {
    final stack = '$stackTrace';
    if (error is GitCheckoutBlockedException) {
      return GitJobFailure(
        code: 'blocked',
        message: error.message,
        paths: error.paths,
        stack: stack,
      );
    }
    if (error is ArgumentError) {
      return GitJobFailure(
        code: 'argument',
        message: '${error.message ?? error}',
        stack: stack,
      );
    }
    if (error is StateError) {
      return GitJobFailure(code: 'state', message: error.message, stack: stack);
    }
    if (error is FormatException) {
      return GitJobFailure(
        code: 'format',
        message: error.message,
        stack: stack,
      );
    }
    return GitJobFailure(
      code: 'other',
      message: '$error',
      stack: stack,
      isError: error is Error,
    );
  }

  String? _discoverRootSync(String workspacePath) {
    final startPath = Directory(workspacePath).existsSync()
        ? workspacePath
        : p.dirname(workspacePath);
    try {
      final gitDir = Repository.discover(startPath: startPath);
      GitDebugLog.log('Repository.discover end gitDir=$gitDir');
      final repo = Repository.open(gitDir);
      try {
        final workdir = repo.workdir;
        if (workdir.isEmpty) return p.normalize(p.dirname(gitDir));
        return _normalizeWorkdir(workdir);
      } finally {
        repo.free();
      }
    } catch (error, stackTrace) {
      GitDebugLog.log(
        'GitRepositoryService.discoverRoot failed startPath=$startPath',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// 组装一次完整 snapshot。所有回调都在同一个 isolate 里执行，返回的
  /// [GitRepositorySnapshot] 只含基本类型/DTO，可安全跨 isolate 传递。
  Future<GitRepositorySnapshot> _buildSnapshot(Repository repo) async {
    final statusEntries = GitDebugLog.timeSync(
      'GitRepositoryService.statusEntries',
      () => _statusEntries(repo),
      result: (value) =>
          'count=${value.length} untracked=${value.where((entry) => entry.isUntracked).length}',
    );
    final conflicts = await GitDebugLog.timeAsync(
      'GitRepositoryService.conflicts',
      () => _conflicts(repo, statusEntries),
      result: (value) => 'count=${value.length}',
    );
    final aheadBehind = GitDebugLog.timeSync(
      'GitRepositoryService.aheadBehind',
      () => _aheadBehind(repo),
      result: (value) => 'ahead=${value.$1} behind=${value.$2}',
    );
    final unstagedPatch = await GitDebugLog.timeAsync(
      'GitRepositoryService.unstagedPatch',
      () => _unstagedPatch(repo, statusEntries),
      result: (value) => 'bytes=${value.length}',
    );
    final root = _normalizeWorkdir(repo.workdir);
    final gitDir = p.normalize(repo.path);
    final branchLabel = GitDebugLog.timeSync(
      'GitRepositoryService.branchLabel',
      () => _branchLabel(repo),
    );
    final stateLabel = GitDebugLog.timeSync(
      'GitRepositoryService.repositoryStateLabel',
      () => _repositoryStateLabel(repo),
    );
    final isDetached = _isDetached(repo);
    final isEmpty = _isEmpty(repo);
    final authorName = _configValue(repo, 'user.name') ?? 'Pyrite User';
    final authorEmail =
        _configValue(repo, 'user.email') ?? 'pyrite@example.local';
    final branches = GitDebugLog.timeSync(
      'GitRepositoryService.branches',
      () => _branches(repo),
      result: (value) => 'count=${value.length}',
    );
    final remotes = GitDebugLog.timeSync(
      'GitRepositoryService.remotes',
      () => _remotes(repo),
      result: (value) => 'count=${value.length}',
    );
    final stashes = GitDebugLog.timeSync(
      'GitRepositoryService.stashes',
      () => _stashes(repo),
      result: (value) => 'count=${value.length}',
    );
    final tags = GitDebugLog.timeSync(
      'GitRepositoryService.tags',
      () => _tags(repo),
      result: (value) => 'count=${value.length}',
    );
    final submodules = GitDebugLog.timeSync(
      'GitRepositoryService.submodules',
      () => _submodules(repo),
      result: (value) => 'count=${value.length}',
    );
    final worktrees = GitDebugLog.timeSync(
      'GitRepositoryService.worktrees',
      () => _worktrees(repo),
      result: (value) => 'count=${value.length}',
    );
    final commits = GitDebugLog.timeSync(
      'GitRepositoryService.commits',
      () => _commits(repo),
      result: (value) => 'count=${value.length}',
    );
    final stagedPatch = GitDebugLog.timeSync(
      'GitRepositoryService.stagedPatch',
      () => _stagedPatch(repo),
      result: (value) => 'bytes=${value.length}',
    );

    GitDebugLog.log(
      'GitRepositoryService.loadSnapshot complete root=$root '
      'gitDir=$gitDir status=${statusEntries.length} '
      'branches=${branches.length} commits=${commits.length}',
    );
    return GitRepositorySnapshot(
      rootPath: root,
      gitDir: gitDir,
      branchLabel: branchLabel,
      stateLabel: stateLabel,
      isDetached: isDetached,
      isEmpty: isEmpty,
      authorName: authorName,
      authorEmail: authorEmail,
      ahead: aheadBehind.$1,
      behind: aheadBehind.$2,
      statusEntries: statusEntries,
      branches: branches,
      remotes: remotes,
      stashes: stashes,
      tags: tags,
      submodules: submodules,
      worktrees: worktrees,
      commits: commits,
      conflicts: conflicts,
      stagedPatch: stagedPatch,
      unstagedPatch: unstagedPatch,
    );
  }

  Future<T> _withRepository<T>(
    String rootPath,
    FutureOr<T> Function(Repository repo) action,
  ) async {
    final stopwatch = Stopwatch()..start();
    GitDebugLog.log('Repository.open(root) start root=$rootPath');
    final repo = Repository.open(rootPath);
    GitDebugLog.log(
      'Repository.open(root) end ${stopwatch.elapsedMilliseconds}ms '
      'path=${repo.path} workdir=${repo.workdir}',
    );
    try {
      return await action(repo);
    } catch (error, stackTrace) {
      GitDebugLog.log(
        'Repository action error root=$rootPath',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    } finally {
      GitDebugLog.log('Repository.free(root) start root=$rootPath');
      repo.free();
      GitDebugLog.log('Repository.free(root) end root=$rootPath');
    }
  }

  String _branchLabel(Repository repo) {
    final branch = _currentBranch(repo);
    if (branch != null) return branch;

    final headOid = _headOidOrNull(repo);
    return headOid == null
        ? _tr(I18nKey.gitStatusUnbornHead)
        : 'HEAD@${headOid.toStrN(7)}';
  }

  String? _currentBranch(Repository repo) {
    try {
      if (repo.isHeadDetached || repo.isEmpty) return null;
      final head = repo.head;
      return head.shorthand;
    } catch (_) {
      return null;
    }
  }

  bool _isDetached(Repository repo) =>
      _tryValue(() => repo.isHeadDetached) ?? false;

  bool _isEmpty(Repository repo) => _tryValue(() => repo.isEmpty) ?? true;

  (int, int) _aheadBehind(Repository repo) {
    try {
      final branchName = _currentBranch(repo);
      if (branchName == null) return (0, 0);
      final branch = Branch.lookup(repo: repo, name: branchName);
      final upstream = branch.upstream;
      final values = repo.aheadBehind(
        local: branch.target,
        upstream: upstream.target,
      );
      return (values[0], values[1]);
    } catch (_) {
      return (0, 0);
    }
  }

  Future<String> _unstagedPatch(
    Repository repo,
    List<GitStatusEntry> entries,
  ) async {
    final rootPath = _normalizeWorkdir(repo.workdir);
    GitDebugLog.log(
      'GitRepositoryService._unstagedPatch start entries=${entries.length}',
    );
    final parts = <String>[_trackedUnstagedPatch(repo)];
    var untrackedPatchCount = 0;
    for (final entry in entries) {
      if (!entry.isUntracked) continue;
      if (untrackedPatchCount >= _maxSnapshotUntrackedPatches) break;
      GitDebugLog.log(
        'GitRepositoryService._unstagedPatch untracked start '
        'path=${entry.path} index=$untrackedPatchCount',
      );
      final patch = await _untrackedFilePatch(rootPath, entry.path);
      if (patch.isNotEmpty) parts.add(patch);
      untrackedPatchCount++;
    }
    return parts.where((part) => part.isNotEmpty).join('\n');
  }

  String _trackedUnstagedPatch(Repository repo, {String? filePath}) {
    GitDebugLog.log(
      'GitRepositoryService._trackedUnstagedPatch start filePath=$filePath',
    );
    final index = repo.index;
    try {
      GitDebugLog.log('Diff.indexToWorkdir start filePath=$filePath');
      final diff = Diff.indexToWorkdir(repo: repo, index: index);
      try {
        GitDebugLog.log(
          'Diff.indexToWorkdir end filePath=$filePath length=${diff.length}',
        );
        final patch = _patchText(diff, filePath: filePath);
        GitDebugLog.log(
          'GitRepositoryService._trackedUnstagedPatch end '
          'filePath=$filePath bytes=${patch.length}',
        );
        return patch;
      } finally {
        GitDebugLog.log('Diff.indexToWorkdir free filePath=$filePath');
        diff.free();
      }
    } catch (error, stackTrace) {
      GitDebugLog.log(
        'GitRepositoryService._trackedUnstagedPatch failed filePath=$filePath',
        error: error,
        stackTrace: stackTrace,
      );
      return '';
    } finally {
      index.free();
    }
  }

  String _stagedPatch(Repository repo, {String? filePath}) {
    GitDebugLog.log(
      'GitRepositoryService._stagedPatch start filePath=$filePath',
    );
    final index = repo.index;
    try {
      GitDebugLog.log('Diff.treeToIndex start filePath=$filePath');
      final diff = Diff.treeToIndex(
        repo: repo,
        tree: _headTreeOrNull(repo),
        index: index,
      );
      try {
        GitDebugLog.log(
          'Diff.treeToIndex end filePath=$filePath length=${diff.length}',
        );
        final patch = _patchText(diff, filePath: filePath);
        GitDebugLog.log(
          'GitRepositoryService._stagedPatch end '
          'filePath=$filePath bytes=${patch.length}',
        );
        return patch;
      } finally {
        GitDebugLog.log('Diff.treeToIndex free filePath=$filePath');
        diff.free();
      }
    } catch (error, stackTrace) {
      GitDebugLog.log(
        'GitRepositoryService._stagedPatch failed filePath=$filePath',
        error: error,
        stackTrace: stackTrace,
      );
      return '';
    } finally {
      index.free();
    }
  }

  String _patchText(Diff diff, {String? filePath}) {
    if (filePath == null) {
      GitDebugLog.log('Diff.patch start length=${diff.length}');
      final patch = diff.patch.trimRight();
      GitDebugLog.log('Diff.patch end bytes=${patch.length}');
      return patch;
    }

    final wanted = _gitPath(filePath);
    final parts = <String>[];
    for (var index = 0; index < diff.length; index += 1) {
      GitDebugLog.log(
        'Patch.fromDiff start filePath=$filePath index=$index length=${diff.length}',
      );
      final patch = Patch.fromDiff(diff: diff, index: index);
      try {
        GitDebugLog.log('Patch.fromDiff end filePath=$filePath index=$index');
        final delta = patch.delta;
        final paths = {
          _gitPath(delta.oldFile.path),
          _gitPath(delta.newFile.path),
        };
        if (paths.contains(wanted)) {
          final text = patch.text.trimRight();
          if (text.isNotEmpty) parts.add(text);
        }
      } finally {
        patch.free();
      }
    }
    return parts.join('\n');
  }

  Future<String> _untrackedFilePatch(String rootPath, String filePath) async {
    GitDebugLog.log(
      'GitRepositoryService._untrackedFilePatch start path=$filePath',
    );
    final file = File(p.join(rootPath, filePath));
    if (!await file.exists()) {
      GitDebugLog.log(
        'GitRepositoryService._untrackedFilePatch missing path=$filePath',
      );
      return '';
    }

    final normalizedPath = _gitPath(filePath);
    final header = StringBuffer()
      ..writeln('diff --git a/$normalizedPath b/$normalizedPath')
      ..writeln('new file mode 100644')
      ..writeln('index 0000000..0000000')
      ..writeln('--- /dev/null')
      ..writeln('+++ b/$normalizedPath');
    late final int length;
    try {
      length = await file.length();
      GitDebugLog.log(
        'GitRepositoryService._untrackedFilePatch length path=$filePath '
        'bytes=$length',
      );
    } on FileSystemException catch (error, stackTrace) {
      GitDebugLog.log(
        'GitRepositoryService._untrackedFilePatch length failed path=$filePath',
        error: error,
        stackTrace: stackTrace,
      );
      return '';
    }
    if (length > _maxUntrackedPatchBytes) {
      header.writeln('@@ -0,0 +1 @@');
      header.writeln(
        '+[untracked file omitted: $length bytes exceeds preview limit]',
      );
      return header.toString().trimRight();
    }

    late final List<int> bytes;
    try {
      bytes = await file.readAsBytes();
    } on FileSystemException catch (error, stackTrace) {
      GitDebugLog.log(
        'GitRepositoryService._untrackedFilePatch read failed path=$filePath',
        error: error,
        stackTrace: stackTrace,
      );
      return '';
    }
    if (bytes.contains(0)) {
      header.writeln('Binary files /dev/null and b/$normalizedPath differ');
      return header.toString().trimRight();
    }

    final content = utf8
        .decode(bytes, allowMalformed: true)
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final lines = content.isEmpty ? <String>[] : content.split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    header.writeln('@@ -0,0 +1,${lines.length} @@');
    for (final line in lines) {
      header.writeln('+$line');
    }
    return header.toString().trimRight();
  }

  List<GitStatusEntry> _statusEntries(Repository repo) {
    GitDebugLog.log('GitRepositoryService._statusEntries repo.status start');
    final statuses = Map<String, Set<GitStatus>>.fromEntries(
      repo.status.entries.map(
        (entry) => MapEntry(_gitPath(entry.key), entry.value),
      ),
    );
    GitDebugLog.log(
      'GitRepositoryService._statusEntries repo.status end count=${statuses.length}',
    );
    _addUntrackedStatuses(repo, statuses);

    final entries = [
      for (final item in statuses.entries)
        GitStatusEntry(
          path: item.key,
          labels: _statusLabels(item.value),
          isStaged: _isIndexStatus(item.value),
          isUnstaged: _isWorktreeStatus(item.value),
          isConflicted: item.value.contains(GitStatus.conflicted),
          isUntracked:
              item.value.contains(GitStatus.wtNew) &&
              !_isIndexStatus(item.value),
        ),
    ];
    entries.sort((a, b) => a.path.compareTo(b.path));
    return entries;
  }

  void _addUntrackedStatuses(
    Repository repo,
    Map<String, Set<GitStatus>> statuses,
  ) {
    final rootPath = _normalizeWorkdir(repo.workdir);
    if (rootPath.isEmpty) return;

    final stopwatch = Stopwatch()..start();
    GitDebugLog.log(
      'GitRepositoryService._addUntrackedStatuses start root=$rootPath '
      'existing=${statuses.length}',
    );
    final trackedPaths = _trackedIndexPaths(repo);
    final pendingDirectories = <Directory>[Directory(rootPath)];
    var scannedEntries = 0;
    var untrackedEntries = 0;

    while (pendingDirectories.isNotEmpty &&
        scannedEntries < _maxUntrackedScanEntries &&
        untrackedEntries < _maxUntrackedStatusEntries) {
      final directory = pendingDirectories.removeLast();
      final children = _listDirectory(directory);

      for (final entity in children) {
        if (scannedEntries >= _maxUntrackedScanEntries ||
            untrackedEntries >= _maxUntrackedStatusEntries) {
          break;
        }
        scannedEntries++;
        if (GitDebugLog.enabled && scannedEntries % 1000 == 0) {
          GitDebugLog.log(
            'GitRepositoryService._addUntrackedStatuses progress '
            'scanned=$scannedEntries untracked=$untrackedEntries '
            'pendingDirs=${pendingDirectories.length}',
          );
        }

        final relativePath = _gitPath(p.relative(entity.path, from: rootPath));
        if (_isGitInternalPath(relativePath)) continue;

        if (entity is Directory) {
          if (statuses.containsKey(relativePath) ||
              trackedPaths.contains(relativePath)) {
            continue;
          }
          if (_isNestedGitRepository(entity)) {
            if (!_isIgnoredPath(repo, relativePath)) {
              statuses[relativePath] = const {GitStatus.wtNew};
              untrackedEntries++;
            }
            continue;
          }
          if (!_isIgnoredPath(repo, relativePath)) {
            pendingDirectories.add(entity);
          }
          continue;
        }
        if (entity is! File && entity is! Link) continue;
        if (statuses.containsKey(relativePath)) continue;
        if (trackedPaths.contains(relativePath)) continue;

        final fileStatus = _statusFile(repo, relativePath);
        if (fileStatus.contains(GitStatus.wtNew)) {
          statuses[relativePath] = fileStatus;
          untrackedEntries++;
        } else if (fileStatus.isEmpty && !_isIgnoredPath(repo, relativePath)) {
          statuses[relativePath] = const {GitStatus.wtNew};
          untrackedEntries++;
        }
      }
    }
    GitDebugLog.log(
      'GitRepositoryService._addUntrackedStatuses end '
      'elapsed=${stopwatch.elapsedMilliseconds}ms scanned=$scannedEntries '
      'untracked=$untrackedEntries total=${statuses.length} '
      'pendingDirs=${pendingDirectories.length}',
    );
  }

  Set<String> _trackedIndexPaths(Repository repo) {
    final index = repo.index;
    try {
      return {
        for (final entry in index)
          if (!entry.isConflict) _gitPath(entry.path),
      };
    } finally {
      index.free();
    }
  }

  List<FileSystemEntity> _listDirectory(Directory directory) {
    try {
      return directory.listSync(followLinks: false);
    } on FileSystemException catch (error, stackTrace) {
      GitDebugLog.log(
        'GitRepositoryService._listDirectory failed path=${directory.path}',
        error: error,
        stackTrace: stackTrace,
      );
      return const [];
    }
  }

  Set<GitStatus> _statusFile(Repository repo, String relativePath) {
    try {
      return repo.statusFile(relativePath);
    } catch (error, stackTrace) {
      GitDebugLog.log(
        'Repository.statusFile failed path=$relativePath',
        error: error,
        stackTrace: stackTrace,
      );
      return const {};
    }
  }

  bool _isGitInternalPath(String relativePath) {
    return relativePath == '.git' || relativePath.startsWith('.git/');
  }

  bool _isNestedGitRepository(Directory directory) {
    return Directory(p.join(directory.path, '.git')).existsSync() ||
        File(p.join(directory.path, '.git')).existsSync();
  }

  bool _isIgnoredPath(Repository repo, String relativePath) {
    try {
      return Ignore.pathIsIgnored(repo: repo, path: relativePath) ||
          Ignore.pathIsIgnored(repo: repo, path: '$relativePath/');
    } catch (error, stackTrace) {
      GitDebugLog.log(
        'Ignore.pathIsIgnored failed path=$relativePath',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  List<String> _statusLabels(Set<GitStatus> statuses) {
    if (statuses.contains(GitStatus.conflicted)) {
      return const [I18nKey.gitStatusConflicted].map(_tr).toList();
    }
    return [
      if (statuses.contains(GitStatus.indexNew))
        _tr(I18nKey.gitStatusStagedNew),
      if (statuses.contains(GitStatus.indexModified))
        _tr(I18nKey.gitStatusStagedModified),
      if (statuses.contains(GitStatus.indexDeleted))
        _tr(I18nKey.gitStatusStagedDeleted),
      if (statuses.contains(GitStatus.indexRenamed))
        _tr(I18nKey.gitStatusStagedRenamed),
      if (statuses.contains(GitStatus.indexTypeChange))
        _tr(I18nKey.gitStatusStagedTypeChange),
      if (statuses.contains(GitStatus.wtNew)) _tr(I18nKey.gitStatusUntracked),
      if (statuses.contains(GitStatus.wtModified))
        _tr(I18nKey.gitStatusWorktreeModified),
      if (statuses.contains(GitStatus.wtDeleted))
        _tr(I18nKey.gitStatusWorktreeDeleted),
      if (statuses.contains(GitStatus.wtRenamed))
        _tr(I18nKey.gitStatusWorktreeRenamed),
      if (statuses.contains(GitStatus.wtTypeChange))
        _tr(I18nKey.gitStatusWorktreeTypeChange),
      if (statuses.contains(GitStatus.ignored)) _tr(I18nKey.gitStatusIgnored),
    ];
  }

  bool _isIndexStatus(Set<GitStatus> statuses) {
    return statuses.any(
      const {
        GitStatus.indexNew,
        GitStatus.indexModified,
        GitStatus.indexDeleted,
        GitStatus.indexRenamed,
        GitStatus.indexTypeChange,
      }.contains,
    );
  }

  bool _isWorktreeStatus(Set<GitStatus> statuses) {
    return statuses.any(
      const {
        GitStatus.wtNew,
        GitStatus.wtModified,
        GitStatus.wtDeleted,
        GitStatus.wtRenamed,
        GitStatus.wtTypeChange,
      }.contains,
    );
  }

  List<GitBranchInfo> _branches(Repository repo) {
    GitDebugLog.log('GitRepositoryService._branches start');
    return [
      ..._branchInfos(repo, remote: false),
      ..._remoteBranchInfosFromRefs(repo),
    ];
  }

  List<GitBranchInfo> _branchInfos(Repository repo, {required bool remote}) {
    GitDebugLog.log('GitRepositoryService._branchInfos start remote=$remote');
    final branches = remote ? repo.branchesRemote : repo.branchesLocal;
    final infos = [
      for (final branch in branches) _branchInfo(repo, branch, remote: remote),
    ];
    GitDebugLog.log(
      'GitRepositoryService._branchInfos end remote=$remote count=${infos.length}',
    );
    return infos;
  }

  /// 单个分支的 DTO。本地分支附带 upstream 与 ahead/behind 跟踪信息。
  GitBranchInfo _branchInfo(
    Repository repo,
    Branch branch, {
    required bool remote,
  }) {
    final upstream = remote ? '' : _branchUpstream(branch);
    final tracking = remote || upstream.isEmpty
        ? (0, 0, false)
        : _branchTracking(repo, branch);
    return GitBranchInfo(
      name: branch.name,
      targetSha: branch.target.sha,
      isCurrent: !remote && branch.isHead,
      isRemote: remote,
      upstream: upstream,
      ahead: tracking.$1,
      behind: tracking.$2,
      hasUpstream: tracking.$3,
    );
  }

  List<GitBranchInfo> _remoteBranchInfosFromRefs(Repository repo) {
    GitDebugLog.log('GitRepositoryService._remoteBranchInfosFromRefs start');
    final refs = _remoteRefTargets(repo);
    final branches = [
      for (final entry in refs.entries)
        GitBranchInfo(
          name: entry.key,
          targetSha: entry.value,
          isCurrent: false,
          isRemote: true,
          upstream: '',
        ),
    ];
    branches.sort((a, b) => a.name.compareTo(b.name));
    GitDebugLog.log(
      'GitRepositoryService._remoteBranchInfosFromRefs end '
      'count=${branches.length}',
    );
    return branches;
  }

  Map<String, String> _remoteRefTargets(Repository repo) {
    final refs = <String, String>{};
    final gitDir = p.normalize(repo.path);
    _readPackedRemoteRefs(p.join(gitDir, 'packed-refs'), refs);
    _readLooseRemoteRefs(p.join(gitDir, 'refs', 'remotes'), refs);
    return refs;
  }

  void _readPackedRemoteRefs(String packedRefsPath, Map<String, String> refs) {
    final file = File(packedRefsPath);
    if (!file.existsSync()) return;

    try {
      for (final rawLine in file.readAsLinesSync()) {
        final line = rawLine.trim();
        if (line.isEmpty || line.startsWith('#') || line.startsWith('^')) {
          continue;
        }
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length < 2) continue;
        final refName = parts[1];
        if (!refName.startsWith('refs/remotes/')) continue;
        final branchName = refName.substring('refs/remotes/'.length);
        if (_isRemoteHeadRef(branchName)) continue;
        refs[branchName] = parts[0];
      }
    } on FileSystemException catch (error, stackTrace) {
      GitDebugLog.log(
        'GitRepositoryService._readPackedRemoteRefs failed '
        'path=$packedRefsPath',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _readLooseRemoteRefs(String refsRootPath, Map<String, String> refs) {
    final refsRoot = Directory(refsRootPath);
    if (!refsRoot.existsSync()) return;

    try {
      for (final entity in refsRoot.listSync(recursive: true)) {
        if (entity is! File) continue;
        final branchName = _gitPath(
          p.relative(entity.path, from: refsRootPath),
        );
        if (_isRemoteHeadRef(branchName)) continue;

        final value = entity.readAsStringSync().trim();
        if (value.isEmpty || value.startsWith('ref:')) continue;
        refs[branchName] = value;
      }
    } on FileSystemException catch (error, stackTrace) {
      GitDebugLog.log(
        'GitRepositoryService._readLooseRemoteRefs failed path=$refsRootPath',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  bool _isRemoteHeadRef(String branchName) {
    return branchName.contains(' -> ') || branchName.endsWith('/HEAD');
  }

  /// 读取分支的 upstream 短名；没有 upstream 时返回空串。
  String _branchUpstream(Branch branch) {
    try {
      return branch.upstream.shorthand;
    } catch (_) {
      return '';
    }
  }

  /// 计算 [branch] 相对其 upstream 的 ahead/behind。
  ///
  /// 没有 upstream 时返回 `(0, 0, false)`；调用方用第三位区分“同步”和
  /// “无跟踪关系”，避免 UI 把 0/0 当成“已同步”。
  (int, int, bool) _branchTracking(Repository repo, Branch branch) {
    try {
      final upstream = branch.upstream;
      final values = repo.aheadBehind(
        local: branch.target,
        upstream: upstream.target,
      );
      return (values[0], values[1], true);
    } catch (_) {
      return (0, 0, false);
    }
  }

  /// 判断 [target] 是否已经并入 [head]（等价 `git branch --merged`）。
  bool _isMergedInto(Repository repo, Commit head, Oid target) {
    try {
      final values = repo.aheadBehind(local: target, upstream: head.oid);
      // 第 0 位是 target 领先 head 的提交数：为 0 说明 target 已被 head 包含。
      return values[0] == 0;
    } catch (_) {
      // 无法判定时按“未合并”处理，让用户显式选择强制删除，避免静默丢提交。
      return false;
    }
  }

  /// 首次推送后把本地分支的 upstream 指向 `<remote>/<branch>`。
  ///
  /// libgit2 的 push 不会像 `git push -u` 那样写配置，需要显式补上；已有
  /// upstream（用户可能指向别的远端）时不覆盖。
  void _ensureBranchUpstream(
    Repository repo,
    String branchName,
    String remoteName,
  ) {
    try {
      final branch = Branch.lookup(repo: repo, name: branchName);
      try {
        String existing = '';
        try {
          existing = branch.upstream.shorthand;
        } catch (_) {
          existing = '';
        }
        if (existing.isNotEmpty) return;
        final trackingRef = '$remoteName/$branchName';
        Reference.lookup(repo: repo, name: 'refs/remotes/$trackingRef').free();
        branch.setUpstream(trackingRef);
      } finally {
        branch.free();
      }
    } catch (error, stackTrace) {
      GitDebugLog.log(
        'GitRepositoryService._ensureBranchUpstream skipped '
        'branch=$branchName remote=$remoteName',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  bool _branchExists(Repository repo, String name) {
    try {
      Branch.lookup(repo: repo, name: name).free();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 找出本地分支 [branchName] 在某个 remote 上的同名分支。
  ///
  /// 返回 `(remoteName, remoteRefName)`，找不到时返回 null。优先匹配
  /// 本地分支已配置的 upstream remote，其次遍历全部 remote。
  (String, String)? _remoteBranchTarget(Repository repo, String branchName) {
    final candidates = <String>[];
    try {
      final branch = Branch.lookup(repo: repo, name: branchName);
      try {
        final remoteName = branch.upstreamRemote;
        if (remoteName.isNotEmpty) candidates.add(remoteName);
      } catch (_) {
        // 分支没有 upstream，继续遍历全部 remote。
      } finally {
        branch.free();
      }
    } catch (_) {
      // 分支不存在（例如只删除远端分支的场景），直接遍历全部 remote。
    }
    for (final name in repo.remotes) {
      if (!candidates.contains(name)) candidates.add(name);
    }
    for (final remoteName in candidates) {
      final refName = '$remoteName/$branchName';
      try {
        Reference.lookup(repo: repo, name: 'refs/remotes/$refName').free();
        return (remoteName, refName);
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  /// 删除远端分支后清理对应的 remote-tracking ref。
  ///
  /// libgit2 的 push 删除不会自动移除 `refs/remotes/<remote>/<branch>`，
  /// 不清理的话 UI 仍会显示一个已经不存在的远端分支。
  void _pruneRemoteTrackingBranch(
    Repository repo,
    String remoteName,
    String branchName,
  ) {
    try {
      Reference.delete(
        repo: repo,
        name: 'refs/remotes/$remoteName/$branchName',
      );
    } catch (error, stackTrace) {
      GitDebugLog.log(
        'GitRepositoryService._pruneRemoteTrackingBranch failed '
        'remote=$remoteName branch=$branchName',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  List<GitRemoteInfo> _remotes(Repository repo) {
    GitDebugLog.log('GitRepositoryService._remotes start');
    final remotes = <GitRemoteInfo>[];
    for (final name in repo.remotes) {
      GitDebugLog.log('Remote.lookup start name=$name');
      final remote = Remote.lookup(repo: repo, name: name);
      try {
        GitDebugLog.log('Remote.lookup end name=$name url=${remote.url}');
        remotes.add(
          GitRemoteInfo(
            name: remote.name,
            url: remote.url,
            pushUrl: remote.pushUrl.isEmpty ? remote.url : remote.pushUrl,
            fetchRefspecs: remote.fetchRefspecs,
            pushRefspecs: remote.pushRefspecs,
          ),
        );
      } finally {
        GitDebugLog.log('Remote.free name=$name');
        remote.free();
      }
    }
    GitDebugLog.log(
      'GitRepositoryService._remotes end count=${remotes.length}',
    );
    return remotes;
  }

  List<GitStashInfo> _stashes(Repository repo) {
    GitDebugLog.log('GitRepositoryService._stashes start');
    final stashes = [
      for (final stash in repo.stashes)
        GitStashInfo(
          index: stash.index,
          sha: stash.oid.sha,
          message: stash.message,
        ),
    ];
    GitDebugLog.log(
      'GitRepositoryService._stashes end count=${stashes.length}',
    );
    return stashes;
  }

  List<GitTagInfo> _tags(Repository repo) {
    GitDebugLog.log('GitRepositoryService._tagsFromRefs start');
    final refs = _tagRefTargets(repo);
    final tags = [
      for (final entry in refs.entries) _tagInfo(repo, entry.key, entry.value),
    ];
    tags.sort((a, b) => a.name.compareTo(b.name));
    GitDebugLog.log('GitRepositoryService._tags end count=${tags.length}');
    return tags;
  }

  /// 解析单个 tag：区分 lightweight/annotated，并取 annotated 的消息首行。
  ///
  /// ref 直接指向 commit 的是 lightweight tag；指向 tag 对象的是 annotated。
  /// 解析失败（例如 tag 指向 tree/blob）时退化成 lightweight，不影响列表展示。
  GitTagInfo _tagInfo(Repository repo, String name, String targetSha) {
    try {
      final object = RevParse.single(repo: repo, spec: 'refs/tags/$name');
      if (object is Tag) {
        try {
          return GitTagInfo(
            name: name,
            targetSha: targetSha,
            isAnnotated: true,
            message: _firstLine(object.message),
          );
        } finally {
          object.free();
        }
      }
      _freeGitObject(object);
    } catch (error, stackTrace) {
      GitDebugLog.log(
        'GitRepositoryService._tagInfo failed name=$name',
        error: error,
        stackTrace: stackTrace,
      );
    }
    return GitTagInfo(name: name, targetSha: targetSha);
  }

  /// 释放 [RevParse.single] 返回的任意 Git 对象。
  ///
  /// 它返回 `Object`（Commit/Tree/Blob/Tag），静态类型上没有 `free()`；
  /// 这里按运行时类型分派，避免每处调用都写同样的 switch。
  void _freeGitObject(Object object) {
    switch (object) {
      case Commit(:final free):
        free();
      case Tree(:final free):
        free();
      case Blob(:final free):
        free();
      case Tag(:final free):
        free();
      default:
        break;
    }
  }

  String _firstLine(String text) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final index = normalized.indexOf('\n');
    return (index == -1 ? normalized : normalized.substring(0, index)).trim();
  }

  Map<String, String> _tagRefTargets(Repository repo) {
    final refs = <String, String>{};
    final gitDir = p.normalize(repo.path);
    _readPackedTagRefs(p.join(gitDir, 'packed-refs'), refs);
    _readLooseTagRefs(p.join(gitDir, 'refs', 'tags'), refs);
    return refs;
  }

  void _readPackedTagRefs(String packedRefsPath, Map<String, String> refs) {
    final file = File(packedRefsPath);
    if (!file.existsSync()) return;

    try {
      for (final rawLine in file.readAsLinesSync()) {
        final line = rawLine.trim();
        if (line.isEmpty || line.startsWith('#') || line.startsWith('^')) {
          continue;
        }
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length < 2) continue;
        final refName = parts[1];
        if (!refName.startsWith('refs/tags/')) continue;
        refs[refName.substring('refs/tags/'.length)] = parts[0];
      }
    } on FileSystemException catch (error, stackTrace) {
      GitDebugLog.log(
        'GitRepositoryService._readPackedTagRefs failed path=$packedRefsPath',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _readLooseTagRefs(String refsRootPath, Map<String, String> refs) {
    final refsRoot = Directory(refsRootPath);
    if (!refsRoot.existsSync()) return;

    try {
      for (final entity in refsRoot.listSync(recursive: true)) {
        if (entity is! File) continue;
        final name = _gitPath(p.relative(entity.path, from: refsRootPath));
        final value = entity.readAsStringSync().trim();
        if (value.isEmpty || value.startsWith('ref:')) continue;
        refs[name] = value;
      }
    } on FileSystemException catch (error, stackTrace) {
      GitDebugLog.log(
        'GitRepositoryService._readLooseTagRefs failed path=$refsRootPath',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  List<GitSubmoduleInfo> _submodules(Repository repo) {
    GitDebugLog.log('GitRepositoryService._submodules start');
    final submodules = <GitSubmoduleInfo>[];
    for (final path in repo.submodules) {
      GitDebugLog.log('Submodule.lookup start path=$path');
      final submodule = Submodule.lookup(repo: repo, name: path);
      try {
        GitDebugLog.log(
          'Submodule.lookup end path=$path name=${submodule.name}',
        );
        submodules.add(
          GitSubmoduleInfo(
            name: submodule.name,
            path: submodule.path,
            url: submodule.url,
            branch: submodule.branch,
            statusLabels: [
              for (final status in submodule.status()) status.name,
            ],
          ),
        );
      } finally {
        GitDebugLog.log('Submodule.free path=$path');
        submodule.free();
      }
    }
    GitDebugLog.log(
      'GitRepositoryService._submodules end count=${submodules.length}',
    );
    return submodules;
  }

  List<GitWorktreeInfo> _worktrees(Repository repo) {
    GitDebugLog.log('GitRepositoryService._worktrees start');
    final rootPath = _normalizeWorkdir(repo.workdir);
    final worktrees = <GitWorktreeInfo>[];
    for (final name in repo.worktrees) {
      GitDebugLog.log('Worktree.lookup start name=$name');
      final worktree = Worktree.lookup(repo: repo, name: name);
      try {
        GitDebugLog.log('Worktree.lookup end name=$name path=${worktree.path}');
        final worktreePath = p.normalize(worktree.path);
        if (p.equals(worktreePath, rootPath)) continue;
        worktrees.add(
          GitWorktreeInfo(
            name: worktree.name,
            path: worktree.path,
            isLocked: worktree.isLocked,
            isPrunable: worktree.isPrunable,
            isValid: worktree.isValid,
          ),
        );
      } finally {
        GitDebugLog.log('Worktree.free name=$name');
        worktree.free();
      }
    }
    GitDebugLog.log(
      'GitRepositoryService._worktrees end count=${worktrees.length}',
    );
    return worktrees;
  }

  List<GitCommitInfo> _commits(
    Repository repo, {
    int limit = 80,
    String? pathspec,
  }) {
    GitDebugLog.log(
      'GitRepositoryService._commits start limit=$limit pathspec=$pathspec',
    );
    if (_isEmpty(repo)) return const [];
    final walker = RevWalk(repo);
    try {
      GitDebugLog.log('RevWalk.sorting start pathspec=$pathspec');
      walker.sorting(const {GitSort.topological, GitSort.time});
      GitDebugLog.log('RevWalk.pushHead start pathspec=$pathspec');
      walker.pushHead();
      final walkLimit = pathspec == null ? limit : 2000;
      final commits = <GitCommitInfo>[];
      for (final commit in walker.walk(limit: walkLimit)) {
        if (commits.length % 20 == 0) {
          GitDebugLog.log(
            'RevWalk progress pathspec=$pathspec count=${commits.length} '
            'oid=${commit.oid.sha}',
          );
        }
        if (pathspec != null && !_commitTouchesPath(repo, commit, pathspec)) {
          continue;
        }
        commits.add(_commitInfo(commit));
        if (commits.length >= limit) break;
      }
      GitDebugLog.log(
        'GitRepositoryService._commits end count=${commits.length} '
        'pathspec=$pathspec',
      );
      return commits;
    } catch (error, stackTrace) {
      GitDebugLog.log(
        'GitRepositoryService._commits failed pathspec=$pathspec',
        error: error,
        stackTrace: stackTrace,
      );
      return const [];
    } finally {
      GitDebugLog.log('RevWalk.free pathspec=$pathspec');
      walker.free();
    }
  }

  GitCommitInfo _commitInfo(Commit commit) {
    return GitCommitInfo(
      sha: commit.oid.sha,
      shortSha: commit.oid.toStrN(7),
      summary: commit.summary,
      author: commit.author.name,
      email: commit.author.email,
      time: DateTime.fromMillisecondsSinceEpoch(
        commit.time * 1000,
        isUtc: true,
      ).toLocal(),
      parentShas: [for (final parent in commit.parents) parent.sha],
    );
  }

  bool _commitTouchesPath(Repository repo, Commit commit, String pathspec) {
    final path = _gitPath(pathspec);
    try {
      if (commit.parents.isEmpty) {
        commit.tree[path];
        return true;
      }
      for (var i = 0; i < commit.parents.length; i += 1) {
        final parent = commit.parent(i);
        final diff = Diff.treeToTree(
          repo: repo,
          oldTree: parent.tree,
          newTree: commit.tree,
        );
        try {
          for (final delta in diff.deltas) {
            if (_gitPath(delta.oldFile.path) == path ||
                _gitPath(delta.newFile.path) == path) {
              return true;
            }
          }
        } finally {
          diff.free();
        }
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  Future<List<GitConflictInfo>> _conflicts(
    Repository repo,
    List<GitStatusEntry> entries,
  ) async {
    final index = repo.index;
    try {
      return [
        for (final entry in entries)
          if (entry.isConflicted)
            _conflictInfo(repo, index.conflict(_gitPath(entry.path))),
      ];
    } finally {
      index.free();
    }
  }

  GitConflictInfo _conflictInfo(Repository repo, ConflictEntry conflict) {
    final path =
        conflict.our?.path ??
        conflict.their?.path ??
        conflict.ancestor?.path ??
        '';
    return GitConflictInfo(
      path: path,
      ancestorPath: conflict.ancestor?.path ?? path,
      oursPath: conflict.our?.path ?? path,
      theirsPath: conflict.their?.path ?? path,
      basePreview: _indexEntryPreview(repo, conflict.ancestor),
      oursPreview: _indexEntryPreview(repo, conflict.our),
      theirsPreview: _indexEntryPreview(repo, conflict.their),
      mergedPreview: _filePreview(_normalizeWorkdir(repo.workdir), path),
    );
  }

  String _indexEntryPreview(Repository repo, IndexEntry? entry) {
    if (entry == null) return '';
    try {
      final blob = Blob.lookup(repo: repo, oid: entry.oid);
      try {
        return blob.isBinary ? '[Binary file]' : blob.content;
      } finally {
        blob.free();
      }
    } catch (_) {
      return '';
    }
  }

  String _filePreview(String rootPath, String filePath) {
    final file = File(p.join(rootPath, filePath));
    if (!file.existsSync()) return '';
    try {
      return file.readAsStringSync();
    } on FormatException {
      return '[Binary file]';
    }
  }

  String _repositoryStateLabel(Repository repo) {
    return switch (repo.state) {
      GitRepositoryState.none => _tr(I18nKey.gitStateIdle),
      GitRepositoryState.merge => _tr(I18nKey.gitStateMerging),
      GitRepositoryState.cherrypick || GitRepositoryState.cherrypickSequence =>
        _tr(I18nKey.gitStateCherryPicking),
      GitRepositoryState.rebase ||
      GitRepositoryState.rebaseInteractive ||
      GitRepositoryState.rebaseMerge ||
      GitRepositoryState.applyMailboxOrRebase => _tr(I18nKey.gitStateRebasing),
      GitRepositoryState.revert ||
      GitRepositoryState.revertSequence => _tr(I18nKey.gitStateReverting),
      GitRepositoryState.bisect => _tr(I18nKey.gitStateBisecting),
      GitRepositoryState.applyMailbox => _tr(I18nKey.gitStateApplyMailbox),
    };
  }

  String? _configValue(Repository repo, String key) {
    try {
      final value = repo.config.getString(key).trim();
      return value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  void _checkoutBranch(
    Repository repo,
    String name, {
    required bool remote,
    Set<GitCheckout> strategy = const {
      GitCheckout.safe,
      GitCheckout.recreateMissing,
    },
  }) {
    final branchName = name.trim();
    if (branchName.isEmpty) throw ArgumentError('分支名称不能为空。');

    final localName = remote
        ? _localBranchNameForRemote(branchName)
        : branchName;
    if (remote) _ensureLocalTrackingBranch(repo, branchName, localName);

    final refName = _localRefName(localName);
    final targetCommit = _commitFromSpec(repo, refName);
    if (strategy.contains(GitCheckout.safe)) {
      final blockedPaths = _checkoutBlockedPaths(repo, targetCommit);
      if (blockedPaths.isNotEmpty) {
        throw GitCheckoutBlockedException(
          message: _tr(I18nKey.gitErrorCheckoutBlockedLocalChanges),
          paths: blockedPaths,
        );
      }
    }

    try {
      Checkout.reference(repo: repo, name: refName, strategy: strategy);
      repo.setHead(refName);
    } catch (error) {
      throw GitCheckoutBlockedException(
        message: error.toString(),
        paths: _checkoutBlockedPaths(repo, targetCommit),
      );
    }
  }

  void _ensureLocalTrackingBranch(
    Repository repo,
    String remoteBranchName,
    String localName,
  ) {
    try {
      Branch.lookup(repo: repo, name: localName);
      return;
    } catch (_) {
      // Create the branch below.
    }

    final remoteRef = Reference.lookup(
      repo: repo,
      name: 'refs/remotes/$remoteBranchName',
    );
    final target = Commit.lookup(repo: repo, oid: remoteRef.target);
    final localBranch = Branch.create(
      repo: repo,
      name: localName,
      target: target,
    );
    try {
      localBranch.setUpstream(remoteBranchName);
    } catch (error, stackTrace) {
      GitDebugLog.log(
        'GitRepositoryService._ensureLocalTrackingBranch setUpstream failed '
        'remote=$remoteBranchName local=$localName',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  List<String> _checkoutBlockedPaths(Repository repo, Commit targetCommit) {
    final dirtyEntries = _statusEntries(
      repo,
    ).where((entry) => entry.isUnstaged || entry.isUntracked).toList();
    if (dirtyEntries.isEmpty) return const [];

    final targetChangedPaths = _changedPaths(
      repo,
      oldTree: _headTreeOrNull(repo),
      newTree: targetCommit.tree,
    );
    return [
      for (final entry in dirtyEntries)
        if ((entry.isUntracked &&
                _treeContains(targetCommit.tree, entry.path)) ||
            (!entry.isUntracked &&
                targetChangedPaths.contains(_gitPath(entry.path))))
          entry.path,
    ];
  }

  Set<String> _changedPaths(
    Repository repo, {
    Tree? oldTree,
    required Tree newTree,
  }) {
    final diff = Diff.treeToTree(
      repo: repo,
      oldTree: oldTree,
      newTree: newTree,
    );
    try {
      return {
        for (final delta in diff.deltas) ...[
          _gitPath(delta.oldFile.path),
          _gitPath(delta.newFile.path),
        ],
      }..remove('');
    } finally {
      diff.free();
    }
  }

  bool _treeContains(Tree tree, String filePath) {
    try {
      tree[_gitPath(filePath)];
      return true;
    } catch (_) {
      return false;
    }
  }

  void _merge(Repository repo, String targetSpec) {
    final annotated = AnnotatedCommit.fromRevSpec(repo: repo, spec: targetSpec);
    try {
      final analysis = Merge.analysis(repo: repo, theirHead: annotated.oid);
      if (analysis.result.contains(GitMergeAnalysis.upToDate)) return;
      if (analysis.result.contains(GitMergeAnalysis.fastForward) ||
          analysis.result.contains(GitMergeAnalysis.unborn)) {
        _fastForward(repo, annotated.oid);
        return;
      }
      Merge.commit(repo: repo, commit: annotated);
    } finally {
      annotated.free();
    }
  }

  void _fastForward(Repository repo, Oid target) {
    if (repo.isHeadDetached) {
      repo.setHead(target);
      Checkout.head(repo: repo);
      return;
    }
    final head = repo.head;
    Reference.setTarget(
      repo: repo,
      name: head.name,
      target: target,
      logMessage: 'PyriteIDE fast-forward',
    );
    repo.setHead(head.name);
    Checkout.head(repo: repo);
  }

  void _advanceRebase(Repository repo, Rebase rebase, GitCommitInput input) {
    while (true) {
      try {
        rebase.next();
      } catch (_) {
        rebase.finish();
        return;
      }
      if (repo.index.hasConflicts) return;
      rebase.commit(committer: _signature(input));
    }
  }

  Commit _headCommit(Repository repo) {
    final commit = _headCommitOrNull(repo);
    if (commit == null) throw StateError('当前仓库还没有提交。');
    return commit;
  }

  Commit? _headCommitOrNull(Repository repo) {
    try {
      return repo.head.peel(GitObject.commit) as Commit;
    } catch (_) {
      return null;
    }
  }

  Oid? _headOidOrNull(Repository repo) {
    try {
      return repo.head.target;
    } catch (_) {
      return null;
    }
  }

  Tree? _headTreeOrNull(Repository repo) {
    try {
      return _headCommit(repo).tree;
    } catch (_) {
      return null;
    }
  }

  List<Commit> _commitParents(Repository repo) {
    final parents = <Commit>[];
    final head = _headCommitOrNull(repo);
    if (head != null) parents.add(head);
    for (final sha in repo.mergeHeadOids) {
      try {
        parents.add(Commit.lookup(repo: repo, oid: repo[sha]));
      } catch (_) {
        // Ignore stale merge heads.
      }
    }
    return parents;
  }

  Commit _commitFromSpec(Repository repo, String spec) {
    final object = _objectFromSpec(repo, spec);
    if (object is Commit) return object;
    if (object is Tag) return object.peel(GitObject.commit) as Commit;
    throw ArgumentError('目标不是提交：$spec');
  }

  Object _objectFromSpec(Repository repo, String spec) {
    return RevParse.single(repo: repo, spec: spec);
  }

  GitObject _objectType(Object object) {
    return switch (object) {
      Commit() => GitObject.commit,
      Tree() => GitObject.tree,
      Blob() => GitObject.blob,
      Tag() => GitObject.tag,
      _ => GitObject.any,
    };
  }

  String? _upstreamSpec(Repository repo, String branchName) {
    try {
      final branch = Branch.lookup(repo: repo, name: branchName);
      return branch.upstream.shorthand;
    } catch (_) {
      return null;
    }
  }

  Signature _signature(GitCommitInput input) {
    final now = DateTime.now();
    return Signature.create(
      name: _authorName(input),
      email: _authorEmail(input),
      time: now.millisecondsSinceEpoch ~/ 1000,
      offset: now.timeZoneOffset.inMinutes,
    );
  }

  Signature _defaultSignature(Repository repo) {
    try {
      return repo.defaultSignature;
    } catch (_) {
      return Signature.create(
        name: 'Pyrite User',
        email: 'pyrite@example.local',
      );
    }
  }

  String _authorName(GitCommitInput input) {
    return input.authorName.trim().isEmpty
        ? 'Pyrite User'
        : input.authorName.trim();
  }

  String _authorEmail(GitCommitInput input) {
    return input.authorEmail.trim().isEmpty
        ? 'pyrite@example.local'
        : input.authorEmail.trim();
  }

  Callbacks _callbacks(GitCredentialDraft draft) {
    return Callbacks(credentials: _credentials(draft));
  }

  Credentials? _credentials(GitCredentialDraft draft) {
    return switch (draft.mode) {
      GitCredentialMode.httpsToken =>
        draft.token.trim().isEmpty
            ? null
            : UserPass(
                username: draft.username.trim().isEmpty
                    ? 'oauth2'
                    : draft.username.trim(),
                password: draft.token.trim(),
              ),
      GitCredentialMode.sshAgent => KeypairFromAgent(
        draft.username.trim().isEmpty ? 'git' : draft.username.trim(),
      ),
      GitCredentialMode.sshKey =>
        draft.privateKeyPath.trim().isEmpty
            ? null
            : Keypair(
                username: draft.username.trim().isEmpty
                    ? 'git'
                    : draft.username.trim(),
                pubKey: draft.publicKeyPath.trim(),
                privateKey: draft.privateKeyPath.trim(),
                passPhrase: draft.passphrase,
              ),
      GitCredentialMode.none => null,
    };
  }

  DateTime? _signatureTime(Signature? signature) {
    if (signature == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      signature.time * 1000,
      isUtc: true,
    ).toLocal();
  }

  Iterable<String> _cleanPaths(Iterable<String> paths) {
    return paths.map((path) => path.trim()).where((path) => path.isNotEmpty);
  }

  String _localBranchNameForRemote(String remoteBranchName) {
    if (remoteBranchName.contains(' -> ') ||
        remoteBranchName.endsWith('/HEAD')) {
      throw ArgumentError('不能切换到远端 HEAD 指针。');
    }
    final separator = remoteBranchName.indexOf('/');
    if (separator == -1 || separator == remoteBranchName.length - 1) {
      return remoteBranchName;
    }
    return remoteBranchName.substring(separator + 1);
  }

  String _localRefName(String branchName) {
    return branchName.startsWith('refs/')
        ? branchName
        : 'refs/heads/$branchName';
  }

  String _gitPath(String value) => p.normalize(value).replaceAll('\\', '/');

  String _normalizeWorkdir(String workdir) {
    final normalized = p.normalize(workdir);
    if (normalized.endsWith('/') || normalized.endsWith('\\')) {
      return p.normalize(p.dirname(normalized));
    }
    return normalized;
  }

  Future<void> _deleteUntrackedPath(
    String rootPath,
    String relativePath,
  ) async {
    final target = p.normalize(p.absolute(p.join(rootPath, relativePath)));
    final root = p.normalize(p.absolute(rootPath));
    if (!p.equals(root, target) && !p.isWithin(root, target)) {
      throw ArgumentError('不能删除仓库外路径：$relativePath');
    }

    final type = FileSystemEntity.typeSync(target);
    if (type == FileSystemEntityType.directory) {
      await Directory(target).delete(recursive: true);
    } else if (type == FileSystemEntityType.file ||
        type == FileSystemEntityType.link) {
      await File(target).delete();
    }
  }

  T? _tryValue<T>(T Function() read) {
    try {
      return read();
    } catch (_) {
      return null;
    }
  }
}

class GitCheckoutBlockedException implements Exception {
  const GitCheckoutBlockedException({
    required this.message,
    required this.paths,
  });

  final String message;
  final List<String> paths;

  @override
  String toString() => message;
}

/// 后台 isolate 中抛出、无法对应到具体 Dart 异常类型的操作失败。
///
/// 保留 message 让 UI 能直接展示；用专门的类型包裹，是为了避免把 libgit2 的
/// 原生错误对象跨 isolate 复制（它们持有原生指针，不能发送）。
class GitRepositoryFailure implements Exception {
  const GitRepositoryFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// [GitRepositoryFailure] 的 Error 版本，对应工作 isolate 中抛出的 Error。
class GitRepositoryFailureError extends Error {
  GitRepositoryFailureError(this.message);

  final String message;

  @override
  String toString() => message;
}
