import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';

// ---------------------------------------------------------------------------
// RunningOperation — describes a single long-running operation
// ---------------------------------------------------------------------------

class RunningOperation {
  const RunningOperation({
    required this.id,
    required this.icon,
    this.label = '',
    this.labelKey,
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
  ///
  /// Prefer [labelKey] so the status bar renders the label in the active
  /// locale; [label] is the raw-text fallback for callers without an i18n key.
  final String label;

  /// Localized display text; the status bar widget resolves it at build time
  /// so a locale change re-renders running chips without re-registering them.
  final I18nKey? labelKey;

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
    I18nKey? labelKey,
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
      labelKey: labelKey ?? this.labelKey,
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
