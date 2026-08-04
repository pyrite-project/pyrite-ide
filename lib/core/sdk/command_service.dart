import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/sdk/activation_manager.dart';
import 'package:pyrite_ide/core/sdk/context_key_service.dart';
import 'package:pyrite_ide/core/sdk/contribution_registry.dart';
import 'package:pyrite_ide/core/sdk/menu_resolver.dart';
import 'package:pyrite_ide/core/sdk/plugin_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/types.dart';

/// Stable error codes returned by [CommandService.execute].
abstract class CommandErrorCode {
  static const String notFound = 'command_not_found';
  static const String disabled = 'command_disabled';
  static const String pluginDisabled = 'plugin_not_enabled';
  static const String notActive = 'plugin_not_active';
  static const String executionFailed = 'execution_failed';
  static const String timeout = 'command_timeout';
}

class CommandException implements Exception {
  CommandException(this.code, this.message);
  final String code;
  final String message;

  @override
  String toString() => 'CommandException($code): $message';
}

/// Executes Manifest-declared commands by activating the owning plugin and
/// sending `ide.command.execute` over the plugin session.
class CommandService {
  CommandService(this._ref);

  final Ref _ref;

  ContributionRegistry get _registry => _ref.read(contributionRegistryProvider);
  ContextKeyService get _contextKeys => _ref.read(contextKeyServiceProvider);
  MenuResolver get _menus =>
      MenuResolver(registry: _registry, contextKeys: _contextKeys);

  /// Looks up a contributed command, or null when it is not registered.
  RegisteredContribution<PluginCommandContribution>? lookup(String commandId) =>
      _registry.commands.byId(commandId);

  bool isEnabled(String commandId) => _menus.isCommandEnabled(commandId);

  /// Activates the owning plugin (via `onCommand`) and runs the handler.
  ///
  /// [context] is forwarded to the plugin (viewId/instanceId/nodeId/selection).
  Future<Object?> execute(
    String commandId, {
    Map<String, dynamic> args = const {},
    Map<String, dynamic> context = const {},
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final contribution = _registry.commands.byId(commandId);
    if (contribution == null) {
      throw CommandException(
        CommandErrorCode.notFound,
        'Unknown command: $commandId',
      );
    }
    if (!_menus.isCommandEnabled(commandId)) {
      throw CommandException(
        CommandErrorCode.disabled,
        'Command is disabled by when context: $commandId',
      );
    }

    final plugins = _ref.read(pluginManagerProvider);
    final plugin = plugins[contribution.pluginId];
    if (plugin == null || plugin.status != PluginStatus.usable) {
      throw CommandException(
        CommandErrorCode.pluginDisabled,
        'Plugin is not enabled: ${contribution.pluginId}',
      );
    }

    final activation = _ref.read(activationManagerProvider.notifier);
    final onCommand = 'onCommand:$commandId';
    final declaresOnCommand =
        plugin.manifest?.activationEvents.contains(onCommand) ?? false;
    if (declaresOnCommand) {
      await activation.activateForCommand(plugins.values, commandId);
    }
    final record = activation.record(plugin.id);
    final alreadyActive = record?.state == ActivationState.active;
    if (!alreadyActive && !declaresOnCommand) {
      throw CommandException(
        CommandErrorCode.notActive,
        'Command requires an active plugin session or onCommand activation: '
        '$commandId',
      );
    }
    if (!alreadyActive && declaresOnCommand) {
      final started = await activation.activate(plugin, reason: onCommand);
      if (!started) {
        throw CommandException(
          CommandErrorCode.notActive,
          'Failed to activate plugin for command: $commandId',
        );
      }
    }

    final manager = _managerFor(plugin.id);
    if (manager == null) {
      throw CommandException(
        CommandErrorCode.notActive,
        'No active session for plugin: ${plugin.id}',
      );
    }

    try {
      final response = await manager.sendAndWaitReply(
        makeEnvelope(
          type: IdeCommands.commandExecute,
          payload: {'commandId': commandId, 'args': args, 'context': context},
        ),
        timeout: timeout,
        connectIfNeeded: false,
      );
      final type = response['type']?.toString() ?? '';
      final payload = response['payload'] as Map<String, dynamic>? ?? {};
      if (type.endsWith('.error')) {
        throw CommandException(
          payload['code']?.toString() ?? CommandErrorCode.executionFailed,
          payload['message']?.toString() ?? 'Command failed: $commandId',
        );
      }
      final data = payload['data'];
      return data;
    } on TimeoutException {
      throw CommandException(
        CommandErrorCode.timeout,
        'Command timed out: $commandId',
      );
    }
  }

  PluginRunManager? _managerFor(String pluginId) {
    for (final entry in _ref.read(pluginRunManagerProvider).entries) {
      if (entry.key.id == pluginId) return entry.value;
    }
    return null;
  }
}

final Provider<CommandService> commandServiceProvider = Provider(
  CommandService.new,
);

final Provider<MenuResolver> menuResolverProvider = Provider(
  (ref) => MenuResolver(
    registry: ref.watch(contributionRegistryProvider),
    contextKeys: ref.watch(contextKeyServiceProvider),
  ),
);
