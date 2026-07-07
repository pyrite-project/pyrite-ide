import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_context_menu/super_context_menu.dart';
import 'package:super_context_menu/src/scaffold/desktop/menu_widget_builder.dart';

import 'package:pyrite_ide/core/services/settings.dart';

class PyriteContextMenuWidget extends ConsumerWidget {
  const PyriteContextMenuWidget({
    super.key,
    required this.child,
    required this.menuProvider,
    this.hitTestBehavior = HitTestBehavior.deferToChild,
    this.contextMenuIsAllowed,
    this.iconTheme,
  });

  final Widget child;
  final MenuProvider menuProvider;
  final HitTestBehavior hitTestBehavior;
  final ContextMenuIsAllowed? contextMenuIsAllowed;
  final IconThemeData? iconTheme;

  static final _md3DesktopBuilder = _PyriteMd3DesktopMenuWidgetBuilder();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final useMaterialMenu = ref.watch(useMaterialContextMenu);
    return ContextMenuWidget(
      hitTestBehavior: hitTestBehavior,
      contextMenuIsAllowed: contextMenuIsAllowed ?? (_) => true,
      iconTheme: iconTheme,
      menuProvider: menuProvider,
      desktopMenuWidgetBuilder: useMaterialMenu ? _md3DesktopBuilder : null,
      child: child,
    );
  }
}

class _PyriteMd3DesktopMenuWidgetBuilder extends DesktopMenuWidgetBuilder {
  static const double _radius = 8;
  static const double _itemRadius = 6;

  @override
  Widget buildMenuContainer(
    BuildContext context,
    DesktopMenuInfo menuInfo,
    Widget child,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(
              Theme.of(context).brightness == Brightness.dark ? 90 : 38,
            ),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_radius),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 160, maxWidth: 320),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: DefaultTextStyle(
              style: Theme.of(context).textTheme.bodySmall!.copyWith(
                color: scheme.onSurface,
                decoration: TextDecoration.none,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget buildSeparator(
    BuildContext context,
    DesktopMenuInfo menuInfo,
    MenuSeparator separator,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Divider(
        height: 1,
        thickness: 1,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }

  @override
  Widget buildMenuItem(
    BuildContext context,
    DesktopMenuInfo menuInfo,
    Key innerKey,
    DesktopMenuButtonState state,
    MenuElement element,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final disabled = element is MenuAction && element.attributes.disabled;
    final destructive = element is MenuAction && element.attributes.destructive;
    final selected = state.selected && menuInfo.focused;
    final baseTextStyle = Theme.of(context).textTheme.bodySmall!;
    final foreground = disabled
        ? scheme.onSurface.withAlpha(97)
        : destructive
        ? scheme.error
        : selected
        ? scheme.onSecondaryContainer
        : scheme.onSurface;
    final iconTheme = menuInfo.iconTheme.copyWith(size: 16, color: foreground);
    final image = element.image?.asWidget(iconTheme);
    final stateIcon = element is MenuAction ? _stateIcon(element.state) : null;
    final submenu = element is Menu;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      child: Container(
        key: innerKey,
        constraints: const BoxConstraints(minHeight: 30),
        padding: const EdgeInsetsDirectional.only(
          start: 8,
          end: 7,
          top: 4,
          bottom: 4,
        ),
        decoration: BoxDecoration(
          color: selected ? scheme.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(_itemRadius),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              child: stateIcon == null
                  ? image
                  : Icon(stateIcon, size: 16, color: foreground),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                element.title ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: baseTextStyle.copyWith(
                  color: foreground,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            if (submenu) Icon(Icons.chevron_right, size: 16, color: foreground),
          ],
        ),
      ),
    );
  }

  IconData? _stateIcon(MenuActionState state) {
    return switch (state) {
      MenuActionState.none => null,
      MenuActionState.checkOn => Icons.check,
      MenuActionState.checkOff => null,
      MenuActionState.checkMixed => Icons.remove,
      MenuActionState.radioOn => Icons.radio_button_checked,
      MenuActionState.radioOff => Icons.radio_button_unchecked,
    };
  }
}
