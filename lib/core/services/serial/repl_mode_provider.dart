import 'package:flutter_riverpod/flutter_riverpod.dart';

/// REPL 执行模式。
///
/// [rawRepl] — 标准 raw REPL（CTRL-A + 粘贴 + CTRL-D），兼容所有支持 raw REPL
///   的固件，并支持流式和分块文件传输。
/// [paste] — 通过 normal REPL 的 Ctrl-E 粘贴模式执行代码，兼容性最好，
///   适用于不支持 raw REPL 的固件，文件操作使用分块传输。
enum ReplMode { rawRepl, paste }

/// 当前 REPL 模式设置。
final replModeProvider = StateProvider<ReplMode>((ref) => ReplMode.rawRepl);
