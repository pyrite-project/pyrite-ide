import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tolyui_message/tolyui_message.dart';

enum IdeMessageType { info, success, warning, error }

class IdeMessageEntry {
  IdeMessageEntry({
    required this.id,
    required this.type,
    required this.message,
    required this.duration,
    required this.closeable,
  });

  final String id;
  final IdeMessageType type;
  final String message;
  final Duration duration;
  final bool closeable;
}

class IdeMessageNotifier extends StateNotifier<List<IdeMessageEntry>> {
  IdeMessageNotifier() : super(const []);

  /// Maximum number of messages on screen at once; adding another evicts the
  /// oldest one (and cancels its timer).
  static const int maxVisible = 4;

  /// The default lifetime for [type]: warnings and errors stay long enough to
  /// read, successes leave quickly.
  static Duration defaultDurationFor(IdeMessageType type) => switch (type) {
    IdeMessageType.success => const Duration(seconds: 3),
    IdeMessageType.info => const Duration(seconds: 4),
    IdeMessageType.warning => const Duration(seconds: 6),
    IdeMessageType.error => const Duration(seconds: 8),
  };

  /// Whether [type] can be dismissed by hand by default. Warnings and errors
  /// are closeable; transient success/info toasts are not.
  static bool defaultCloseableFor(IdeMessageType type) => switch (type) {
    IdeMessageType.warning || IdeMessageType.error => true,
    IdeMessageType.success || IdeMessageType.info => false,
  };

  final Map<String, Timer> _timers = {};
  int _nextId = 0;

  void show(
    String message, {
    IdeMessageType type = IdeMessageType.info,
    Duration? duration,
    bool? closeable,
  }) {
    if (message.isEmpty) return;
    final effectiveDuration = duration ?? defaultDurationFor(type);
    final effectiveCloseable = closeable ?? defaultCloseableFor(type);

    // Repeating the same message of the same type refreshes the visible entry
    // and restarts its timer instead of stacking an identical panel.
    final existingIndex = state.indexWhere(
      (entry) => entry.type == type && entry.message == message,
    );
    if (existingIndex >= 0) {
      final existing = state[existingIndex];
      _timers.remove(existing.id)?.cancel();
      state = [
        for (var index = 0; index < state.length; index++)
          if (index == existingIndex)
            IdeMessageEntry(
              id: existing.id,
              type: type,
              message: message,
              duration: effectiveDuration,
              closeable: effectiveCloseable,
            )
          else
            state[index],
      ];
      _timers[existing.id] = Timer(
        effectiveDuration,
        () => dismiss(existing.id),
      );
      return;
    }

    final id = 'ide_message_${_nextId++}';
    final entry = IdeMessageEntry(
      id: id,
      type: type,
      message: message,
      duration: effectiveDuration,
      closeable: effectiveCloseable,
    );

    final overflow = state.length - maxVisible + 1;
    if (overflow > 0) {
      for (var index = 0; index < overflow; index++) {
        _timers.remove(state[index].id)?.cancel();
      }
      state = [...state.sublist(overflow), entry];
    } else {
      state = [...state, entry];
    }
    _timers[id] = Timer(effectiveDuration, () => dismiss(id));
  }

  void info(String message) => show(message);

  void success(String message) => show(message, type: IdeMessageType.success);

  void warning(String message) => show(message, type: IdeMessageType.warning);

  void error(String message) => show(message, type: IdeMessageType.error);

  void dismiss(String id) {
    _timers.remove(id)?.cancel();
    state = [
      for (final entry in state)
        if (entry.id != id) entry,
    ];
  }

  @override
  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    super.dispose();
  }
}

final ideMessageProvider =
    StateNotifierProvider<IdeMessageNotifier, List<IdeMessageEntry>>(
      (ref) => IdeMessageNotifier(),
    );

void showIdeMessage(
  BuildContext context,
  String message, {
  IdeMessageType type = IdeMessageType.info,
  Duration? duration,
  bool? closeable,
}) {
  ProviderScope.containerOf(context, listen: false)
      .read(ideMessageProvider.notifier)
      .show(message, type: type, duration: duration, closeable: closeable);
}

void showIdeSuccess(BuildContext context, String message) {
  showIdeMessage(context, message, type: IdeMessageType.success);
}

void showIdeWarning(BuildContext context, String message) {
  showIdeMessage(context, message, type: IdeMessageType.warning);
}

void showIdeError(BuildContext context, String message) {
  showIdeMessage(context, message, type: IdeMessageType.error);
}

class IdeMessageHost extends ConsumerWidget {
  const IdeMessageHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(ideMessageProvider);
    if (entries.isEmpty) return const SizedBox.shrink();

    return Positioned.fill(
      child: SafeArea(
        child: IgnorePointer(
          ignoring: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 16, left: 16, right: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final entry in entries)
                    Padding(
                      key: ValueKey(entry.id),
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _IdeMessagePanel(entry: entry),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IdeMessagePanel extends ConsumerWidget {
  const _IdeMessagePanel({required this.entry});

  final IdeMessageEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = _styleFor(context, entry.type);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      child: MessagePanel(
        key: ValueKey(entry.id),
        message: entry.message,
        icon: style.icon,
        backgroundColor: style.backgroundColor,
        foregroundColor: style.foregroundColor,
        borderColor: style.borderColor,
        onClose: entry.closeable
            ? () => ref.read(ideMessageProvider.notifier).dismiss(entry.id)
            : null,
      ),
    );
  }

  _IdeMessageStyle _styleFor(BuildContext context, IdeMessageType type) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme =
        Theme.of(context).extension<TolyMessageStyleTheme>() ??
        (isDark
            ? TolyMessageStyleTheme.tolyuiDark()
            : TolyMessageStyleTheme.tolyuiLight());
    final style = switch (type) {
      IdeMessageType.success => theme.successStyle,
      IdeMessageType.warning => theme.warningStyle,
      IdeMessageType.error => theme.errorStyle,
      IdeMessageType.info => theme.infoStyle,
    };
    return _IdeMessageStyle(
      icon: style.icon,
      backgroundColor: style.backgroundColor,
      foregroundColor: style.foregroundColor,
      borderColor: style.borderColor,
    );
  }
}

class _IdeMessageStyle {
  const _IdeMessageStyle({
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.borderColor,
  });

  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color borderColor;
}
