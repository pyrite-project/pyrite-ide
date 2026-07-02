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

  final Map<String, Timer> _timers = {};
  int _nextId = 0;

  void show(
    String message, {
    IdeMessageType type = IdeMessageType.info,
    Duration duration = const Duration(seconds: 3),
    bool closeable = false,
  }) {
    if (message.isEmpty) return;
    final id = 'ide_message_${_nextId++}';
    final entry = IdeMessageEntry(
      id: id,
      type: type,
      message: message,
      duration: duration,
      closeable: closeable,
    );
    state = [...state, entry];
    _timers[id] = Timer(duration, () => dismiss(id));
  }

  void info(String message) => show(message);

  void success(String message) => show(message, type: IdeMessageType.success);

  void warning(String message) => show(message, type: IdeMessageType.warning);

  void error(String message) => show(message, type: IdeMessageType.error);

  void dismiss(String id) {
    _timers.remove(id)?.cancel();
    state = [for (final entry in state) if (entry.id != id) entry];
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
}) {
  ProviderScope.containerOf(context, listen: false)
      .read(ideMessageProvider.notifier)
      .show(message, type: type);
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
    final theme = Theme.of(context).extension<TolyMessageStyleTheme>() ??
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
