/// Web stub of the git repository service.
///
/// A browser build has no libgit2 and (per product decision) no Git support,
/// so the Git page surfaces its "no repository" empty state. Mutation
/// requests fail with a descriptive [StateError] instead of crashing.
library;

import 'package:pyrite_ide/core/services/git/git_models.dart';

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

Never _unavailable([String? operation]) => throw StateError(
      'Git ${operation == null ? '' : '$operation '}' 'is not available in the '
      'web build.',
    );

class GitRepositoryService {
  GitRepositoryService({Duration commandTimeout = const Duration(seconds: 20)});

  Future<GitRepositorySnapshot?> loadSnapshot(String? workspacePath) async {
    if (workspacePath == null || workspacePath.isEmpty) return null;
    return const GitRepositorySnapshot(
      rootPath: '',
      gitDir: '',
      branchLabel: 'Git',
      stateLabel: '空闲',
      isDetached: false,
      isEmpty: true,
      authorName: '',
      authorEmail: '',
      ahead: 0,
      behind: 0,
      statusEntries: [],
      branches: [],
      remotes: [],
      stashes: [],
      tags: [],
      submodules: [],
      worktrees: [],
      commits: [],
      conflicts: [],
      stagedPatch: '',
      unstagedPatch: '',
    );
  }

  Future<String?> discoverRoot(String? workspacePath) async => null;

  Future<void> initRepository(String workspacePath) => _unavailable('init');

  Future<String> diffForPath(
    String rootPath,
    String filePath, {
    bool staged = false,
  }) =>
      _unavailable('diff');

  Future<String> diffForEntry(
    String rootPath,
    GitStatusEntry entry, {
    bool staged = false,
  }) =>
      _unavailable('diff');

  Future<List<GitCommitInfo>> fileHistory(
    String rootPath,
    String filePath,
  ) async =>
      const [];

  Future<List<GitBlameLine>> blame(String rootPath, String filePath) async =>
      const [];

  Future<void> stage(String rootPath, Iterable<String> paths) =>
      _unavailable('stage');

  Future<void> unstage(String rootPath, Iterable<String> paths) =>
      _unavailable('unstage');

  Future<void> discardChanges(String rootPath, GitStatusEntry entry) =>
      _unavailable('discard');

  Future<void> commit(String rootPath, GitCommitInput input) =>
      _unavailable('commit');

  Future<void> createBranch(String rootPath, String name) =>
      _unavailable('branch');

  Future<void> checkoutBranch(
    String rootPath,
    String name, {
    bool remote = false,
  }) =>
      _unavailable('checkout');

  Future<void> checkoutBranchWithStash(
    String rootPath,
    String name, {
    bool remote = false,
  }) =>
      _unavailable('checkout');

  Future<void> checkoutBranchWithMerge(
    String rootPath,
    String name, {
    bool remote = false,
  }) =>
      _unavailable('checkout');

  Future<void> forceCheckoutBranch(
    String rootPath,
    String name, {
    bool remote = false,
  }) =>
      _unavailable('checkout');

  Future<void> discardTrackedPathsAndCheckoutBranch(
    String rootPath,
    String name,
    Iterable<String> paths, {
    bool remote = false,
  }) =>
      _unavailable('checkout');

  Future<void> stash(
    String rootPath,
    GitCommitInput input, {
    bool includeUntracked = true,
  }) =>
      _unavailable('stash');

  Future<void> applyStash(String rootPath, int index, {bool pop = false}) =>
      _unavailable('stash');

  Future<void> dropStash(String rootPath, int index) => _unavailable('stash');

  Future<String> fetch(
    String rootPath,
    String remoteName,
    GitCredentialDraft draft,
  ) =>
      _unavailable('fetch');

  Future<String> push(
    String rootPath,
    String remoteName,
    GitCredentialDraft draft,
  ) =>
      _unavailable('push');

  Future<String> pull(
    String rootPath,
    String remoteName,
    GitCredentialDraft draft,
  ) =>
      _unavailable('pull');

  Future<void> addRemote(String rootPath, String name, String url) =>
      _unavailable('remote');

  Future<void> merge(String rootPath, String targetSpec) =>
      _unavailable('merge');

  Future<void> rebase(String rootPath, String targetSpec, GitCommitInput input) =>
      _unavailable('rebase');

  Future<void> continueRebase(String rootPath, GitCommitInput input) =>
      _unavailable('rebase');

  Future<void> abortRebase(String rootPath) => _unavailable('rebase');

  Future<void> cherryPick(String rootPath, String targetSpec) =>
      _unavailable('cherry-pick');

  Future<void> markResolved(String rootPath, String filePath) =>
      _unavailable('resolve');

  Future<void> acceptConflictSide(
    String rootPath,
    String filePath,
    GitConflictSide side,
  ) =>
      _unavailable('resolve');

  Future<void> createTag(String rootPath, String name, {String? targetSpec}) =>
      _unavailable('tag');

  Future<void> createWorktree(String rootPath, String name, String path) =>
      _unavailable('worktree');

  Future<void> pruneWorktree(String rootPath, String name) =>
      _unavailable('worktree');

  Future<void> updateSubmodule(
    String rootPath,
    String name,
    GitCredentialDraft draft,
  ) =>
      _unavailable('submodule');

  Future<void> writeCommitGraph(String rootPath) => _unavailable('commit-graph');
}
