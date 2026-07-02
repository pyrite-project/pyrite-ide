class GitDiffDisplay {
  const GitDiffDisplay({
    required this.text,
    required this.addedRanges,
    required this.removedRanges,
  });

  final String text;
  final List<(int startLine, int endLine)> addedRanges;
  final List<({int afterLine, String content})> removedRanges;
}

GitDiffDisplay buildGitDiffDisplay(String patch) {
  final normalizedPatch = patch
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .trimRight();
  if (normalizedPatch.isEmpty) {
    return const GitDiffDisplay(
      text: 'No diff.',
      addedRanges: [],
      removedRanges: [],
    );
  }

  final visibleLines = <String>[];
  final addedRanges = <(int startLine, int endLine)>[];
  final removedRanges = <({int afterLine, String content})>[];
  final pendingRemovedLines = <String>[];
  var pendingRemovedAfterLine = -1;
  var insideHunk = false;
  var sawBinaryChange = false;

  void flushRemovedLines() {
    if (pendingRemovedLines.isEmpty) return;
    removedRanges.add((
      afterLine: pendingRemovedAfterLine,
      content: pendingRemovedLines.join('\n'),
    ));
    pendingRemovedLines.clear();
  }

  for (final line in normalizedPatch.split('\n')) {
    if (line.startsWith('diff --git ')) {
      flushRemovedLines();
      insideHunk = false;
      continue;
    }
    if (line.startsWith('@@ ')) {
      flushRemovedLines();
      insideHunk = true;
      continue;
    }
    if (line.startsWith(r'\ No newline at end of file')) {
      continue;
    }
    if (!insideHunk && _isDiffMetadataLine(line)) {
      sawBinaryChange = sawBinaryChange || line.startsWith('Binary files ');
      continue;
    }

    if (insideHunk && line.startsWith('+')) {
      flushRemovedLines();
      final visibleLineIndex = visibleLines.length;
      visibleLines.add(line.substring(1));
      addedRanges.add((visibleLineIndex, visibleLineIndex));
    } else if (insideHunk && line.startsWith('-')) {
      final afterLine = visibleLines.length - 1;
      if (pendingRemovedLines.isNotEmpty &&
          pendingRemovedAfterLine != afterLine) {
        flushRemovedLines();
      }
      pendingRemovedAfterLine = afterLine;
      pendingRemovedLines.add(line.substring(1));
    } else {
      flushRemovedLines();
      visibleLines.add(line.startsWith(' ') ? line.substring(1) : line);
    }
  }
  flushRemovedLines();

  if (visibleLines.isEmpty && removedRanges.isEmpty) {
    return GitDiffDisplay(
      text: sawBinaryChange ? 'Binary file changed.' : 'No diff.',
      addedRanges: const [],
      removedRanges: const [],
    );
  }

  return GitDiffDisplay(
    text: visibleLines.join('\n'),
    addedRanges: addedRanges,
    removedRanges: removedRanges,
  );
}

bool _isDiffMetadataLine(String line) {
  return line.startsWith('index ') ||
      line.startsWith('--- ') ||
      line.startsWith('+++ ') ||
      line.startsWith('new file mode ') ||
      line.startsWith('deleted file mode ') ||
      line.startsWith('old mode ') ||
      line.startsWith('new mode ') ||
      line.startsWith('similarity index ') ||
      line.startsWith('dissimilarity index ') ||
      line.startsWith('rename from ') ||
      line.startsWith('rename to ') ||
      line.startsWith('copy from ') ||
      line.startsWith('copy to ') ||
      line.startsWith('Binary files ') ||
      line == 'GIT binary patch';
}
