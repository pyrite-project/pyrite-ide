import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:xterm/xterm.dart';

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
  IdeOutputLogNotifier() : super(const []);

  static const int maxEntries = 1000;
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
      message: message,
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
      IdeOutputSource.plugin => '插件',
      IdeOutputSource.terminal => '终端',
    };
  }
}

final Terminal ideOutputTerminal = Terminal(maxLines: 10000);
final TerminalController ideOutputController = TerminalController();

final ideOutputLogProvider =
    StateNotifierProvider<IdeOutputLogNotifier, List<IdeOutputEntry>>(
      (ref) => IdeOutputLogNotifier(),
    );
