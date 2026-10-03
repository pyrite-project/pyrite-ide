/// Web stub of the desktop terminal provider.
///
/// A browser cannot spawn a pseudo-terminal, so the terminal panel stays
/// disabled exactly like on Android: [DesktopTerminalNotifier.isSupported] is
/// always false and [createSession] records the platform-unsupported error.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/platform/pyrite_io.dart';
import 'package:xterm/xterm.dart';

class DesktopTerminalSession {
  DesktopTerminalSession({
    required this.id,
    required this.title,
    required this.terminal,
    required this.controller,
    required this.backgroundColor,
  });

  final int id;
  final String title;
  final Terminal terminal;
  final TerminalController controller;
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

  bool get isSupported => false;

  Future<void> createSession({
    void Function(Terminal, ValueNotifier<Color?>)? configureTerminal,
    Directory? defaultDir,
  }) async {
    state = state.copyWith(
      error: translate(ref, I18nKey.terminalUnsupportedPlatform),
    );
  }

  void selectSession(int id) {
    state = state.copyWith(selectedId: id);
  }

  Future<void> closeSession(int id) async {}

  Future<void> closeAll() async {}
}

/// Decodes PTY output; kept for interface parity with the io provider.
Stream<String> decodeTerminalOutput(Stream<List<int>> output) {
  return const Utf8Decoder(allowMalformed: true).bind(output);
}

final desktopTerminalProvider =
    StateNotifierProvider<DesktopTerminalNotifier, DesktopTerminalState>(
      (ref) => DesktopTerminalNotifier(ref),
    );
