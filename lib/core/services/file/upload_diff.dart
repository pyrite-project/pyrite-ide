import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  final m = a.length, n = b.length;

  final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));
  for (int i = 1; i <= m; i++) {
    for (int j = 1; j <= n; j++) {
      dp[i][j] = a[i - 1] == b[j - 1]
          ? dp[i - 1][j - 1] + 1
          : (dp[i - 1][j] > dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1]);
    }
  }

  final ops = <_DiffOp>[];
  int i = m, j = n;
  while (i > 0 || j > 0) {
    if (i > 0 && j > 0 && a[i - 1] == b[j - 1]) {
      ops.add(_DiffOp('=', a[i - 1], oldLine: i - 1, newLine: j - 1));
      i--;
      j--;
    } else if (j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j])) {
      ops.add(_DiffOp('+', b[j - 1], oldLine: -1, newLine: j - 1));
      j--;
    } else {
      ops.add(_DiffOp('-', a[i - 1], oldLine: i - 1, newLine: -1));
      i--;
    }
  }
  ops.sort((x, y) {
    final xi = x.type == '=' || x.type == '+' ? x.newLine : x.oldLine;
    final yi = y.type == '=' || y.type == '+' ? y.newLine : y.oldLine;
    return xi.compareTo(yi);
  });

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

class PendingUpload {
  final DiffInfo diff;
  final String localPath;
  final String targetPath;
  final String content;
  final Completer<bool> completer = Completer<bool>();

  PendingUpload({
    required this.diff,
    required this.localPath,
    required this.targetPath,
    required this.content,
  });
}

final pendingUploadProvider = StateProvider<PendingUpload?>((ref) => null);

class PendingDownload {
  final DiffInfo diff;
  final String boardPath;
  final String localPath;
  final String content;

  PendingDownload({
    required this.diff,
    required this.boardPath,
    required this.localPath,
    required this.content,
  });
}

final pendingDownloadProvider = StateProvider<PendingDownload?>((ref) => null);
