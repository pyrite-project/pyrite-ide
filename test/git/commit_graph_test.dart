import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/git/git_models.dart';
import 'package:pyrite_ide/pages/git/main.dart';

void main() {
  test('commit graph ignores parents that are not below the current row', () {
    final rows = buildGitCommitGraphRowsForTesting([
      _commit('parent'),
      _commit('child', ['parent']),
    ]);

    expect(rows[1].parentEdges, isEmpty);
    expect(rows[1].passThroughEdges, isEmpty);
    expect(rows[1].laneCount, 1);
  });

  test('commit graph does not duplicate repeated parent lanes', () {
    final rows = buildGitCommitGraphRowsForTesting([
      _commit('merge', ['left', 'left', 'right']),
      _commit('left'),
      _commit('right'),
    ]);

    expect(rows.first.laneCount, 2);
    expect(rows.first.parentEdges, const [
      GitCommitGraphDebugEdge(fromLane: 0, toLane: 0),
      GitCommitGraphDebugEdge(fromLane: 0, toLane: 1, colorIndex: 1),
    ]);
  });

  test('commit graph keeps first-parent history blue after branch joins', () {
    final rows = buildGitCommitGraphRowsForTesting([
      _commit('merge', ['left', 'right']),
      _commit('right', ['base']),
      _commit('left', ['base']),
      _commit('base'),
    ]);

    expect(rows[2].parentEdges, const [
      GitCommitGraphDebugEdge(fromLane: 0, toLane: 0),
    ]);
    expect(rows[2].passThroughEdges, const [
      GitCommitGraphDebugEdge(fromLane: 1, toLane: 0, colorIndex: 1),
    ]);
    expect(rows[3].nodeLane, 0);
    expect(rows[3].nodeColorIndex, 0);
    expect(rows[3].laneCount, 1);
  });

  test('commit graph keeps the shared pre-branch history on main color', () {
    final rows = buildGitCommitGraphRowsForTesting([
      _commit('merge', ['left', 'right']),
      _commit('left', ['base']),
      _commit('right', ['base']),
      _commit('base'),
    ]);

    expect(rows[1].nodeColorIndex, 0);
    expect(rows[1].parentEdges, const [
      GitCommitGraphDebugEdge(fromLane: 0, toLane: 0),
    ]);
    expect(rows[2].nodeColorIndex, 1);
    expect(rows[2].parentEdges, const [
      GitCommitGraphDebugEdge(fromLane: 1, toLane: 0, colorIndex: 1),
    ]);
    expect(rows[3].nodeLane, 0);
    expect(rows[3].nodeColorIndex, 0);
  });
}

GitCommitInfo _commit(String sha, [List<String> parents = const []]) {
  return GitCommitInfo(
    sha: sha,
    shortSha: sha,
    summary: sha,
    author: 'Test Author',
    email: 'test@example.local',
    time: DateTime.utc(2024),
    parentShas: parents,
  );
}
