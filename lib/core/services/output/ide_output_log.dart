import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:xterm/xterm.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';

enum IdeOutputSource { ide, plugin, terminal }

class IdeOutputEntry {
  const IdeOutputEntry({
    required this.time,
    required this.source,
    required this.message,
    this.pluginId,
    this.sessionId,
  });

  final DateTime time;
  final IdeOutputSource source;
  final String message;
  final String? pluginId;
  final String? sessionId;
}

class IdeOutputLogNotifier extends StateNotifier<List<IdeOutputEntry>> {
  IdeOutputLogNotifier({I18nTranslate? translate})
    : _tr = translate ?? fallbackTranslate,
      super(const []);

  /// Renders the source tag in the active locale when an entry is written.
  final I18nTranslate _tr;

  static const int maxEntries = 1000;

  /// Upper bound on one entry's text.
  ///
  /// Every write copies the entry list and repaints the terminal, so a single
  /// oversized message (the device echoing a pasted script, a traceback that
  /// quotes a whole file) costs the panel far more than it is worth. The head
  /// is what a reader needs; the tail is dropped with a marker.
  static const int maxMessageChars = 8000;

  static DebugPrintCallback? debugMirror;
  static bool _mirroring = false;

  static void setDebugMirror(DebugPrintCallback? callback) {
    debugMirror = callback;
  }

  void add(
    IdeOutputSource source,
    String message, {
    String? pluginId,
    String? sessionId,
  }) {
    final entry = IdeOutputEntry(
      time: DateTime.now(),
      source: source,
      message: _cap(message),
      pluginId: pluginId,
      sessionId: sessionId,
    );
    ideOutputTerminal.write(_formatEntry(entry));
    _mutateStateSafely(() {
      final next = [...state, entry];
      state = next.length > maxEntries
          ? next.sublist(next.length - maxEntries)
          : next;
    });
    if (!_mirroring) {
      _mirroring = true;
      try {
        debugMirror?.call(_formatEntryForDebug(entry));
      } finally {
        _mirroring = false;
      }
    }
  }

  void clear() {
    ideOutputController.clearSelection();
    ideOutputTerminal.clear();
    _mutateStateSafely(() => state = const []);
  }

  void _mutateStateSafely(VoidCallback mutation) {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) mutation();
      });
      return;
    }
    mutation();
  }

  static String _cap(String message) {
    if (message.length <= maxMessageChars) return message;
    final dropped = message.length - maxMessageChars;
    return '${message.substring(0, maxMessageChars)}'
        '\n… ($dropped characters truncated)';
  }

  String _formatEntry(IdeOutputEntry entry) {
    final time = entry.time;
    final stamp =
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
    final prefix =
        '[$stamp] [${_sourceLabel(entry.source)}]${_scopeLabel(entry)} ';
    final normalized = entry.message
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final lines = normalized.split('\n');
    return '${['$prefix${lines.first}', for (final line in lines.skip(1)) '${' ' * prefix.length}$line'].join('\r\n')}\r\n';
  }

  String _formatEntryForDebug(IdeOutputEntry entry) {
    final time = entry.time;
    final stamp =
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
    return '[$stamp] [${_sourceLabel(entry.source)}]${_scopeLabel(entry)} '
        '${entry.message}';
  }

  String _scopeLabel(IdeOutputEntry entry) {
    final pluginId = entry.pluginId;
    if (pluginId == null || pluginId.isEmpty) return '';
    final sessionId = entry.sessionId;
    return sessionId == null || sessionId.isEmpty
        ? ' [$pluginId]'
        : ' [$pluginId/$sessionId]';
  }

  String _sourceLabel(IdeOutputSource source) {
    return switch (source) {
      IdeOutputSource.ide => 'IDE',
      IdeOutputSource.plugin => _tr(I18nKey.outputSourcePlugin),
      IdeOutputSource.terminal => _tr(I18nKey.outputSourceTerminal),
    };
  }
}

final Terminal ideOutputTerminal = Terminal(maxLines: 10000);
final TerminalController ideOutputController = TerminalController();

final ideOutputLogProvider =
    StateNotifierProvider<IdeOutputLogNotifier, List<IdeOutputEntry>>(
      (ref) => IdeOutputLogNotifier(translate: translateFor(ref)),
    );
