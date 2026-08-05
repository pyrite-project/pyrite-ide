import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/serial/repl_mode_provider.dart';

/// 文件传输模式。
///
/// [streaming] — 发送设备接收脚本后通过 stdin/stdout 流式传输，
///   兼容所有支持 raw REPL 的固件。
/// [chunked] — 在同一 REPL 会话中打开文件并逐块执行读写命令，
///   类似 Thonny 的文件操作方式，也支持不具备 raw REPL 的设备。
enum FileTransferMode { streaming, chunked }

/// Paste REPL cannot carry the streaming stdin/stdout protocol, so it always
/// uses chunked commands. Raw REPL honors the user's selected transfer mode.
FileTransferMode resolveFileTransferMode(
  ReplMode replMode,
  FileTransferMode preferredMode,
) {
  return replMode == ReplMode.paste ? FileTransferMode.chunked : preferredMode;
}

final fileTransferModeProvider = StateProvider<FileTransferMode>(
  (ref) => FileTransferMode.chunked,
);
