import 'package:pyrite_ide/core/sdk/context_key_service.dart';
import 'package:pyrite_ide/core/sdk/contribution_registry.dart';
import 'package:pyrite_ide/core/sdk/plugin_manifest.dart';

/// A menu contribution resolved against the current context keys and command.
class ResolvedMenuItem {
  const ResolvedMenuItem({
    required this.pluginId,
    required this.commandId,
    required this.title,
    required this.location,
    required this.enabled,
    this.icon,
    this.view,
    this.group,
    this.order = 0,
  });

  final String pluginId;
  final String commandId;
  final String title;
  final String location;
  final bool enabled;
  final PluginIconReference? icon;
  final String? view;
  final String? group;
  final int order;

  String? get materialIcon {
    final icon = this.icon;
    if (icon == null || icon.kind != PluginIconKind.material) return null;
    return 'material:${icon.value}';
  }
}

/// Resolves Manifest menu contributions for a location (and optional view).
///
/// Visibility follows the menu entry's `when` (via [ContributionRegistry]).
/// Enablement follows the target command's `when` (false → disabled, not hidden).
class MenuResolver {
  MenuResolver({required this.registry, required this.contextKeys});

  final ContributionRegistry registry;
  final ContextKeyService contextKeys;

  static const String viewTitle = 'view/title';
  static const String viewContext = 'view/context';
  static const String navigationContext = 'navigation/context';
  static const String commandPalette = 'commandPalette';

  List<ResolvedMenuItem> resolve({
    required String location,
    String? viewId,
    Set<String>? enabledPluginIds,
  }) {
    final items = <ResolvedMenuItem>[];
    for (final menu in registry.menus.visible) {
      final contribution = menu.value;
      if (contribution.location != location) continue;
      if (viewId != null &&
          contribution.view != null &&
          contribution.view != viewId) {
        continue;
      }
      if (enabledPluginIds != null &&
          !enabledPluginIds.contains(menu.pluginId)) {
        continue;
      }
      final command = registry.commands.byId(contribution.command);
      if (command == null) continue;
      if (enabledPluginIds != null &&
          !enabledPluginIds.contains(command.pluginId)) {
        continue;
      }
      final commandWhen = command.value.when == null
          ? null
          : WhenExpression.parse(
              command.value.when!,
              allowedKeys: contextKeys.allowedKeys,
            );
      items.add(
        ResolvedMenuItem(
          pluginId: command.pluginId,
          commandId: command.value.id,
          title: command.value.title,
          location: location,
          enabled: contextKeys.evaluate(commandWhen),
          icon: command.value.icon,
          view: contribution.view,
          group: contribution.group,
          order: contribution.order != 0
              ? contribution.order
              : command.value.order,
        ),
      );
    }
    items.sort((a, b) {
      final byOrder = a.order.compareTo(b.order);
      if (byOrder != 0) return byOrder;
      return a.commandId.compareTo(b.commandId);
    });
    return items;
  }

  /// Whether [commandId] is currently enabled under context keys.
  bool isCommandEnabled(String commandId) {
    final command = registry.commands.byId(commandId);
    if (command == null || !command.visible) return false;
    final when = command.value.when;
    if (when == null) return true;
    return contextKeys.evaluate(
      WhenExpression.parse(when, allowedKeys: contextKeys.allowedKeys),
    );
  }
}
