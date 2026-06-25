import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/git/git_models.dart';

void main() {
  test('GitViewState can explicitly clear repository snapshot', () {
    final state = GitViewState(snapshot: _snapshot());

    final cleared = state.copyWith(clearSnapshot: true);

    expect(cleared.snapshot, isNull);
  });
}

GitRepositorySnapshot _snapshot() {
  return const GitRepositorySnapshot(
    rootPath: '/repo',
    gitDir: '/repo/.git',
    branchLabel: 'main',
    stateLabel: '空闲',
    isDetached: false,
    isEmpty: false,
    authorName: 'Pyrite Test',
    authorEmail: 'pyrite-test@example.local',
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
