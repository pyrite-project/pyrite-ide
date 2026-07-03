import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum LogLevel { send, recv, info, error }

class LogEntry {
  final DateTime time;
  final LogLevel level;
  final String pluginId;
  final String type;
  final String detail;

  const LogEntry({
    required this.time,
    required this.level,
    required this.pluginId,
    required this.type,
    required this.detail,
  });
}

class DebugLogService extends ChangeNotifier {
  static const int _maxEntries = 500;

  final List<LogEntry> _entries = [];

  UnmodifiableListView<LogEntry> get entries => UnmodifiableListView(_entries);

  void log({
    required LogLevel level,
    required String pluginId,
    required String type,
    String detail = '',
  }) {
    _entries.add(
      LogEntry(
        time: DateTime.now(),
        level: level,
        pluginId: pluginId,
        type: type,
        detail: detail,
      ),
    );
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }
}

final debugLogProvider = ChangeNotifierProvider<DebugLogService>((ref) {
  return DebugLogService();
});
