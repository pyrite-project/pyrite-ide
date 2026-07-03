class DiffInfo {
  final List<(int startLine, int endLine)> addedRanges;
  final List<({int afterLine, String content})> removedRanges;
  final List<String> unifiedLines;
  final int addCount;
  final int removeCount;

  DiffInfo({
    required this.addedRanges,
    required this.removedRanges,
    required this.unifiedLines,
    required this.addCount,
    required this.removeCount,
  });
}

DiffInfo computeDiff(String oldText, String newText) {
  final a = oldText.split('\n');
  final b = newText.split('\n');
  final ops = _normalizeEditOrder(_myersDiff(a, b));

  final addedRanges = <(int, int)>[];
  final removedRanges = <({int afterLine, String content})>[];
  final unifiedLines = <String>[];
  int addCount = 0, removeCount = 0;
  int newPos = 0;

  int? addStart;
  int? remAfterLine;
  final remBuf = StringBuffer();

  void flushAdd() {
    if (addStart != null) {
      addedRanges.add((addStart!, newPos - 1));
      addStart = null;
    }
  }

  void flushRem() {
    if (remBuf.isNotEmpty) {
      removedRanges.add((afterLine: remAfterLine!, content: remBuf.toString()));
      remBuf.clear();
      remAfterLine = null;
    }
  }

  for (final op in ops) {
    if (op.type == '=') {
      flushAdd();
      flushRem();
      unifiedLines.add(' ${op.text}');
      newPos++;
    } else if (op.type == '+') {
      addCount++;
      unifiedLines.add('+${op.text}');
      addStart ??= newPos;
      newPos++;
      flushRem();
    } else {
      removeCount++;
      unifiedLines.add('-${op.text}');
      remAfterLine ??= newPos - 1;
      if (remBuf.isNotEmpty) remBuf.write('\n');
      remBuf.write(op.text);
      flushAdd();
    }
  }
  flushAdd();
  flushRem();

  return DiffInfo(
    addedRanges: addedRanges,
    removedRanges: removedRanges,
    unifiedLines: unifiedLines,
    addCount: addCount,
    removeCount: removeCount,
  );
}

class _DiffOp {
  final String type;
  final String text;
  final int oldLine;
  final int newLine;
  _DiffOp(this.type, this.text, {required this.oldLine, required this.newLine});
}

List<_DiffOp> _myersDiff(List<String> oldLines, List<String> newLines) {
  final oldLength = oldLines.length;
  final newLength = newLines.length;
  final maxDistance = oldLength + newLength;
  var furthestByDiagonal = <int, int>{1: 0};
  final trace = <Map<int, int>>[];

  for (var distance = 0; distance <= maxDistance; distance += 1) {
    final nextFurthestByDiagonal = <int, int>{};
    for (var diagonal = -distance; diagonal <= distance; diagonal += 2) {
      final canMoveDown =
          diagonal == -distance ||
          (diagonal != distance &&
              (furthestByDiagonal[diagonal - 1] ?? -1) <
                  (furthestByDiagonal[diagonal + 1] ?? -1));
      var oldIndex = canMoveDown
          ? furthestByDiagonal[diagonal + 1] ?? 0
          : (furthestByDiagonal[diagonal - 1] ?? 0) + 1;
      var newIndex = oldIndex - diagonal;

      while (oldIndex < oldLength &&
          newIndex < newLength &&
          oldLines[oldIndex] == newLines[newIndex]) {
        oldIndex += 1;
        newIndex += 1;
      }

      nextFurthestByDiagonal[diagonal] = oldIndex;
      if (oldIndex >= oldLength && newIndex >= newLength) {
        trace.add(nextFurthestByDiagonal);
        return _backtrackMyersDiff(trace, oldLines, newLines);
      }
    }
    trace.add(nextFurthestByDiagonal);
    furthestByDiagonal = nextFurthestByDiagonal;
  }

  return [
    for (var index = 0; index < oldLength; index += 1)
      _DiffOp('-', oldLines[index], oldLine: index, newLine: -1),
    for (var index = 0; index < newLength; index += 1)
      _DiffOp('+', newLines[index], oldLine: -1, newLine: index),
  ];
}

List<_DiffOp> _backtrackMyersDiff(
  List<Map<int, int>> trace,
  List<String> oldLines,
  List<String> newLines,
) {
  var oldIndex = oldLines.length;
  var newIndex = newLines.length;
  final ops = <_DiffOp>[];

  for (var distance = trace.length - 1; distance > 0; distance -= 1) {
    final previousFurthestByDiagonal = trace[distance - 1];
    final diagonal = oldIndex - newIndex;
    final movedDown =
        diagonal == -distance ||
        (diagonal != distance &&
            (previousFurthestByDiagonal[diagonal - 1] ?? -1) <
                (previousFurthestByDiagonal[diagonal + 1] ?? -1));
    final previousDiagonal = movedDown ? diagonal + 1 : diagonal - 1;
    final previousOldIndex = previousFurthestByDiagonal[previousDiagonal] ?? 0;
    final previousNewIndex = previousOldIndex - previousDiagonal;

    while (oldIndex > previousOldIndex && newIndex > previousNewIndex) {
      ops.add(
        _DiffOp(
          '=',
          oldLines[oldIndex - 1],
          oldLine: oldIndex - 1,
          newLine: newIndex - 1,
        ),
      );
      oldIndex -= 1;
      newIndex -= 1;
    }

    if (movedDown) {
      ops.add(
        _DiffOp(
          '+',
          newLines[newIndex - 1],
          oldLine: -1,
          newLine: newIndex - 1,
        ),
      );
      newIndex -= 1;
    } else {
      ops.add(
        _DiffOp(
          '-',
          oldLines[oldIndex - 1],
          oldLine: oldIndex - 1,
          newLine: -1,
        ),
      );
      oldIndex -= 1;
    }
  }

  while (oldIndex > 0 && newIndex > 0) {
    ops.add(
      _DiffOp(
        '=',
        oldLines[oldIndex - 1],
        oldLine: oldIndex - 1,
        newLine: newIndex - 1,
      ),
    );
    oldIndex -= 1;
    newIndex -= 1;
  }
  while (oldIndex > 0) {
    ops.add(
      _DiffOp('-', oldLines[oldIndex - 1], oldLine: oldIndex - 1, newLine: -1),
    );
    oldIndex -= 1;
  }
  while (newIndex > 0) {
    ops.add(
      _DiffOp('+', newLines[newIndex - 1], oldLine: -1, newLine: newIndex - 1),
    );
    newIndex -= 1;
  }

  return ops.reversed.toList();
}

List<_DiffOp> _normalizeEditOrder(List<_DiffOp> ops) {
  final normalized = <_DiffOp>[];
  final removed = <_DiffOp>[];
  final added = <_DiffOp>[];

  void flushEdits() {
    if (removed.isNotEmpty) {
      normalized.addAll(removed);
      removed.clear();
    }
    if (added.isNotEmpty) {
      normalized.addAll(added);
      added.clear();
    }
  }

  for (final op in ops) {
    if (op.type == '=') {
      flushEdits();
      normalized.add(op);
    } else if (op.type == '-') {
      removed.add(op);
    } else {
      added.add(op);
    }
  }
  flushEdits();

  return normalized;
}
