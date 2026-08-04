import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pyrite_ide/features/plugin_view/plugin_icons.dart';
import 'package:pyrite_ide/shared/pyrite_context_menu.dart';
import 'package:super_context_menu/super_context_menu.dart' as scm;

typedef PluginMenuEventSink = void Function(Map<String, dynamic> payload);

class PluginMenuBarController {
  final Map<String, MenuController> _menus = {};

  void bind(String id, MenuController controller) => _menus[id] = controller;

  bool openMenu(String id) {
    final controller = _menus[id];
    if (controller == null) return false;
    for (final other in _menus.values) {
      if (!identical(other, controller) && other.isOpen) other.close();
    }
    controller.open();
    return true;
  }

  void close() {
    for (final controller in _menus.values) {
      if (controller.isOpen) controller.close();
    }
  }

  bool get isOpen => _menus.values.any((controller) => controller.isOpen);
}

class PluginPopupController {
  bool isOpen = false;
  String? selectedId;
}

List<Map<String, dynamic>> pluginMenuEntries(Object? raw) => raw is List
    ? [
        for (final entry in raw)
          if (entry is Map)
            entry.map((key, value) => MapEntry(key.toString(), value)),
      ]
    : const [];

class PluginMenuButton extends StatelessWidget {
  const PluginMenuButton({
    super.key,
    required this.items,
    required this.onSelected,
    this.label,
    this.icon,
    this.tooltip,
    this.enabled = true,
    this.alignment = 'bottomStart',
    this.offsetX = 0,
    this.offsetY = 0,
    this.useRootOverlay = true,
    this.trigger,
    this.iconOnly = false,
    this.controller,
  });

  final List<Map<String, dynamic>> items;
  final PluginMenuEventSink onSelected;
  final String? label;
  final String? icon;
  final String? tooltip;
  final bool enabled;
  final String alignment;
  final double offsetX;
  final double offsetY;
  final bool useRootOverlay;
  final Widget? trigger;
  final bool iconOnly;
  final MenuController? controller;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      controller: controller,
      useRootOverlay: useRootOverlay,
      alignmentOffset: Offset(offsetX, offsetY),
      style: MenuStyle(alignment: _menuAlignment(alignment)),
      menuChildren: buildPluginMenuChildren(context, items, onSelected),
      builder: (context, controller, _) {
        void toggle() {
          if (!enabled) return;
          controller.isOpen ? controller.close() : controller.open();
        }

        if (trigger != null) {
          return Semantics(
            button: true,
            enabled: enabled,
            label: tooltip ?? label,
            child: InkWell(onTap: enabled ? toggle : null, child: trigger),
          );
        }
        if (iconOnly || (icon != null && (label == null || label!.isEmpty))) {
          return IconButton(
            icon: Icon(pluginIcon(icon ?? 'material:more_vert'), size: 18),
            tooltip: tooltip ?? label,
            visualDensity: VisualDensity.compact,
            onPressed: enabled ? toggle : null,
          );
        }
        final text = Text(label ?? '');
        final leading = icon == null ? null : Icon(pluginIcon(icon), size: 16);
        return leading == null
            ? TextButton.icon(
                onPressed: enabled ? toggle : null,
                icon: const SizedBox.shrink(),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [text, const Icon(Icons.expand_more, size: 16)],
                ),
              )
            : TextButton.icon(
                onPressed: enabled ? toggle : null,
                icon: leading,
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [text, const Icon(Icons.expand_more, size: 16)],
                ),
              );
      },
    );
  }
}

class PluginMenuBar extends StatelessWidget {
  const PluginMenuBar({
    super.key,
    required this.items,
    required this.onSelected,
    this.controller,
  });

  final List<Map<String, dynamic>> items;
  final PluginMenuEventSink onSelected;
  final PluginMenuBarController? controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final item in items)
          if (_visible(item) && _kind(item) != 'divider')
            if (_kind(item) == 'submenu')
              Builder(
                builder: (context) {
                  final id =
                      item['id']?.toString() ?? item['label']?.toString() ?? '';
                  final menuController = MenuController();
                  controller?.bind(id, menuController);
                  return PluginMenuButton(
                    controller: menuController,
                    items: pluginMenuEntries(item['children']),
                    label: item['label']?.toString(),
                    icon: item['icon']?.toString(),
                    enabled: item['enabled'] != false,
                    onSelected: onSelected,
                  );
                },
              )
            else
              TextButton(
                onPressed: item['enabled'] == false
                    ? null
                    : () => onSelected(_eventFor(item, _kind(item))),
                child: Text(item['label']?.toString() ?? ''),
              ),
      ],
    );
  }
}

Widget buildPluginContextMenu({
  required Widget child,
  required List<Map<String, dynamic>> items,
  required PluginMenuEventSink onSelected,
  bool enabled = true,
}) {
  return PyriteContextMenuWidget(
    contextMenuIsAllowed: (_) => enabled,
    menuProvider: (_) => _buildContextMenu(items, onSelected),
    child: child,
  );
}

Widget buildDynamicPluginContextMenu({
  required Widget child,
  required Future<Map<String, dynamic>?> Function() menuProvider,
  required void Function(String componentId, Map<String, dynamic> payload)
  onSelected,
  required String targetId,
  required String targetType,
}) {
  return PyriteContextMenuWidget(
    menuProvider: (_) async {
      final component = await menuProvider();
      if (component == null || component['type'] != 'ContextMenu') return null;
      final rawProps = component['props'];
      if (rawProps is! Map) return null;
      final props = rawProps.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      if (props['enabled'] == false) return null;
      final componentId = props['id']?.toString();
      final items = pluginMenuEntries(props['items']);
      if (componentId == null || componentId.isEmpty || items.isEmpty) {
        return null;
      }
      return _buildContextMenu(items, (payload) {
        onSelected(componentId, {
          ...payload,
          'targetId': targetId,
          'targetType': targetType,
        });
      });
    },
    child: child,
  );
}

List<Widget> buildPluginMenuChildren(
  BuildContext context,
  List<Map<String, dynamic>> items,
  PluginMenuEventSink onSelected,
) => [
  for (final item in items)
    if (_visible(item)) _buildMenuEntry(context, item, onSelected),
];

Widget _buildMenuEntry(
  BuildContext context,
  Map<String, dynamic> item,
  PluginMenuEventSink onSelected,
) {
  final kind = _kind(item);
  if (kind == 'divider') {
    final label = item['label']?.toString();
    return label == null || label.isEmpty
        ? const Divider(height: 9)
        : Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 7, 12, 3),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
  }

  final enabled = item['enabled'] != false;
  final leading = _leadingIcon(item, kind);
  final trailing = item['trailingIcon'] == null
      ? null
      : Icon(pluginIcon(item['trailingIcon']?.toString()), size: 16);
  final label = Text(
    item['label']?.toString() ?? '',
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );

  if (kind == 'submenu') {
    if (!enabled) {
      return MenuItemButton(
        onPressed: null,
        leadingIcon: leading,
        trailingIcon: const Icon(Icons.chevron_right, size: 16),
        child: label,
      );
    }
    return SubmenuButton(
      leadingIcon: leading,
      trailingIcon: trailing,
      menuChildren: buildPluginMenuChildren(
        context,
        pluginMenuEntries(item['children']),
        onSelected,
      ),
      child: label,
    );
  }

  return MenuItemButton(
    onPressed: enabled ? () => onSelected(_eventFor(item, kind)) : null,
    leadingIcon: leading,
    trailingIcon: trailing,
    shortcut: pluginMenuShortcut(item['shortcut']),
    closeOnActivate: item['closeOnSelect'] != false,
    semanticsLabel: item['semanticsLabel']?.toString(),
    style: _menuItemStyle(context, item),
    child: label,
  );
}

Widget? _leadingIcon(Map<String, dynamic> item, String kind) {
  if (kind == 'checkbox') {
    return Icon(
      item['checked'] == true ? Icons.check_box : Icons.check_box_outline_blank,
      size: 16,
    );
  }
  if (kind == 'radio') {
    return Icon(
      item['selected'] == true
          ? Icons.radio_button_checked
          : Icons.radio_button_unchecked,
      size: 16,
    );
  }
  final icon = item['icon']?.toString();
  return icon == null ? null : Icon(pluginIcon(icon), size: 16);
}

ButtonStyle? _menuItemStyle(BuildContext context, Map<String, dynamic> item) {
  if (item['tone'] != 'danger') return null;
  final error = Theme.of(context).colorScheme.error;
  return ButtonStyle(
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? error.withValues(alpha: 0.38)
          : error,
    ),
  );
}

Map<String, dynamic> _eventFor(Map<String, dynamic> item, String kind) => {
  'itemId': item['id']?.toString(),
  'itemType': kind,
  if (kind == 'checkbox') 'checked': item['checked'] != true,
  if (kind == 'radio') 'selected': true,
};

scm.Menu _buildContextMenu(
  List<Map<String, dynamic>> items,
  PluginMenuEventSink onSelected,
) => scm.Menu(
  children: [
    for (final item in items)
      if (_visible(item)) _contextEntry(item, onSelected),
  ],
);

scm.MenuElement _contextEntry(
  Map<String, dynamic> item,
  PluginMenuEventSink onSelected,
) {
  final kind = _kind(item);
  if (kind == 'divider') {
    return scm.MenuSeparator(title: item['label']?.toString());
  }
  final icon = item['icon']?.toString();
  if (kind == 'submenu') {
    return scm.Menu(
      title: item['label']?.toString(),
      image: icon == null ? null : scm.MenuImage.icon(pluginIcon(icon)),
      children: [
        for (final child in pluginMenuEntries(item['children']))
          if (_visible(child)) _contextEntry(child, onSelected),
      ],
    );
  }
  return scm.MenuAction(
    title: item['label']?.toString(),
    image: icon == null ? null : scm.MenuImage.icon(pluginIcon(icon)),
    attributes: scm.MenuActionAttributes(
      disabled: item['enabled'] == false,
      destructive: item['tone'] == 'danger',
    ),
    state: switch (kind) {
      'checkbox' =>
        item['checked'] == true
            ? scm.MenuActionState.checkOn
            : scm.MenuActionState.checkOff,
      'radio' =>
        item['selected'] == true
            ? scm.MenuActionState.radioOn
            : scm.MenuActionState.radioOff,
      _ => scm.MenuActionState.none,
    },
    activator: pluginMenuShortcut(item['shortcut']),
    callback: () => onSelected(_eventFor(item, kind)),
  );
}

SingleActivator? pluginMenuShortcut(Object? raw) {
  if (raw is! Map) return null;
  final key = _logicalKey(raw['key']?.toString());
  if (key == null) return null;
  final primary = raw['primary'] == true;
  final apple =
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;
  return SingleActivator(
    key,
    control: raw['control'] == true || (primary && !apple),
    shift: raw['shift'] == true,
    alt: raw['alt'] == true,
    meta: raw['meta'] == true || (primary && apple),
    includeRepeats: false,
  );
}

LogicalKeyboardKey? _logicalKey(String? raw) {
  final key = raw?.trim().toLowerCase();
  if (key == null || key.isEmpty) return null;
  return _logicalKeys[key];
}

const _logicalKeys = <String, LogicalKeyboardKey>{
  'a': LogicalKeyboardKey.keyA,
  'b': LogicalKeyboardKey.keyB,
  'c': LogicalKeyboardKey.keyC,
  'd': LogicalKeyboardKey.keyD,
  'e': LogicalKeyboardKey.keyE,
  'f': LogicalKeyboardKey.keyF,
  'g': LogicalKeyboardKey.keyG,
  'h': LogicalKeyboardKey.keyH,
  'i': LogicalKeyboardKey.keyI,
  'j': LogicalKeyboardKey.keyJ,
  'k': LogicalKeyboardKey.keyK,
  'l': LogicalKeyboardKey.keyL,
  'm': LogicalKeyboardKey.keyM,
  'n': LogicalKeyboardKey.keyN,
  'o': LogicalKeyboardKey.keyO,
  'p': LogicalKeyboardKey.keyP,
  'q': LogicalKeyboardKey.keyQ,
  'r': LogicalKeyboardKey.keyR,
  's': LogicalKeyboardKey.keyS,
  't': LogicalKeyboardKey.keyT,
  'u': LogicalKeyboardKey.keyU,
  'v': LogicalKeyboardKey.keyV,
  'w': LogicalKeyboardKey.keyW,
  'x': LogicalKeyboardKey.keyX,
  'y': LogicalKeyboardKey.keyY,
  'z': LogicalKeyboardKey.keyZ,
  '0': LogicalKeyboardKey.digit0,
  '1': LogicalKeyboardKey.digit1,
  '2': LogicalKeyboardKey.digit2,
  '3': LogicalKeyboardKey.digit3,
  '4': LogicalKeyboardKey.digit4,
  '5': LogicalKeyboardKey.digit5,
  '6': LogicalKeyboardKey.digit6,
  '7': LogicalKeyboardKey.digit7,
  '8': LogicalKeyboardKey.digit8,
  '9': LogicalKeyboardKey.digit9,
  'enter': LogicalKeyboardKey.enter,
  'escape': LogicalKeyboardKey.escape,
  'tab': LogicalKeyboardKey.tab,
  'space': LogicalKeyboardKey.space,
  'delete': LogicalKeyboardKey.delete,
  'backspace': LogicalKeyboardKey.backspace,
  'arrowup': LogicalKeyboardKey.arrowUp,
  'arrowdown': LogicalKeyboardKey.arrowDown,
  'arrowleft': LogicalKeyboardKey.arrowLeft,
  'arrowright': LogicalKeyboardKey.arrowRight,
  'home': LogicalKeyboardKey.home,
  'end': LogicalKeyboardKey.end,
  'pageup': LogicalKeyboardKey.pageUp,
  'pagedown': LogicalKeyboardKey.pageDown,
  'f1': LogicalKeyboardKey.f1,
  'f2': LogicalKeyboardKey.f2,
  'f3': LogicalKeyboardKey.f3,
  'f4': LogicalKeyboardKey.f4,
  'f5': LogicalKeyboardKey.f5,
  'f6': LogicalKeyboardKey.f6,
  'f7': LogicalKeyboardKey.f7,
  'f8': LogicalKeyboardKey.f8,
  'f9': LogicalKeyboardKey.f9,
  'f10': LogicalKeyboardKey.f10,
  'f11': LogicalKeyboardKey.f11,
  'f12': LogicalKeyboardKey.f12,
};

bool _visible(Map<String, dynamic> item) => item['visible'] != false;

String _kind(Map<String, dynamic> item) => item['type']?.toString() ?? 'item';

AlignmentGeometry _menuAlignment(String token) => switch (token) {
  'bottomEnd' => AlignmentDirectional.bottomEnd,
  'topStart' => AlignmentDirectional.topStart,
  'topEnd' => AlignmentDirectional.topEnd,
  _ => AlignmentDirectional.bottomStart,
};
