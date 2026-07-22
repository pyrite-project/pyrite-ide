import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/constants/window.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager_provider.dart';
import 'package:pyrite_ide/core/services/editor/desktop_terminal_provider.dart';
import 'package:pyrite_ide/core/services/editor/editor_controller_provider.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/local_file_items_provider.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/core/services/function_page.dart';
import 'package:pyrite_ide/shared/studio_text.dart';
import 'package:window_manager/window_manager.dart';

class UseWindow with WindowListener {
  ProviderContainer? _container;
  bool _closing = false;

  void init() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      WidgetsFlutterBinding.ensureInitialized();
      await windowManager.ensureInitialized();
      await windowManager.setPreventClose(true);
      windowManager.addListener(this);
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    }
  }

  void bind(ProviderContainer container) {
    _container = container;
  }

  @override
  void onWindowClose() async {
    if (_closing) return;
    _closing = true;

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

  Future<void> _closeDesktopTerminals() async {
    try {
      await _container
          ?.read(desktopTerminalProvider.notifier)
          .closeAll()
          .timeout(const Duration(seconds: 1));
    } catch (_) {}
  }

  Future<void> _stopPlugins() async {
    try {
      await _container
          ?.read(pluginRunManagerProvider.notifier)
          .stopAllForShutdown()
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
  }
}

class UseTitleBar extends StatelessWidget {
  const UseTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    final double titleBarHeight = Platform.isMacOS ? 36 : 45;
    final double leftPadding = Platform.isMacOS ? 80 : 22;
    final double appIconSize = Platform.isMacOS ? 14 : 28;
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
            MenuItemButton(
              onPressed: () {},
              leadingIcon: Icon(Icons.expand),
              trailingIcon: Checkbox(
                value: ref.watch(expansionPageShow),
                onChanged: (value) =>
                    ref.read(expansionPageShow.notifier).state = !ref.read(
                      expansionPageShow,
                    ),
              ),
              child: const UseText(I18nKey.menuExpansionPanel),
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
  }) {
    return SingleActivator(
      key,
      control: !Platform.isMacOS,
      meta: Platform.isMacOS,
      shift: shift,
    );
  }
}

class WindowActionBar extends StatelessWidget {
  const WindowActionBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        IconButton(
          icon: Icon(Icons.minimize, size: 18),
          onPressed: () => windowManager.minimize(),
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
          onPressed: () => windowManager.close(),
        ),
      ],
    );
  }
}
