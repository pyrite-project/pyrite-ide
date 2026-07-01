import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

enum IdeOutputSource { ide, plugin, terminal }

class IdeOutputEntry {
  const IdeOutputEntry({
    required this.time,
    required this.source,
    required this.message,
  });

  final DateTime time;
  final IdeOutputSource source;
  final String message;
}

class IdeOutputLogNotifier extends StateNotifier<List<IdeOutputEntry>> {
  IdeOutputLogNotifier() : super(const []);

  static const int maxEntries = 1000;
  static DebugPrintCallback? debugMirror;
  static bool _mirroring = false;

  static void setDebugMirror(DebugPrintCallback? callback) {
    debugMirror = callback;
  }

  void add(IdeOutputSource source, String message) {
    final entry = IdeOutputEntry(
      time: DateTime.now(),
      source: source,
      message: message,
    );
    ideOutputTerminal.write(_formatEntry(entry));
    final next = [
      ...state,
      entry,
    ];
    state = next.length > maxEntries
        ? next.sublist(next.length - maxEntries)
        : next;
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
    ideOutputTerminal.write('\x1b[2J\x1b[H');
    state = const [];
  }

  String _formatEntry(IdeOutputEntry entry) {
    final time = entry.time;
    final stamp = '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
    final prefix = '[$stamp] [${_sourceLabel(entry.source)}] ';
    final normalized = entry.message.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');
    return '${[
      '$prefix${lines.first}',
      for (final line in lines.skip(1)) '${' ' * prefix.length}$line',
    ].join('\r\n')}\r\n';
  }

  String _formatEntryForDebug(IdeOutputEntry entry) {
    final time = entry.time;
    final stamp = '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
    return '[$stamp] [${_sourceLabel(entry.source)}] ${entry.message}';
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
