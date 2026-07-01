import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/sdk/models/plugin_theme.dart';

class StubsProfileEntry {
  const StubsProfileEntry({
    required this.id,
    required this.path,
    this.label,
    this.priority = 0,
    this.metadata = const {},
  });

  final String id;
  final String path;
  final String? label;
  final int priority;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    'label': label,
    'priority': priority,
    'metadata': metadata,
  };

  factory StubsProfileEntry.fromMap(Map<String, dynamic> map) {
    return StubsProfileEntry(
      id: map['id']?.toString() ?? '',
      path: map['path']?.toString() ?? '',
      label: map['label']?.toString(),
      priority: (map['priority'] as num?)?.toInt() ?? 0,
      metadata: Map<String, dynamic>.from(map['metadata'] as Map? ?? {}),
    );
  }
}

class StubsProviderEntry {
  const StubsProviderEntry({
    required this.pluginId,
    required this.providerId,
    required this.kind,
    required this.version,
    required this.profiles,
    this.aliases = const [],
    this.metadata = const {},
  });

  final String pluginId;
  final String providerId;
  final String kind;
  final String version;
  final List<StubsProfileEntry> profiles;
  final List<String> aliases;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => {
    'plugin_id': pluginId,
    'provider_id': providerId,
    'kind': kind,
    'version': version,
    'profiles': profiles.map((profile) => profile.toJson()).toList(),
    'aliases': aliases,
    'metadata': metadata,
  };
}

class DataRegistry extends ChangeNotifier {
  // pluginId → { themeName → PluginThemeData }
  final Map<String, Map<String, PluginThemeData>> _themes = {};
  // pluginId → { locale → messages }
  final Map<String, Map<String, Map<String, dynamic>>> _locales = {};
  // providerId → StubsProviderEntry
  final Map<String, StubsProviderEntry> _stubsProviders = {};
  // Merged locale → messages (all plugins combined, later plugins override)
  Map<String, Map<String, dynamic>> _mergedLocales = {};

  // ── Theme ──

  List<PluginThemeData> get allThemes {
    final list = <PluginThemeData>[];
    for (final pluginThemes in _themes.values) {
      list.addAll(pluginThemes.values);
    }
    return list;
  }

  PluginThemeData? getThemeById(String fullId) {
    // fullId = "pluginId::themeName"
    final separator = fullId.indexOf('::');
    if (separator == -1) return null;
    final pluginId = fullId.substring(0, separator);
    final themeName = fullId.substring(separator + 2);
    return _themes[pluginId]?[themeName];
  }

  void registerTheme(
    String pluginId,
    String themeName,
    Map<String, dynamic> data,
  ) {
    final fullId = '$pluginId::$themeName';
    final theme = PluginThemeData.fromMap(fullId, themeName, pluginId, data);
    _themes.putIfAbsent(pluginId, () => {});
    _themes[pluginId]![themeName] = theme;
    notifyListeners();
  }

  // ── i18n ──

  List<String> get availableLocales {
    final locales = <String>{};
    for (final pluginLocales in _locales.values) {
      locales.addAll(pluginLocales.keys);
    }
    return locales.toList()..sort();
  }

  Map<String, dynamic>? getLocale(String locale) {
    return _mergedLocales[locale];
  }

  String translate(String key, {String? locale}) {
    final targetLocale = locale ?? 'zh-CN';
    final messages = _mergedLocales[targetLocale];
    if (messages == null) return key;
    return messages[key]?.toString() ?? key;
  }

  void registerLocale(
    String pluginId,
    String locale,
    Map<String, dynamic> messages,
  ) {
    _locales.putIfAbsent(pluginId, () => {});
    _locales[pluginId]![locale] = messages;
    _rebuildMergedLocales();
    notifyListeners();
  }

  // ── Stubs ──

  List<StubsProviderEntry> get allStubsProviders =>
      _stubsProviders.values.toList()
        ..sort((a, b) => a.providerId.compareTo(b.providerId));

  StubsProviderEntry? getStubsProvider(String providerId) {
    return _stubsProviders[providerId];
  }

  StubsProfileEntry? getStubsProfile(String providerId, String profileId) {
    final provider = _stubsProviders[providerId];
    if (provider == null) return null;
    for (final profile in provider.profiles) {
      if (profile.id == profileId) return profile;
    }
    return null;
  }

  List<Map<String, dynamic>> resolveStubsLayers(
    List<Map<String, String>> layers,
  ) {
    final resolved = <Map<String, dynamic>>[];
    for (final layer in layers) {
      final providerId = layer['provider'] ?? layer['provider_id'] ?? '';
      final profileId = layer['profile'] ?? layer['profile_id'] ?? '';
      final profile = getStubsProfile(providerId, profileId);
      if (profile == null) continue;
      resolved.add({
        'provider': providerId,
        'profile': profileId,
        'path': profile.path,
        'label': profile.label,
        'priority': profile.priority,
      });
    }
    return resolved;
  }

  void registerStubsProvider(StubsProviderEntry entry) {
    final existing = _stubsProviders[entry.providerId];
    if (existing != null && existing.pluginId != entry.pluginId) {
      throw StateError(
        'Stubs provider id already registered: ${entry.providerId}',
      );
    }
    _stubsProviders[entry.providerId] = entry;
    notifyListeners();
  }

  void _rebuildMergedLocales() {
    _mergedLocales = {};
    for (final pluginLocales in _locales.values) {
      for (final entry in pluginLocales.entries) {
        _mergedLocales.putIfAbsent(entry.key, () => {});
        _mergedLocales[entry.key]!.addAll(entry.value);
      }
    }
  }

  // ── Cleanup ──

  void removePlugin(String pluginId) {
    final hadThemes = _themes.remove(pluginId) != null;
    final hadLocales = _locales.remove(pluginId) != null;
    final stubsToRemove = _stubsProviders.entries
        .where((entry) => entry.value.pluginId == pluginId)
        .map((entry) => entry.key)
        .toList();
    for (final providerId in stubsToRemove) {
      _stubsProviders.remove(providerId);
    }
    if (hadThemes || hadLocales || stubsToRemove.isNotEmpty) {
      if (hadLocales) _rebuildMergedLocales();
      notifyListeners();
    }
  }
}

final dataRegistryProvider =
    ChangeNotifierProvider((ref) => DataRegistry());
