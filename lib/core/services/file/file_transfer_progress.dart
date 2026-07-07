import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

enum FileTransferDirection { upload, download, move }

enum FileTransferScope { file, folder }

class FileTransferProgressState {
  const FileTransferProgressState({
    this.isActive = false,
    this.direction,
    this.scope,
    this.currentFile,
    this.currentIndex = 0,
    this.totalFiles = 0,
    this.bytesDone = 0,
    this.bytesTotal = 0,
    this.message,
    this.failed = false,
  });

  final bool isActive;
  final FileTransferDirection? direction;
  final FileTransferScope? scope;
  final String? currentFile;
  final int currentIndex;
  final int totalFiles;
  final int bytesDone;
  final int bytesTotal;
  final String? message;
  final bool failed;

  double? get progress {
    if (bytesTotal <= 0) return null;
    return (bytesDone / bytesTotal).clamp(0, 1).toDouble();
  }

  String get directionLabel => switch (direction) {
    FileTransferDirection.upload => '上传',
    FileTransferDirection.download => '下载',
    FileTransferDirection.move => '移动',
    null => '传输',
  };

  String get scopeLabel => switch (scope) {
    FileTransferScope.file => '文件',
    FileTransferScope.folder => '文件夹',
    null => '',
  };

  FileTransferProgressState copyWith({
    bool? isActive,
    FileTransferDirection? direction,
    FileTransferScope? scope,
    String? currentFile,
    int? currentIndex,
    int? totalFiles,
    int? bytesDone,
    int? bytesTotal,
    String? message,
    bool? failed,
  }) {
    return FileTransferProgressState(
      isActive: isActive ?? this.isActive,
      direction: direction ?? this.direction,
      scope: scope ?? this.scope,
      currentFile: currentFile ?? this.currentFile,
      currentIndex: currentIndex ?? this.currentIndex,
      totalFiles: totalFiles ?? this.totalFiles,
      bytesDone: bytesDone ?? this.bytesDone,
      bytesTotal: bytesTotal ?? this.bytesTotal,
      message: message ?? this.message,
      failed: failed ?? this.failed,
    );
  }
}

class FileTransferProgressNotifier
    extends StateNotifier<FileTransferProgressState> {
  FileTransferProgressNotifier() : super(const FileTransferProgressState());

  Timer? _clearTimer;

  void start({
    required FileTransferDirection direction,
    required FileTransferScope scope,
    required int totalFiles,
    String? message,
  }) {
    _clearTimer?.cancel();
    state = FileTransferProgressState(
      isActive: true,
      direction: direction,
      scope: scope,
      totalFiles: totalFiles,
      message: message,
    );
  }

  void startFile({
    required String file,
    required int index,
    required int totalFiles,
    required int bytesTotal,
  }) {
    state = FileTransferProgressState(
      isActive: true,
      direction: state.direction,
      scope: state.scope,
      currentFile: file,
      currentIndex: index,
      totalFiles: totalFiles,
      bytesDone: 0,
      bytesTotal: bytesTotal,
      failed: false,
    );
  }

  void updateBytes(int done, int total) {
    state = state.copyWith(bytesDone: done, bytesTotal: total);
  }

  void complete({String? message}) {
    state = state.copyWith(
      isActive: true,
      bytesDone: state.bytesTotal,
      message: message ?? '${state.directionLabel}完成',
      failed: false,
    );
    _scheduleClear();
  }

  void fail(String message) {
    state = state.copyWith(isActive: true, message: message, failed: true);
    _scheduleClear(delay: const Duration(seconds: 5));
  }

  void clear() {
    _clearTimer?.cancel();
    state = const FileTransferProgressState();
  }

  void _scheduleClear({Duration delay = const Duration(seconds: 2)}) {
    _clearTimer?.cancel();
    _clearTimer = Timer(delay, clear);
  }

  @override
  void dispose() {
    _clearTimer?.cancel();
    super.dispose();
  }
}

final fileTransferProgressProvider =
    StateNotifierProvider<
      FileTransferProgressNotifier,
      FileTransferProgressState
    >((ref) => FileTransferProgressNotifier());
