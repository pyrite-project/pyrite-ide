import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/sdk/context_key_service.dart';
import 'package:pyrite_ide/core/sdk/plugin_manifest.dart';

class RegisteredContribution<T> {
  RegisteredContribution._({
    required this.pluginId,
    required this.key,
    required this.value,
    required WhenExpression? when,
    required bool visible,
  }) : _when = when,
       _visible = visible;

  final String pluginId;
  final String key;
  final T value;
  final WhenExpression? _when;
  bool _visible;

  bool get visible => _visible;
  Set<String> get contextDependencies => _when?.dependencies ?? const {};

  bool _reevaluate(ContextKeyService contextKeys) {
    final next = contextKeys.evaluate(_when);
    final changed = next != _visible;
    _visible = next;
    return changed;
  }
}

class ContributionSubRegistry<T> {
  ContributionSubRegistry._();

  final Map<String, RegisteredContribution<T>> _entries = {};

  List<RegisteredContribution<T>> get all =>
      List<RegisteredContribution<T>>.unmodifiable(_entries.values);
  List<RegisteredContribution<T>> get visible =>
      List<RegisteredContribution<T>>.unmodifiable(
        _entries.values.where((entry) => entry.visible),
      );
  RegisteredContribution<T>? byId(String id) => _entries[id.toLowerCase()];
}

class ContributionRegistry extends ChangeNotifier {
  ContributionRegistry(this.contextKeys) {
    contextKeys.addChangeListener(_handleContextChange);
  }

  final ContextKeyService contextKeys;
  final navigation =
      ContributionSubRegistry<PluginNavigationContainerContribution>._();
  final views = ContributionSubRegistry<PluginViewContribution>._();
  final commands = ContributionSubRegistry<PluginCommandContribution>._();
  final menus = ContributionSubRegistry<PluginMenuContribution>._();
  final configuration =
      ContributionSubRegistry<PluginConfigurationContribution>._();

  final Map<String, _PluginContributionSet> _plugins = {};
  final Map<String, String> _idOwners = {};
  final Map<String, Set<RegisteredContribution<Object?>>> _dependencies = {};

  int _lastContextEvaluationCount = 0;
  bool _notificationScheduled = false;
  bool _disposed = false;
  int get lastContextEvaluationCount => _lastContextEvaluationCount;
  Set<String> get pluginIds => Set<String>.unmodifiable(_plugins.keys);

  void registerPlugin(PluginManifestV2 manifest) {
    final staged = _stage(manifest);
    _validateIds([staged], excludingPluginIds: {manifest.id});
    _removePlugin(manifest.id);
    _install(staged);
    notifyListeners();
  }

  void replaceAll(
    Iterable<PluginManifestV2> manifests, {
    bool deferNotification = false,
  }) {
    final staged = manifests.map(_stage).toList(growable: false);
    _validateIds(staged, excludingPluginIds: _plugins.keys.toSet());
    _clear();
    for (final plugin in staged) {
      _install(plugin);
    }
    _emitNotification(deferNotification: deferNotification);
  }

  void unregisterPlugin(String pluginId) {
    if (!_plugins.containsKey(pluginId)) return;
    _removePlugin(pluginId);
    notifyListeners();
  }

  _PluginContributionSet _stage(PluginManifestV2 manifest) {
    PluginManifestValidator(
      contextKeys: contextKeys.allowedKeys,
    ).validate(manifest);
    final entries = <RegisteredContribution<Object?>>[];

    RegisteredContribution<T> entry<T>(String key, T value, String? when) {
      final expression = when == null
          ? null
          : WhenExpression.parse(when, allowedKeys: contextKeys.allowedKeys);
      final result = RegisteredContribution<T>._(
        pluginId: manifest.id,
        key: key,
        value: value,
        when: expression,
        visible: contextKeys.evaluate(expression),
      );
      entries.add(result as RegisteredContribution<Object?>);
      return result;
    }

    final contributions = manifest.contributes;
    final navigationEntries = [
      for (final value in contributions.navigationContainers)
        entry(value.id, value, value.when),
    ];
    final viewEntries = [
      for (final value in contributions.views)
        entry(value.id, value, value.when),
    ];
    final commandEntries = [
      for (final value in contributions.commands)
        entry(value.id, value, value.when),
    ];
    final menuEntries = [
      for (var index = 0; index < contributions.menus.length; index++)
        entry(
          '${manifest.id}#menu:$index',
          contributions.menus[index],
          contributions.menus[index].when,
        ),
    ];
    final configurationEntries = [
      for (final value in contributions.configuration)
        entry(value.id, value, value.when),
    ];
    return _PluginContributionSet(
      pluginId: manifest.id,
      ids: manifest.contributes.ids.map((id) => id.toLowerCase()).toSet(),
      entries: entries,
      navigation: navigationEntries,
      views: viewEntries,
      commands: commandEntries,
      menus: menuEntries,
      configuration: configurationEntries,
    );
  }

  void _validateIds(
    Iterable<_PluginContributionSet> candidates, {
    required Set<String> excludingPluginIds,
  }) {
    final owners = <String, String>{
      for (final entry in _idOwners.entries)
        if (!excludingPluginIds.contains(entry.value)) entry.key: entry.value,
    };
    final pluginIds = <String>{};
    for (final candidate in candidates) {
      if (!pluginIds.add(candidate.pluginId.toLowerCase())) {
        throw PluginManifestException(
          PluginManifestErrorCode.contributionConflict,
          'Duplicate plugin ID: ${candidate.pluginId}',
        );
      }
      for (final id in candidate.ids) {
        final owner = owners[id];
        if (owner != null) {
          throw PluginManifestException(
            PluginManifestErrorCode.contributionConflict,
            'Contribution ID $id conflicts with plugin $owner',
          );
        }
        owners[id] = candidate.pluginId;
      }
    }
  }

  void _install(_PluginContributionSet plugin) {
    _plugins[plugin.pluginId] = plugin;
    for (final id in plugin.ids) {
      _idOwners[id] = plugin.pluginId;
    }
    _addEntries(navigation._entries, plugin.navigation);
    _addEntries(views._entries, plugin.views);
    _addEntries(commands._entries, plugin.commands);
    _addEntries(menus._entries, plugin.menus);
    _addEntries(configuration._entries, plugin.configuration);
    for (final entry in plugin.entries) {
      for (final dependency in entry.contextDependencies) {
        _dependencies.putIfAbsent(dependency, () => {}).add(entry);
      }
    }
  }

  void _addEntries<T>(
    Map<String, RegisteredContribution<T>> target,
    Iterable<RegisteredContribution<T>> entries,
  ) {
    for (final entry in entries) {
      target[entry.key.toLowerCase()] = entry;
    }
  }

  void _removePlugin(String pluginId) {
    final plugin = _plugins.remove(pluginId);
    if (plugin == null) return;
    for (final id in plugin.ids) {
      _idOwners.remove(id);
    }
    for (final entry in plugin.entries) {
      for (final dependency in entry.contextDependencies) {
        final dependants = _dependencies[dependency];
        dependants?.remove(entry);
        if (dependants?.isEmpty == true) _dependencies.remove(dependency);
      }
    }
    navigation._entries.removeWhere((_, entry) => entry.pluginId == pluginId);
    views._entries.removeWhere((_, entry) => entry.pluginId == pluginId);
    commands._entries.removeWhere((_, entry) => entry.pluginId == pluginId);
    menus._entries.removeWhere((_, entry) => entry.pluginId == pluginId);
    configuration._entries.removeWhere(
      (_, entry) => entry.pluginId == pluginId,
    );
  }

  void _clear() {
    _plugins.clear();
    _idOwners.clear();
    _dependencies.clear();
    navigation._entries.clear();
    views._entries.clear();
    commands._entries.clear();
    menus._entries.clear();
    configuration._entries.clear();
  }

  void _handleContextChange(Set<String> changedKeys) {
    final affected = <RegisteredContribution<Object?>>{};
    for (final key in changedKeys) {
      affected.addAll(_dependencies[key] ?? const {});
    }
    _lastContextEvaluationCount = affected.length;
    var visibilityChanged = false;
    for (final entry in affected) {
      visibilityChanged = entry._reevaluate(contextKeys) || visibilityChanged;
    }
    if (visibilityChanged) notifyListeners();
  }

  void _emitNotification({required bool deferNotification}) {
    if (!deferNotification) {
      notifyListeners();
      return;
    }
    if (_notificationScheduled) return;
    _notificationScheduled = true;
    Future<void>.microtask(() {
      _notificationScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    contextKeys.removeChangeListener(_handleContextChange);
    _clear();
    super.dispose();
  }
}

class _PluginContributionSet {
  const _PluginContributionSet({
    required this.pluginId,
    required this.ids,
    required this.entries,
    required this.navigation,
    required this.views,
    required this.commands,
    required this.menus,
    required this.configuration,
  });

  final String pluginId;
  final Set<String> ids;
  final List<RegisteredContribution<Object?>> entries;
  final List<RegisteredContribution<PluginNavigationContainerContribution>>
  navigation;
  final List<RegisteredContribution<PluginViewContribution>> views;
  final List<RegisteredContribution<PluginCommandContribution>> commands;
  final List<RegisteredContribution<PluginMenuContribution>> menus;
  final List<RegisteredContribution<PluginConfigurationContribution>>
  configuration;
}

final contributionRegistryProvider =
    ChangeNotifierProvider<ContributionRegistry>(
      (ref) => ContributionRegistry(ref.read(contextKeyServiceProvider)),
    );
