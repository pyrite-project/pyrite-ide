import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ---------------------------------------------------------------------------
// StatusBarEntry — a single item in the bottom status bar
// ---------------------------------------------------------------------------

/// Describes one item that can appear in the status bar.
///
/// Items are sorted by [order] (ascending). Lower values appear further left.
///
/// Ordering convention:
///   0–9   LSP state
///  10–19  File state (current file, save status)
///  20–29  Board connection state
///  30–39  Git state
///  40–49  Running operations (code execution)
///  50–59  File transfer progress
///  60–69  Console toggle
/// 100+    External / plugin-contributed items
class StatusBarEntry {
  const StatusBarEntry({
    required this.id,
    required this.order,
    required this.builder,
  });

  /// Unique key — used for dedup and [StatusBarRegistryNotifier.unregister].
  final String id;

  /// Sort key — lower values appear further left.
  final int order;

  /// Builds the widget for this entry.
  final Widget Function(BuildContext context) builder;
}

// ---------------------------------------------------------------------------
// StatusBarRegistryNotifier — manages the list of registered entries
// ---------------------------------------------------------------------------

class StatusBarRegistryNotifier extends StateNotifier<List<StatusBarEntry>> {
  StatusBarRegistryNotifier() : super(const []);

  /// Registers (or replaces) an entry with the given [id].
  void register(
    String id, {
    required int order,
    required Widget Function(BuildContext context) builder,
  }) {
    state = [
      for (final e in state)
        if (e.id != id) e,
      StatusBarEntry(id: id, order: order, builder: builder),
    ]..sort((a, b) => a.order.compareTo(b.order));
  }

  /// Removes the entry with the given [id].
  void unregister(String id) {
    state = [
      for (final e in state)
        if (e.id != id) e,
    ];
  }
}

final statusBarRegistryProvider =
    StateNotifierProvider<StatusBarRegistryNotifier, List<StatusBarEntry>>(
      (ref) => StatusBarRegistryNotifier(),
    );
