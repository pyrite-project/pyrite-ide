import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ---------------------------------------------------------------------------
// RunningOperation — describes a single long-running operation
// ---------------------------------------------------------------------------

class RunningOperation {
  const RunningOperation({
    required this.id,
    required this.label,
    required this.icon,
    this.canInterrupt = false,
    this.canForceReset = false,
    this.onInterrupt,
    this.onForceReset,
    this.progress,
    this.failed = false,
  });

  /// Unique key — used for dedup and removal.
  final String id;

  /// Display text shown in the status bar.
  final String label;

  /// Display icon shown in the status bar.
  final IconData icon;

  /// Whether to show an interrupt (CTRL-C) button.
  final bool canInterrupt;

  /// Whether to show a force-reset button (for stuck states).
  final bool canForceReset;

  /// Called when the interrupt button is pressed.
  final VoidCallback? onInterrupt;

  /// Called when the force-reset button is pressed.
  final VoidCallback? onForceReset;

  /// Progress value 0.0–1.0, or `null` for an indeterminate spinner.
  final double? progress;

  /// Whether this operation has failed.
  final bool failed;

  RunningOperation copyWith({
    String? id,
    String? label,
    IconData? icon,
    bool? canInterrupt,
    bool? canForceReset,
    VoidCallback? onInterrupt,
    VoidCallback? onForceReset,
    double? progress,
    bool? failed,
  }) {
    return RunningOperation(
      id: id ?? this.id,
      label: label ?? this.label,
      icon: icon ?? this.icon,
      canInterrupt: canInterrupt ?? this.canInterrupt,
      canForceReset: canForceReset ?? this.canForceReset,
      onInterrupt: onInterrupt ?? this.onInterrupt,
      onForceReset: onForceReset ?? this.onForceReset,
      progress: progress ?? this.progress,
      failed: failed ?? this.failed,
    );
  }
}

// ---------------------------------------------------------------------------
// RunningOperationsNotifier — manages the list of active operations
// ---------------------------------------------------------------------------

class RunningOperationsNotifier extends StateNotifier<List<RunningOperation>> {
  RunningOperationsNotifier() : super(const []);

  /// Adds or updates an operation by [id].
  void start(RunningOperation op) {
    state = [
      for (final e in state)
        if (e.id != op.id) e,
      op,
    ];
  }

  /// Removes the operation with the given [id].
  void stop(String id) {
    state = [
      for (final e in state)
        if (e.id != id) e,
    ];
  }

  /// Updates the progress of the operation with the given [id].
  void updateProgress(String id, double? progress) {
    state = [
      for (final e in state)
        if (e.id == id) e.copyWith(progress: progress) else e,
    ];
  }
}

final runningOperationsProvider =
    StateNotifierProvider<RunningOperationsNotifier, List<RunningOperation>>(
      (ref) => RunningOperationsNotifier(),
    );
