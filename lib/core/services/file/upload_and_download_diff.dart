import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/file/diff_info.dart';

export 'package:pyrite_ide/core/services/file/diff_info.dart';

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

class PendingDownload {
  final DiffInfo diff;
  final String boardPath;
  final String localPath;
  final String correspondingPath;
  final String content;

  PendingDownload({
    required this.diff,
    required this.boardPath,
    required this.localPath,
    required this.correspondingPath,
    required this.content,
  });
}

Map<String, StateProvider<PendingUpload?>> pendingUploadProviderMap = {};
Map<String, StateProvider<PendingDownload?>> pendingDownloadProviderMap = {};
