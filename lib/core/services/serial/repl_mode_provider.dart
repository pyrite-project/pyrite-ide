import 'package:flutter_riverpod/flutter_riverpod.dart';

/// REPL 执行模式。
///
/// [rawPaste] — 使用 MicroPython raw-paste 协议，支持流控和高效二进制传输，
///   需要较新的 MicroPython 固件。
/// [rawRepl] — 标准 raw REPL（CTRL-A + 粘贴 + CTRL-D），兼容所有支持 raw REPL
///   的固件，但不支持流控。
/// [paste] — 通过 normal REPL 的 Ctrl-E 粘贴模式执行代码，兼容性最好，
///   适用于不支持 raw REPL 的固件。
enum ReplMode {
  rawPaste,
  rawRepl,
  paste,
}

/// 当前 REPL 模式设置。
final replModeProvider = StateProvider<ReplMode>((ref) => ReplMode.rawPaste);
