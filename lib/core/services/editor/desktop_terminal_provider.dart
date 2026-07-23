import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
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

  bool get isSupported =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Future<void> createSession() async {
    if (!isSupported) {
      state = state.copyWith(
        error: translate(ref, I18nKey.terminalUnsupportedPlatform),
      );
      return;
    }

    final id = _nextId++;
    final terminal = Terminal(maxLines: 10000);
    final controller = TerminalController();
    final shell = _defaultShell();

    try {
      final session = _startSessionProcess(
        id: id,
        title: translate(
          ref,
          I18nKey.terminalSessionTitle,
        ).replaceAll('{id}', id.toString()),
        terminal: terminal,
        controller: controller,
        shell: shell,
      );
      state = state.copyWith(
        sessions: [...state.sessions, session],
        selectedId: id,
        clearError: true,
      );
      ref
          .read(ideOutputLogProvider.notifier)
          .add(
            IdeOutputSource.terminal,
            translate(ref, I18nKey.terminalStarted)
                .replaceAll('{title}', session.title)
                .replaceAll('{executable}', shell.executable),
          );
    } catch (error) {
      final message = translate(
        ref,
        I18nKey.terminalStartFailed,
      ).replaceAll('{error}', error.toString());
      state = state.copyWith(error: message);
      ref
          .read(ideOutputLogProvider.notifier)
          .add(IdeOutputSource.terminal, message);
    }
  }

  DesktopTerminalSession _startSessionProcess({
    required int id,
    required String title,
    required Terminal terminal,
    required TerminalController controller,
    required _ShellCommand shell,
  }) {
    final pty = Pty.start(
      shell.executable,
      arguments: shell.arguments,
      workingDirectory: Directory.current.path,
      environment: _terminalEnvironment(),
      rows: 25,
      columns: 80,
    );
    terminal.onOutput = (data) {
      pty.write(Uint8List.fromList(utf8.encode(data)));
    };
    terminal.onResize = (int cols, int rows, int pw, int ph) {
      pty.resize(rows, cols);
    };
    final subscription = pty.output.listen((data) {
      terminal.write(utf8.decode(data, allowMalformed: true));
    });
    pty.exitCode.then(
      (code) => _handleProcessExit(
        id: id,
        title: title,
        terminal: terminal,
        controller: controller,
        pty: pty,
        shell: shell,
        code: code,
      ),
    );

    return DesktopTerminalSession(
      id: id,
      title: title,
      terminal: terminal,
      controller: controller,
      pty: pty,
      outputSubscription: subscription,
    );
  }

  Future<void> _handleProcessExit({
    required int id,
    required String title,
    required Terminal terminal,
    required TerminalController controller,
    required Pty pty,
    required _ShellCommand shell,
    required int code,
  }) async {
    final current = state.sessions.where((item) => item.id == id).firstOrNull;
    if (current == null || current.pty != pty) return;

    final hexCode = (code & 0xffffffff).toRadixString(16).padLeft(8, '0');
    final message = translate(
      ref,
      I18nKey.terminalProcessExited,
    ).replaceAll('{code}', code.toString()).replaceAll('{hexCode}', hexCode);
    terminal.write('\r\n[$message]\r\n');
    ref
        .read(ideOutputLogProvider.notifier)
        .add(IdeOutputSource.terminal, '${shell.executable}: $message');

    if (code == 0) return;

    await current.outputSubscription.cancel();
    try {
      final restarted = _startSessionProcess(
        id: id,
        title: title,
        terminal: terminal,
        controller: controller,
        shell: shell,
      );
      final sessions = [
        for (final session in state.sessions)
          if (session.id == id) restarted else session,
      ];
      state = state.copyWith(sessions: sessions, clearError: true);
      terminal.write(
        '[${translate(ref, I18nKey.terminalRestartedProcess)}]\r\n',
      );
      ref
          .read(ideOutputLogProvider.notifier)
          .add(
            IdeOutputSource.terminal,
            translate(ref, I18nKey.terminalRestarted)
                .replaceAll('{title}', title)
                .replaceAll('{executable}', shell.executable),
          );
    } catch (error) {
      final message = translate(
        ref,
        I18nKey.terminalRestartFailed,
      ).replaceAll('{error}', error.toString());
      state = state.copyWith(error: message);
      terminal.write('[$message]\r\n');
      ref
          .read(ideOutputLogProvider.notifier)
          .add(IdeOutputSource.terminal, message);
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
      return _ShellCommand(_windowsPowerShellPath(), const [
        '-NoLogo',
        '-NoExit',
      ]);
    }
    if (Platform.isLinux || Platform.isMacOS) {
      return const _ShellCommand('bash', []);
    }
    return const _ShellCommand('sh', []);
  }

  String _windowsPowerShellPath() {
    final systemRoot =
        Platform.environment['SystemRoot'] ??
        Platform.environment['SYSTEMROOT'];
    if (systemRoot != null && systemRoot.isNotEmpty) {
      final executable = File(
        '$systemRoot\\System32\\WindowsPowerShell\\v1.0\\powershell.exe',
      );
      if (executable.existsSync()) return executable.path;
    }
    return 'powershell.exe';
  }

  Map<String, String> _terminalEnvironment() {
    final environment = Map<String, String>.of(Platform.environment);
    environment['TERM'] = environment['TERM']?.isNotEmpty == true
        ? environment['TERM']!
        : 'xterm-256color';
    environment['COLORTERM'] = environment['COLORTERM']?.isNotEmpty == true
        ? environment['COLORTERM']!
        : 'truecolor';
    environment['LANG'] = environment['LANG']?.isNotEmpty == true
        ? environment['LANG']!
        : 'en_US.UTF-8';
    return environment;
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
