import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/editor/repl_input_controller.dart';
import 'package:pyrite_ide/core/services/editor/terminal.dart';
import 'package:pyrite_ide/core/services/output/ide_output_log.dart';
import 'package:pyrite_ide/core/services/serial/active_device_provider.dart';
import 'package:pyrite_ide/core/services/serial/serial_provider.dart';
import 'package:pyrite_ide/core/services/serial/web_repl_provider.dart';
import 'package:pyrite_ide/features/function_page/repl_surface.dart';

/// The action row a console surface shows above its own content.
///
/// The console and the editor are the same kind of tab strip, so a surface's
/// buttons belong to that surface rather than to the strip: they travel with
/// the tab when it is dragged into an editor group, and the strip keeps its
/// corner for the panel-level controls.
class ConsoleSurfaceActions extends ConsumerWidget {
  const ConsoleSurfaceActions({super.key, required this.actions});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (actions.isEmpty) return const SizedBox.shrink();
    final compact = ref.watch(themeStyle) == ThemeStyle.compact;
    return Container(
      height: compact ? 26 : 30,
      padding: const EdgeInsets.only(right: 4),
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [for (final action in actions) _actionSlot(action, compact)],
      ),
    );
  }

  /// Matches the button footprint the strip's trailing area used, so the row
  /// keeps its size at every density tier.
  Widget _actionSlot(Widget child, bool compact) {
    return SizedBox.square(
      dimension: compact ? 26 : 30,
      child: IconButtonTheme(
        data: IconButtonThemeData(
          style: ButtonStyle(
            iconSize: WidgetStatePropertyAll(compact ? 15 : 17),
            padding: WidgetStatePropertyAll(EdgeInsets.zero),
            minimumSize: WidgetStatePropertyAll(Size.square(compact ? 26 : 30)),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        child: child,
      ),
    );
  }
}

/// The REPL surface's own actions: connect, clear, interrupt and reboot.
class ReplSurfaceActions extends ConsumerWidget {
  const ReplSurfaceActions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isConnected = ref.watch(deviceConnectedProvider);
    final webReplState = ref.watch(webReplProvider);
    final useWebRepl =
        webReplState.state == WebReplState.connected ||
        webReplState.state == WebReplState.waitingPassword;
    return ConsoleSurfaceActions(
      actions: [
        if (!isConnected && !useWebRepl)
          IconButton(
            tooltip: translateForWidget(ref, I18nKey.bottomPanelConnectWebRepl),
            onPressed: () {
              ref.read(webReplProvider.notifier).connect();
            },
            icon: const Icon(Icons.wifi),
          ),
        IconButton(
          tooltip: translateForWidget(ref, I18nKey.bottomPanelClearTerminal),
          onPressed: () {
            replController.clearSelection();
            repl.clear();
            replClearSink?.call();
            final input = ref.read(replInputControllerProvider);
            if (replClearSink == null) {
              if (input.mode == ReplInteractionMode.prompt) {
                repl.write('>>> ');
              } else if (input.mode == ReplInteractionMode.continuation) {
                repl.write('... ');
              }
            }
          },
          icon: const Icon(Icons.cleaning_services_outlined),
        ),
        IconButton(
          tooltip: useWebRepl
              ? translateForWidget(ref, I18nKey.editorToolbarInterruptDevice)
              : translateForWidget(
                  ref,
                  isConnected
                      ? I18nKey.editorToolbarInterruptDevice
                      : I18nKey.editorToolbarInterruptNeedsDevice,
                ),
          onPressed: (useWebRepl || isConnected)
              ? () {
                  if (useWebRepl) {
                    ref.read(webReplProvider.notifier).sendCommand("\x03");
                  } else {
                    ref.read(serialProvider.notifier).sendCommand("\x03");
                  }
                }
              : null,
          icon: const Icon(Icons.stop_circle_outlined),
        ),
        IconButton(
          tooltip: useWebRepl
              ? translateForWidget(ref, I18nKey.editorToolbarSoftReboot)
              : translateForWidget(
                  ref,
                  isConnected
                      ? I18nKey.editorToolbarSoftReboot
                      : I18nKey.editorToolbarSoftRebootNeedsDevice,
                ),
          onPressed: (useWebRepl || isConnected)
              ? () {
                  if (useWebRepl) {
                    ref.read(webReplProvider.notifier).sendCommand("\x04");
                  } else {
                    ref.read(serialProvider.notifier).sendCommand("\x04");
                  }
                }
              : null,
          icon: const Icon(Icons.restart_alt),
        ),
      ],
    );
  }
}

/// The output log surface's own action: clear the log.
class LogSurfaceActions extends ConsumerWidget {
  const LogSurfaceActions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ConsoleSurfaceActions(
      actions: [
        IconButton(
          tooltip: translateForWidget(ref, I18nKey.bottomPanelClearOutput),
          onPressed: () => ref.read(ideOutputLogProvider.notifier).clear(),
          icon: const Icon(Icons.cleaning_services_outlined),
        ),
      ],
    );
  }
}
