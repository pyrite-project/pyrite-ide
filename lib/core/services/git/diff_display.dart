class GitDiffDisplay {
  const GitDiffDisplay({
    required this.text,
    required this.addedRanges,
    required this.deletedRanges,
  });

  final String text;
  final List<(int startLine, int endLine)> addedRanges;
  final List<(int startLine, int endLine)> deletedRanges;
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
      deletedRanges: [],
    );
  }

  final visibleLines = <String>[];
  final addedRanges = <(int startLine, int endLine)>[];
  final deletedRanges = <(int startLine, int endLine)>[];
  var insideHunk = false;
  var sawBinaryChange = false;

  for (final line in normalizedPatch.split('\n')) {
    if (line.startsWith('diff --git ')) {
      insideHunk = false;
      continue;
    }
    if (line.startsWith('@@ ')) {
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

    final visibleLineIndex = visibleLines.length;
    visibleLines.add(line);
    if (line.startsWith('+')) {
      addedRanges.add((visibleLineIndex, visibleLineIndex));
    } else if (line.startsWith('-')) {
      deletedRanges.add((visibleLineIndex, visibleLineIndex));
    }
  }

  if (visibleLines.isEmpty) {
    return GitDiffDisplay(
      text: sawBinaryChange ? 'Binary file changed.' : 'No diff.',
      addedRanges: const [],
      deletedRanges: const [],
    );
  }

  return GitDiffDisplay(
    text: visibleLines.join('\n'),
    addedRanges: addedRanges,
    deletedRanges: deletedRanges,
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
