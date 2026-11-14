import 'dart:async';
import 'dart:io';

import 'package:code_forge/code_forge.dart' show editorModifierKeys;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/constants/theme_density.dart';
import 'package:pyrite_ide/core/constants/window.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/models/pane_edge.dart';
import 'package:pyrite_ide/core/models/window_placement.dart';
import 'package:pyrite_ide/core/sdk/activation_manager.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/data_registry.dart';
import 'package:pyrite_ide/core/services/editor/desktop_terminal_provider.dart';
import 'package:pyrite_ide/core/services/editor/editor_controller_provider.dart';
import 'package:pyrite_ide/core/services/editor/editor_layout_commands.dart';
import 'package:pyrite_ide/core/services/editor/editor_split.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/core/services/file/local_tree.dart';
import 'package:pyrite_ide/core/services/function_page.dart';
import 'package:pyrite_ide/core/services/message/ide_message.dart';
import 'package:pyrite_ide/core/services/persistence/app_persistence.dart';
import 'package:pyrite_ide/core/services/window_placement.dart';
import 'package:pyrite_ide/features/command_palette/command_palette.dart';
import 'package:pyrite_ide/features/command_palette/editor_palette_hooks.dart';
import 'package:pyrite_ide/features/command_palette/palette_entry.dart';
import 'package:pyrite_ide/features/function_page/console_tabs.dart';
import 'package:pyrite_ide/shared/studio_text.dart';
import 'package:pyrite_ide/shared/tabbed_view/unsaved_tab_guard.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:tabbed_view/tabbed_view.dart';
import 'package:window_manager/window_manager.dart';

class UseWindow with WindowListener {
  ProviderContainer? _container;
  bool _closing = false;

  /// Guards the unsaved-changes prompt against a second close request
  /// arriving while the first one is still showing its dialog.
  bool _confirmingUnsaved = false;

  /// Smallest window the shell accepts.
  ///
  /// Set to the smallest phone target rather than a desktop comfort floor: the
  /// app has a phone layout, and being able to resize a desktop window down to
  /// 320x480 is how that layout gets exercised without a device.
  static const Size _minimumWindowSize = Size(320, 480);

  /// The normal (unmaximized) bounds, kept even while the window is maximized
  /// so restoring a maximized session does not later restore to the maximized
  /// size as its "normal" size.
  Rect? _lastNormalBounds;
  Timer? _placementCaptureTimer;

  void init() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      WidgetsFlutterBinding.ensureInitialized();
      await windowManager.ensureInitialized();
      await windowManager.setPreventClose(true);
      await windowManager.setAlwaysOnTop(
        _container?.read(alwaysOnTopProvider) ?? false,
      );
      // window_manager's focus callbacks only exist on macOS and Linux; the
      // Windows embedder never handles WM_ACTIVATE, so `onWindowFocus` below
      // is dead code there. Handing the editor a real focus probe is what
      // actually recovers a modifier held across an Alt+Tab on Windows.
      editorModifierKeys.windowFocusProbe = windowManager.isFocused;
      windowManager.addListener(this);
      final restored = await _restoredPlacement();
      try {
        await windowManager.setMinimumSize(_minimumWindowSize);
      } catch (error) {
        debugPrint('[window] could not set minimum size: $error');
      }
      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        if (restored != null) {
          try {
            await windowManager.setBounds(restored.bounds);
            _lastNormalBounds = restored.bounds;
          } catch (error) {
            debugPrint('[window] could not restore bounds: $error');
          }
        }
        await windowManager.show();
        await windowManager.focus();
        if (restored?.maximized == true) {
          try {
            await windowManager.maximize();
          } catch (error) {
            debugPrint('[window] could not restore maximized state: $error');
          }
        }
      });
    }
  }

  /// Validates the persisted placement against the displays that exist now.
  ///
  /// A monitor that was disconnected since the last run must not leave the
  /// window off-screen, and a bad file must not prevent the app from opening.
  Future<WindowPlacement?> _restoredPlacement() async {
    final stored = _container?.read(windowPlacementProvider);
    if (stored == null) return null;
    try {
      final displays = await screenRetriever.getAllDisplays();
      final areas = <Rect>[
        for (final display in displays)
          Rect.fromLTWH(
            (display.visiblePosition ?? Offset.zero).dx,
            (display.visiblePosition ?? Offset.zero).dy,
            (display.visibleSize ?? display.size).width,
            (display.visibleSize ?? display.size).height,
          ),
      ];
      return stored.clampToVisibleAreas(areas);
    } catch (error) {
      debugPrint('[window] could not read displays, centering: $error');
      return null;
    }
  }

  void bind(ProviderContainer container) {
    _container = container;
  }

  @override
  void onWindowClose() async {
    if (_closing) return;

    // The unsaved-changes prompt is a courtesy, not a gate. If it fails for
    // any reason -- no Navigator to push onto, a provider that throws while
    // being read -- the window must still close. Reporting a close request and
    // then doing nothing leaves the user with an app they cannot quit, which is
    // strictly worse than losing a buffer they were warned about.
    var mayClose = true;
    try {
      mayClose = await _confirmDiscardUnsavedTabs();
    } catch (error) {
      debugPrint(
        '[window] unsaved-changes prompt failed, closing anyway: $error',
      );
    }
    if (!mayClose) return;
    _closing = true;
    _placementCaptureTimer?.cancel();
    await _captureWindowPlacement(force: true);
    await _persistWindowPlacement();

    try {
      await Future.wait([
        _closeDesktopTerminals(),
        _stopPlugins(),
      ]).timeout(const Duration(seconds: 2));
    } catch (_) {
    } finally {
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
      exit(0);
    }
  }

  /// Offers to write out dirty editors before the window goes away.
  ///
  /// Returns false when the user cancels, in which case closing is abandoned
  /// and the next close request starts over. `onWindowClose` runs without a
  /// BuildContext of its own, so the dialog rides on [appContext], which the
  /// app shell installs at startup.
  Future<bool> _confirmDiscardUnsavedTabs() async {
    final container = _container;
    final context = appContext;
    if (container == null || context == null || !context.mounted) return true;
    if (_confirmingUnsaved) return false;

    final unsaved = _collectUnsavedTabs(container);
    if (unsaved.isEmpty) return true;

    _confirmingUnsaved = true;
    try {
      return await _showUnsavedExitDialog(container, context, unsaved);
    } finally {
      _confirmingUnsaved = false;
    }
  }

  Future<bool> _showUnsavedExitDialog(
    ProviderContainer container,
    BuildContext context,
    List<TabData> unsaved,
  ) async {
    final registry = container.read(dataRegistryProvider);
    final locale = container.read(activeLocaleProvider);
    String tr(I18nKey key, [Map<String, String> replacements = const {}]) {
      var value = translateFromRegistry(registry, locale, key);
      for (final entry in replacements.entries) {
        value = value.replaceAll('{${entry.key}}', entry.value);
      }
      return value;
    }

    final choice = await showDialog<_ExitChoice>(
      context: context,
      // A close request must not slip through on a barrier tap.
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr(I18nKey.appExitUnsavedTitle)),
        content: Text(
          tr(I18nKey.appExitUnsavedContent, {'count': '${unsaved.length}'}),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () =>
                Navigator.of(dialogContext).pop(_ExitChoice.discard),
            child: Text(tr(I18nKey.appExitUnsavedDiscardAll)),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_ExitChoice.saveAll),
            child: Text(tr(I18nKey.appExitUnsavedSaveAll)),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_ExitChoice.cancel),
            child: Text(tr(I18nKey.tabUnsavedDialogCancel)),
          ),
        ],
      ),
    );

    switch (choice) {
      case _ExitChoice.saveAll:
        final notifier = container.read(fileProvider.notifier);
        for (final tab in unsaved) {
          // One unreadable file must not strand the rest of the saves, and it
          // must not keep the window open either -- the buffer is already
          // persisted for the next session.
          try {
            await notifier.saveTab(tab);
          } catch (error) {
            debugPrint('[lib/features/window.dart] ignored error: $error');
          }
        }
        container
            .read(ideMessageProvider.notifier)
            .success(tr(I18nKey.tabSavedCurrentFile));
        return true;
      case _ExitChoice.discard:
        return true;
      case _ExitChoice.cancel:
      case null:
        return false;
    }
  }

  List<TabData> _collectUnsavedTabs(ProviderContainer container) {
    final tabs = <TabData>[
      for (final controller in allEditorControllers(container))
        ...controller.tabs,
    ];
    return tabs.where(isTabUnsaved).toList();
  }

  @override
  void onWindowFocus() {
    // A modifier held while the window lost focus never produces a key-up,
    // which leaves the framework key cache claiming Alt is still down.
    // Re-read the engine's view before the user can click. Only macOS and
    // Linux reach here; Windows relies on `windowFocusProbe` instead, which
    // this class supplies in `init`.
    editorModifierKeys.onWindowFocus();
    // Focus is when a file this window had open is most likely to have been
    // changed elsewhere: a git checkout, another editor, or a command line
    // tool. Reconcile before the user can type over it or save past it.
    unawaited(_checkExternalFileChanges());
  }

  Future<void> _checkExternalFileChanges() async {
    final container = _container;
    final context = appContext;
    if (container == null || context == null || !context.mounted) return;
    try {
      await container
          .read(tabbedViewControllerProvider.notifier)
          .checkExternalChanges(context);
    } catch (error) {
      debugPrint('[window] external file check failed: $error');
    }
  }

  @override
  void onWindowBlur() {
    editorModifierKeys.onWindowBlur();
  }

  @override
  void onWindowResize() => _schedulePlacementCapture();

  @override
  void onWindowResized() => _schedulePlacementCapture();

  @override
  void onWindowMove() => _schedulePlacementCapture();

  @override
  void onWindowMoved() => _schedulePlacementCapture();

  @override
  void onWindowMaximize() {
    final container = _container;
    if (container == null) return;
    final bounds =
        container.read(windowPlacementProvider)?.bounds ?? _lastNormalBounds;
    if (bounds == null) return;
    container.read(windowPlacementProvider.notifier).state = WindowPlacement(
      bounds: bounds,
      maximized: true,
    );
  }

  @override
  void onWindowUnmaximize() {
    final container = _container;
    if (container == null) return;
    final current = container.read(windowPlacementProvider);
    if (current != null) {
      container.read(windowPlacementProvider.notifier).state = WindowPlacement(
        bounds: current.bounds,
        maximized: false,
      );
    }
    _schedulePlacementCapture();
  }

  /// Debounces the resize/move burst a window drag produces.
  void _schedulePlacementCapture() {
    if (_closing) return;
    _placementCaptureTimer?.cancel();
    _placementCaptureTimer = Timer(const Duration(milliseconds: 300), () {
      unawaited(_captureWindowPlacement());
    });
  }

  /// Records the current normal bounds in memory.
  ///
  /// While maximized the window manager reports the maximized rectangle, which
  /// must not replace the normal bounds the user would return to.
  Future<void> _captureWindowPlacement({bool force = false}) async {
    final container = _container;
    if (container == null) return;
    try {
      if (!force && await windowManager.isMaximized()) return;
      final bounds = await windowManager.getBounds();
      if (bounds.width < 200 || bounds.height < 200) return;
      if (await windowManager.isMaximized()) return;
      _lastNormalBounds = bounds;
      container.read(windowPlacementProvider.notifier).state = WindowPlacement(
        bounds: bounds,
        maximized: false,
      );
    } catch (error) {
      debugPrint('[window] could not capture bounds: $error');
    }
  }

  /// Writes the placement into `app.json` without rewriting unrelated data.
  Future<void> _persistWindowPlacement() async {
    final placement = _container?.read(windowPlacementProvider);
    if (placement == null) return;
    try {
      await AppPersistence().patch({'window': placement.toJson()});
    } catch (error) {
      debugPrint('[window] could not persist bounds: $error');
    }
  }

  Future<void> _closeDesktopTerminals() async {
    try {
      await _container
          ?.read(desktopTerminalProvider.notifier)
          .closeAll()
          .timeout(const Duration(seconds: 1));
    } catch (error) {
      debugPrint('[lib/features/window.dart] ignored error: $error');
    }
  }

  Future<void> _stopPlugins() async {
    try {
      // Goes through the ActivationManager so in-flight activations settle
      // before the runtime is torn down.
      await _container
          ?.read(activationManagerProvider.notifier)
          .deactivateAllForShutdown()
          .timeout(const Duration(seconds: 2));
    } catch (error) {
      debugPrint('[lib/features/window.dart] ignored error: $error');
    }
  }
}

enum _ExitChoice { discard, saveAll, cancel }

class UseTitleBar extends ConsumerWidget {
  const UseTitleBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final double titleBarHeight = Platform.isMacOS ? 36 : 45;
    final double appIconSize = Platform.isMacOS ? 14 : 28;
    final double leftPadding = Platform.isMacOS
        ? 80
        : ThemeDensityTokens.forStyle(ref.watch(themeStyle)).navRailWidth / 2 -
              appIconSize / 2;
    return GestureDetector(
      onPanStart: (details) => windowManager.startDragging(),
      child: Container(
        padding: EdgeInsets.only(left: leftPadding, right: 8),
        color: Theme.of(context).colorScheme.surface,
        height: titleBarHeight,
        child: Row(
          children: [
            Image.asset(
              "assets/icons/app_icon.webp",
              width: appIconSize,
              height: appIconSize,
            ),
            SizedBox(width: 20),
            if (!Platform.isMacOS) AppActionBar(),
            Expanded(child: Platform.isMacOS ? SizedBox() : WindowActionBar()),
          ],
        ),
      ),
    );
  }
}

class AppActionBar extends ConsumerWidget {
  const AppActionBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MenuBar(
      style: MenuStyle(
        backgroundColor: WidgetStateProperty.all(
          Theme.of(context).colorScheme.surface,
        ),
        elevation: WidgetStateProperty.all(0),
      ),
      children: [
        SubmenuButton(
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.all(
              Theme.of(context).colorScheme.surface,
            ),
            overlayColor: WidgetStateProperty.all(
              Theme.of(context).colorScheme.surface,
            ),
          ),
          alignmentOffset: Offset(0, 5),
          menuStyle: MenuStyle(
            minimumSize: WidgetStatePropertyAll(Size(180, 0)),
          ),
          menuChildren: [
            buildMenuItemButton(
              context,
              I18nKey.menuNewFile,
              () =>
                  ref.read(tabbedViewControllerProvider.notifier).createFile(),
              leadingIconData: Icons.add,
              shortcut: platformShortcut(LogicalKeyboardKey.keyN),
            ),
            buildMenuItemButton(
              context,
              I18nKey.menuOpenFile,
              () => ref
                  .read(tabbedViewControllerProvider.notifier)
                  .openFile(context),
              leadingIconData: Icons.open_in_browser,
              shortcut: platformShortcut(LogicalKeyboardKey.keyO),
            ),
            buildMenuItemButton(
              context,
              I18nKey.menuOpenFolder,
              () => ref.read(localFileItemsProvider.notifier).openFolder(),
              leadingIconData: Icons.folder_open,
            ),
            PopupMenuDivider(),
            buildMenuItemButton(
              context,
              I18nKey.menuSaveCurrentFile,
              () => ref.read(fileProvider.notifier).saveCurrentFile(),
              leadingIconData: Icons.save,
              shortcut: platformShortcut(LogicalKeyboardKey.keyS),
            ),
            buildMenuItemButton(
              context,
              I18nKey.menuSaveCurrentFileAs,
              () => ref.read(fileProvider.notifier).saveCurrentFileAs(),
              leadingIconData: Icons.save_as,
              shortcut: platformShortcut(LogicalKeyboardKey.keyS, shift: true),
            ),
            PopupMenuDivider(),
            buildMenuItemButton(
              context,
              I18nKey.menuReopenClosedTab,
              () => reopenClosedEditorTab(context, ref),
              leadingIconData: Icons.restore,
              shortcut: platformShortcut(LogicalKeyboardKey.keyT, shift: true),
            ),
            PopupMenuDivider(),
            buildMenuItemButton(
              context,
              I18nKey.menuCommandPalette,
              () => showCommandPalette(context, hooks: editorPaletteHooks()),
              leadingIconData: Icons.terminal,
              shortcut: platformShortcut(LogicalKeyboardKey.keyP, shift: true),
            ),
            buildMenuItemButton(
              context,
              I18nKey.menuQuickOpen,
              () => showCommandPalette(
                context,
                mode: PaletteLaunchMode.files,
                hooks: editorPaletteHooks(),
              ),
              leadingIconData: Icons.search,
              shortcut: platformShortcut(LogicalKeyboardKey.keyP),
            ),
          ],
          child: const UseText(I18nKey.menuFile),
        ),
        SubmenuButton(
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.all(
              Theme.of(context).colorScheme.surface,
            ),
            overlayColor: WidgetStateProperty.all(
              Theme.of(context).colorScheme.surface,
            ),
          ),
          alignmentOffset: Offset(0, 5),
          menuChildren: [
            buildMenuItemButton(
              context,
              I18nKey.menuCut,
              ref.read(editorControllerMapProvider.notifier).cut,
              leadingIconData: Icons.cut,
              shortcut: platformShortcut(LogicalKeyboardKey.keyX),
            ),
            buildMenuItemButton(
              context,
              I18nKey.menuCopy,
              ref.read(editorControllerMapProvider.notifier).copy,
              leadingIconData: Icons.copy,
              shortcut: platformShortcut(LogicalKeyboardKey.keyC),
            ),
            buildMenuItemButton(
              context,
              I18nKey.menuPaste,
              ref.read(editorControllerMapProvider.notifier).paste,
              leadingIconData: Icons.paste,
              shortcut: platformShortcut(LogicalKeyboardKey.keyV),
            ),
          ],
          child: const UseText(I18nKey.menuEdit),
        ),
        SubmenuButton(
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.all(
              Theme.of(context).colorScheme.surface,
            ),
            overlayColor: WidgetStateProperty.all(
              Theme.of(context).colorScheme.surface,
            ),
          ),
          alignmentOffset: Offset(0, 5),
          menuChildren: [
            MenuItemButton(
              onPressed: () {},
              leadingIcon: Icon(Icons.functions),
              trailingIcon: Checkbox(
                value: ref.watch(functionPageShow),
                onChanged: (value) =>
                    ref.read(functionPageShow.notifier).state = !ref.read(
                      functionPageShow,
                    ),
              ),
              child: const UseText(I18nKey.menuFunctionPanel),
            ),
            MenuItemButton(
              onPressed: () {},
              leadingIcon: Icon(Icons.control_camera),
              trailingIcon: Checkbox(
                value: ref.watch(consolePageShow),
                onChanged: (value) => ref.read(consolePageShow.notifier).state =
                    !ref.read(consolePageShow),
              ),
              child: const UseText(I18nKey.menuConsolePanel),
            ),
            // Always reachable, unlike the console tab's own menu: once every
            // surface was dragged out, the panel and its strip are gone.
            MenuItemButton(
              onPressed: () =>
                  resetTerminalLayout(ProviderScope.containerOf(context)),
              leadingIcon: const Icon(Icons.settings_backup_restore),
              child: const UseText(I18nKey.consoleResetLayout),
            ),
            PopupMenuDivider(),
            buildMenuItemButton(
              context,
              I18nKey.menuSplitRight,
              () => splitActiveEditor(ref, PaneEdge.right),
              leadingIconData: Icons.vertical_split,
              shortcut: platformShortcut(LogicalKeyboardKey.backslash),
            ),
            buildMenuItemButton(
              context,
              I18nKey.menuSplitDown,
              () => splitActiveEditor(ref, PaneEdge.bottom),
              leadingIconData: Icons.horizontal_split,
              shortcut: platformShortcut(
                LogicalKeyboardKey.backslash,
                shift: true,
              ),
            ),
            buildMenuItemButton(
              context,
              I18nKey.menuCloseGroup,
              () => closeActiveEditorGroup(context, ref),
              leadingIconData: Icons.close_fullscreen,
              shortcut: platformShortcut(LogicalKeyboardKey.keyW, alt: true),
            ),
            buildMenuItemButton(
              context,
              I18nKey.menuResetEditorLayout,
              () => resetEditorLayout(ref),
              leadingIconData: Icons.restart_alt,
            ),
          ],
          child: const UseText(I18nKey.menuView),
        ),
      ],
    );
  }

  Widget buildMenuItemButton(
    BuildContext context,
    Object text,
    Function()? onPressed, {
    IconData? leadingIconData,
    IconData? trailingIconData,
    SingleActivator? shortcut,
    Widget? trailing,
  }) {
    return MenuItemButton(
      onPressed: onPressed,
      leadingIcon: (leadingIconData != null)
          ? Icon(leadingIconData, size: 18)
          : SizedBox(width: 18),
      trailingIcon: (trailingIconData != null)
          ? Icon(trailingIconData, size: 18)
          : SizedBox(width: 18),
      style: ButtonStyle(),
      shortcut: shortcut,
      child: UseText(text),
    );
  }

  SingleActivator platformShortcut(
    LogicalKeyboardKey key, {
    bool shift = false,
    bool alt = false,
  }) {
    return SingleActivator(
      key,
      control: !Platform.isMacOS,
      meta: Platform.isMacOS,
      shift: shift,
      alt: alt,
    );
  }
}

class WindowActionBar extends ConsumerWidget {
  const WindowActionBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        IconButton(
          icon: (ref.watch(alwaysOnTopProvider))
              ? Icon(Icons.push_pin, size: 18)
              : Icon(Icons.push_pin_outlined, size: 18),
          onPressed: () async {
            ref.read(alwaysOnTopProvider.notifier).state = !ref.read(
              alwaysOnTopProvider,
            );
            await windowManager.setAlwaysOnTop(ref.read(alwaysOnTopProvider));
          },
        ),
        IconButton(
          icon: Icon(Icons.minimize, size: 18),
          onPressed: windowManager.minimize,
        ),
        FutureBuilder<bool>(
          future: windowManager.isMaximized(),
          builder: (context, snapshot) {
            return IconButton(
              icon: Icon(
                snapshot.data == true ? Icons.filter_none : Icons.crop_square,
                size: 20,
              ),
              onPressed: () async {
                if (await windowManager.isMaximized()) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
            );
          },
        ),
        IconButton(
          hoverColor: Theme.of(
            context,
          ).colorScheme.error.withValues(alpha: 0.3),
          icon: Icon(Icons.close, size: 20),
          onPressed: windowManager.close,
        ),
      ],
    );
  }
}
