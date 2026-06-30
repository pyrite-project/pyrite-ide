import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  void add(IdeOutputSource source, String message) {
    final next = [
      ...state,
      IdeOutputEntry(time: DateTime.now(), source: source, message: message),
    ];
    state = next.length > maxEntries
        ? next.sublist(next.length - maxEntries)
        : next;
  }

  void clear() {
    state = const [];
  }
}

final ideOutputLogProvider =
    StateNotifierProvider<IdeOutputLogNotifier, List<IdeOutputEntry>>(
      (ref) => IdeOutputLogNotifier(),
    );
