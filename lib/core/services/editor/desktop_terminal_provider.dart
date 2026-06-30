import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:pyrite_ide/core/services/output/ide_output_log.dart';
import 'package:xterm/xterm.dart';

class DesktopTerminalSession {
  DesktopTerminalSession({
    required this.id,
    required this.title,
    required this.terminal,
    required this.controller,
    required this.pty,
    required this.outputSubscription,
  });

  final int id;
  final String title;
  final Terminal terminal;
  final TerminalController controller;
  final Pty pty;
  final StreamSubscription<List<int>> outputSubscription;
}

class DesktopTerminalState {
  const DesktopTerminalState({
    this.sessions = const [],
    this.selectedId,
    this.error,
  });

  final List<DesktopTerminalSession> sessions;
  final int? selectedId;
  final String? error;

  DesktopTerminalSession? get selectedSession {
    for (final session in sessions) {
      if (session.id == selectedId) return session;
    }
    return sessions.isEmpty ? null : sessions.first;
  }

  DesktopTerminalState copyWith({
    List<DesktopTerminalSession>? sessions,
    int? selectedId,
    String? error,
    bool clearError = false,
  }) {
    return DesktopTerminalState(
      sessions: sessions ?? this.sessions,
      selectedId: selectedId ?? this.selectedId,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class DesktopTerminalNotifier extends StateNotifier<DesktopTerminalState> {
  DesktopTerminalNotifier(this.ref) : super(const DesktopTerminalState());

  final Ref ref;

  int _nextId = 1;

  bool get isSupported => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Future<void> createSession() async {
    if (!isSupported) {
      state = state.copyWith(error: '当前平台不支持桌面终端');
      return;
    }

    final id = _nextId++;
    final terminal = Terminal(maxLines: 10000);
    final controller = TerminalController();
    final shell = _defaultShell();

    try {
      final pty = Pty.start(
        shell.executable,
        arguments: shell.arguments,
        workingDirectory: Directory.current.path,
        rows: 25,
        columns: 80,
      );
      terminal.onOutput = (data) {
        pty.write(Uint8List.fromList(utf8.encode(data)));
      };
      final subscription = pty.output.listen((data) {
        terminal.write(utf8.decode(data, allowMalformed: true));
      });
      pty.exitCode.then((code) {
        final hexCode = (code & 0xffffffff).toRadixString(16).padLeft(8, '0');
        final message = '进程已退出，代码 $code (0x$hexCode)';
        terminal.write('\r\n[$message]\r\n');
        ref.read(ideOutputLogProvider.notifier).add(IdeOutputSource.terminal, '${shell.executable}: $message');
      });

      final session = DesktopTerminalSession(
        id: id,
        title: '终端 $id',
        terminal: terminal,
        controller: controller,
        pty: pty,
        outputSubscription: subscription,
      );
      state = state.copyWith(
        sessions: [...state.sessions, session],
        selectedId: id,
        clearError: true,
      );
      ref
          .read(ideOutputLogProvider.notifier)
          .add(IdeOutputSource.terminal, '启动 ${session.title}: ${shell.executable}');
    } catch (error) {
      state = state.copyWith(error: '启动终端失败: $error');
      ref
          .read(ideOutputLogProvider.notifier)
          .add(IdeOutputSource.terminal, '启动终端失败: $error');
    }
  }

  void selectSession(int id) {
    state = state.copyWith(selectedId: id);
  }

  Future<void> closeSession(int id) async {
    final session = state.sessions.where((item) => item.id == id).firstOrNull;
    if (session == null) return;
    await session.outputSubscription.cancel();
    session.pty.kill();

    final sessions = state.sessions.where((item) => item.id != id).toList();
    final selectedId = state.selectedId == id
        ? (sessions.isEmpty ? null : sessions.last.id)
        : state.selectedId;
    state = DesktopTerminalState(sessions: sessions, selectedId: selectedId);
  }

  Future<void> closeAll() async {
    for (final session in state.sessions) {
      await session.outputSubscription.cancel();
      session.pty.kill();
    }
    state = const DesktopTerminalState();
  }

  _ShellCommand _defaultShell() {
    if (Platform.isWindows) {
      return const _ShellCommand('cmd.exe', []);
    }
    if (Platform.isLinux || Platform.isMacOS) return const _ShellCommand('bash', []);
    return const _ShellCommand('sh', []);
  }
}

class _ShellCommand {
  const _ShellCommand(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}

final desktopTerminalProvider =
    StateNotifierProvider<DesktopTerminalNotifier, DesktopTerminalState>(
      (ref) => DesktopTerminalNotifier(ref),
    );
