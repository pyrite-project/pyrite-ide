/// Web stub of the status-bar git summary: no repository is reported.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

final gitStatusSummaryProvider = Provider<GitStatusSummary?>((ref) {
  return null;
});

class GitStatusSummary {
  const GitStatusSummary({required this.rootPath, required this.branchLabel});

  final String rootPath;
  final String branchLabel;

  static GitStatusSummary? inspect(String? workspacePath) => null;
}
