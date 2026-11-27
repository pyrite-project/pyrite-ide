import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_pty/flutter_pty.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/logging/app_log.dart';
import 'package:pyrite_ide/core/services/output/ide_output_log.dart';
import 'package:xterm/xterm.dart';

class DesktopTerminalSession {
  DesktopTerminalSession({
    required this.id,
    required this.title,
    required this.terminal,
    required this.controller,
    required this.process,
    required this.outputSubscription,
    required this.backgroundColor,
  });

  final int id;
  final String title;
  final Terminal terminal;
  final TerminalController controller;
  final DesktopTerminalProcess process;
  final StreamSubscription<String> outputSubscription;
  final ValueNotifier<Color?> backgroundColor;
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

  Future<void> createSession({
    void Function(Terminal, ValueNotifier<Color?>)? configureTerminal,
    Directory? defaultDir,
  }) async {
    if (!isSupported) {
      state = state.copyWith(
        error: translate(ref, I18nKey.terminalUnsupportedPlatform),
      );
      return;
    }

    final id = _nextId++;
    final terminal = Terminal(maxLines: 10000);
    final backgroundColor = ValueNotifier<Color?>(null);
    configureTerminal?.call(terminal, backgroundColor);
    final controller = TerminalController();
    final shell = _defaultShell();
    final startDirectory = _resolveStartDirectory(defaultDir);

    try {
      final session = await _startSessionProcess(
        id: id,
        title: translate(
          ref,
          I18nKey.terminalSessionTitle,
        ).replaceAll('{id}', id.toString()),
        terminal: terminal,
        controller: controller,
        shell: shell,
        defaultDir: startDirectory,
        backgroundColor: backgroundColor,
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
      backgroundColor.dispose();
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

  Future<DesktopTerminalSession> _startSessionProcess({
    required int id,
    required String title,
    required Terminal terminal,
    required TerminalController controller,
    required _ShellCommand shell,
    required ValueNotifier<Color?> backgroundColor,
    String? defaultDir,
  }) async {
    final process = await _startTerminalProcess(
      shell: shell,
      workingDirectory: defaultDir ?? Directory.current.path,
    );
    terminal.onOutput = (data) {
      process.write(utf8.encode(data));
    };
    terminal.onResize = (int cols, int rows, int pw, int ph) {
      process.resize(rows, cols);
    };
    final subscription = decodeTerminalOutput(
      process.output,
    ).listen(terminal.write);
    if (process is _PipeTerminalProcess) {
      terminal.write(
        '\r\n[${translate(ref, I18nKey.terminalPipeFallback)}]\r\n',
      );
    }
    process.exitCode.then(
      (code) => _handleProcessExit(
        id: id,
        title: title,
        terminal: terminal,
        controller: controller,
        process: process,
        shell: shell,
        startDirectory: defaultDir ?? Directory.current.path,
        code: code,
      ),
    );

    return DesktopTerminalSession(
      id: id,
      title: title,
      terminal: terminal,
      controller: controller,
      process: process,
      outputSubscription: subscription,
      backgroundColor: backgroundColor,
    );
  }

  /// Set after the first launch attempt tells us whether the host exposes the
  /// pseudoconsole API. Windows only ships ConPTY from version 1809 (build
  /// 17763); on older builds `flutter_pty.dll` cannot even be loaded, so the
  /// session falls back to plain pipes instead of failing outright.
  bool? _conPtyAvailable;

  Future<DesktopTerminalProcess> _startTerminalProcess({
    required _ShellCommand shell,
    required String workingDirectory,
  }) async {
    final environment = _terminalEnvironment();

    if (!Platform.isWindows || _conPtyAvailable != false) {
      try {
        final pty = Pty.start(
          shell.executable,
          arguments: shell.arguments,
          workingDirectory: workingDirectory,
          environment: environment,
          rows: 25,
          columns: 80,
        );
        _conPtyAvailable = true;
        return _ConPtyTerminalProcess(pty);
      } catch (error) {
        if (!Platform.isWindows) rethrow;
        _conPtyAvailable = false;
        AppLog.w(
          'terminal',
          'ConPTY unavailable, falling back to a pipe-backed shell',
          error: error,
        );
        ref
            .read(ideOutputLogProvider.notifier)
            .add(
              IdeOutputSource.terminal,
              translate(ref, I18nKey.terminalPipeFallback),
            );
      }
    }

    // cmd.exe copes with redirected stdin/stdout, and the UTF-8 code page
    // keeps its output decodable by the terminal widget.
    final process = await Process.start(
      'cmd.exe',
      const ['/Q', '/K', 'chcp 65001>nul'],
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: false,
    );
    return _PipeTerminalProcess(process);
  }

  Future<void> _handleProcessExit({
    required int id,
    required String title,
    required Terminal terminal,
    required TerminalController controller,
    required DesktopTerminalProcess process,
    required _ShellCommand shell,
    required String startDirectory,
    required int code,
  }) async {
    final current = state.sessions.where((item) => item.id == id).firstOrNull;
    if (current == null || current.process != process) return;

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
      final restarted = await _startSessionProcess(
        id: id,
        title: title,
        terminal: terminal,
        controller: controller,
        shell: shell,
        defaultDir: startDirectory,
        backgroundColor: current.backgroundColor,
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
    session.process.kill();
    session.backgroundColor.dispose();

    final sessions = state.sessions.where((item) => item.id != id).toList();
    final selectedId = state.selectedId == id
        ? (sessions.isEmpty ? null : sessions.last.id)
        : state.selectedId;
    state = DesktopTerminalState(sessions: sessions, selectedId: selectedId);
  }

  Future<void> closeAll() async {
    for (final session in state.sessions) {
      await session.outputSubscription.cancel();
      session.process.kill();
      session.backgroundColor.dispose();
    }
    state = const DesktopTerminalState();
  }

  /// Picks the working directory for a new session: the workspace root while
  /// it still exists, otherwise the process directory. A project that was
  /// moved must not turn every new terminal into a launch failure.
  String _resolveStartDirectory(Directory? workspace) {
    final workspacePath = workspace?.path.trim();
    if (workspacePath != null &&
        workspacePath.isNotEmpty &&
        Directory(workspacePath).existsSync()) {
      return workspacePath;
    }
    return Directory.current.path;
  }

  _ShellCommand _defaultShell() {
    if (Platform.isWindows) {
      return _ShellCommand(_windowsPowerShellPath(), const [
        '-NoLogo',
        '-NoExit',
      ]);
    }
    if (Platform.isLinux || Platform.isMacOS) {
      // Use system default shell from environment variable
      final systemShell = Platform.environment['SHELL'];
      if (systemShell != null && systemShell.isNotEmpty) {
        return _ShellCommand(systemShell, const []);
      }
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

Stream<String> decodeTerminalOutput(Stream<List<int>> output) {
  // Use the decoder's bind API so Dart owns the incremental chunked conversion
  // and the input remains the PTY's Stream<List<int>> type.
  return const Utf8Decoder(allowMalformed: true).bind(output);
}

/// The narrow slice of a child process the terminal needs: bytes in, bytes
/// out, an exit code, and a way to kill it.
///
/// ConPTY provides that plus window-size negotiation. On Windows builds that
/// predate ConPTY (10.0.17763) the terminal falls back to plain pipes, which
/// keep commands and output working but cannot resize the console.
abstract class DesktopTerminalProcess {
  Stream<List<int>> get output;

  Future<int> get exitCode;

  void write(List<int> data);

  void resize(int rows, int cols);

  void kill();
}

class _ConPtyTerminalProcess implements DesktopTerminalProcess {
  _ConPtyTerminalProcess(this._pty);

  final Pty _pty;

  @override
  Stream<List<int>> get output => _pty.output;

  @override
  Future<int> get exitCode => _pty.exitCode;

  @override
  void write(List<int> data) => _pty.write(Uint8List.fromList(data));

  @override
  void resize(int rows, int cols) => _pty.resize(rows, cols);

  @override
  void kill() => _pty.kill();
}

class _PipeTerminalProcess implements DesktopTerminalProcess {
  _PipeTerminalProcess(this._process) {
    var remaining = 2;
    void onDone() {
      if (--remaining == 0 && !_output.isClosed) _output.close();
    }

    _subscriptions = [
      _process.stdout.listen(
        _output.add,
        onError: _output.addError,
        onDone: onDone,
      ),
      _process.stderr.listen(
        _output.add,
        onError: _output.addError,
        onDone: onDone,
      ),
    ];
  }

  final Process _process;
  final StreamController<List<int>> _output = StreamController<List<int>>();
  late final List<StreamSubscription<List<int>>> _subscriptions;
  bool _closed = false;

  @override
  Stream<List<int>> get output => _output.stream;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  void write(List<int> data) {
    if (_closed) return;
    try {
      _process.stdin.add(data);
    } catch (_) {
      // The child can exit between a keystroke and this call; the exit itself
      // is reported through [exitCode], so a lost write needs no recovery.
    }
  }

  @override
  void resize(int rows, int cols) {
    // Pipes have no window size to negotiate.
  }

  @override
  void kill() {
    _closed = true;
    _process.kill();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    if (!_output.isClosed) _output.close();
  }
}

final desktopTerminalProvider =
    StateNotifierProvider<DesktopTerminalNotifier, DesktopTerminalState>(
      DesktopTerminalNotifier.new,
    );
