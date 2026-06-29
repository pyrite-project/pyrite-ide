import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/sdk/models/plugin_theme.dart';

class DataRegistry extends ChangeNotifier {
  // pluginId → { themeName → PluginThemeData }
  final Map<String, Map<String, PluginThemeData>> _themes = {};
  // pluginId → { locale → messages }
  final Map<String, Map<String, Map<String, dynamic>>> _locales = {};
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
    if (hadThemes || hadLocales) {
      if (hadLocales) _rebuildMergedLocales();
      notifyListeners();
    }
  }
}

final dataRegistryProvider =
    ChangeNotifierProvider((ref) => DataRegistry());
