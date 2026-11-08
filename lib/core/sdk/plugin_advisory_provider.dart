import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/sdk/plugin_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_registry_client.dart';
import 'package:pyrite_ide/core/sdk/plugin_registry_ledger.dart';
import 'package:pyrite_ide/core/sdk/types.dart';

/// How long an answer stays fresh. The periodic tick is more frequent, so a
/// machine that was asleep or offline catches up soon after it wakes.
const advisoryCheckInterval = Duration(hours: 6);
const advisoryTickInterval = Duration(hours: 1);
const _releasesPerRequest = 100;

class PluginAdvisoryState {
  const PluginAdvisoryState({
    this.advisories = const {},
    this.checking = false,
    this.checkedAt,
  });

  /// What the registries last said about installed plugins, by plugin id.
  final Map<String, PluginAdvisory> advisories;
  final bool checking;
  final DateTime? checkedAt;

  /// The advisory for [pluginId] when it deserves the user's attention.
  PluginAdvisory? flaggedFor(String pluginId) {
    final advisory = advisories[pluginId];
    return advisory != null && advisory.isFlagged ? advisory : null;
  }

  PluginAdvisoryState copyWith({
    Map<String, PluginAdvisory>? advisories,
    bool? checking,
    DateTime? checkedAt,
  }) => PluginAdvisoryState(
    advisories: advisories ?? this.advisories,
    checking: checking ?? this.checking,
    checkedAt: checkedAt ?? this.checkedAt,
  );
}

/// Keeps the user informed about plugins they installed from a registry.
///
/// Registries can deprecate a release, publish a security advisory or withdraw
/// it after it was installed. Nothing is changed automatically: the IDE only
/// asks, remembers the answer, and shows it.
class PluginAdvisoryNotifier extends StateNotifier<PluginAdvisoryState> {
  PluginAdvisoryNotifier({
    required Map<String, Plugin> Function() installedPlugins,
    PluginRegistryClient? client,
    PluginRegistryLedger? ledger,
    DateTime Function()? now,
  }) : _installedPlugins = installedPlugins,
       _client = client ?? PluginRegistryClient(),
       _ledger = ledger ?? PluginRegistryLedger(),
       _now = now ?? DateTime.now,
       super(const PluginAdvisoryState());

  final Map<String, Plugin> Function() _installedPlugins;
  final PluginRegistryClient _client;
  final PluginRegistryLedger _ledger;
  final DateTime Function() _now;

  /// Called with advisories that became worth attention since the last check.
  void Function(List<PluginAdvisory> alerts)? onNewAlerts;

  /// Shows the answers remembered from earlier sessions.
  Future<void> reload() async {
    final snapshot = await _ledger.read();
    if (!mounted) return;
    state = PluginAdvisoryState(
      advisories: snapshot.advisories,
      checkedAt: snapshot.checkedAt,
    );
  }

  Future<void> checkIfDue() async {
    final checkedAt = state.checkedAt;
    if (state.checking ||
        (checkedAt != null &&
            _now().difference(checkedAt) < advisoryCheckInterval)) {
      return;
    }
    await check();
  }

  Future<void> check() async {
    if (state.checking) return;
    state = state.copyWith(checking: true);
    try {
      await _check();
    } on Object catch (error) {
      debugPrint('PluginAdvisoryNotifier: check failed: $error');
    } finally {
      if (mounted) state = state.copyWith(checking: false);
    }
  }

  Future<void> _check() async {
    final installed = _installedPlugins();
    final snapshot = await _ledger.read();

    final gone = snapshot.sources.keys.where(
      (id) => !installed.containsKey(id),
    );
    if (gone.isNotEmpty) await _ledger.forget(gone.toList());

    // A plugin updated or replaced by other means no longer matches what the
    // registry remembers, so it is left alone rather than judged by a verdict
    // about a different release.
    final eligible = [
      for (final source in snapshot.sources.values)
        if (installed[source.pluginId]?.version == source.version) source,
    ];

    final previous = {
      for (final entry in snapshot.advisories.entries)
        if (eligible.any((source) => source.pluginId == entry.key))
          entry.key: entry.value,
    };
    final fresh = <String, PluginAdvisory>{};
    var answered = eligible.isEmpty;

    final byOrigin = <String, List<RegistrySource>>{};
    for (final source in eligible) {
      byOrigin.putIfAbsent(source.origin, () => []).add(source);
    }
    for (final entry in byOrigin.entries) {
      try {
        for (var i = 0; i < entry.value.length; i += _releasesPerRequest) {
          final batch = entry.value.skip(i).take(_releasesPerRequest).toList();
          final advisories = await _client.fetchAdvisories(entry.key, [
            for (final source in batch)
              (pluginId: source.pluginId, version: source.version),
          ]);
          for (final advisory in advisories) {
            if (batch.any(
              (s) =>
                  s.pluginId == advisory.pluginId &&
                  s.version == advisory.version,
            )) {
              fresh[advisory.pluginId] = advisory;
            }
          }
        }
        answered = true;
      } on PluginRegistryException catch (error) {
        // Keep what was known: being offline must not clear a warning.
        debugPrint('PluginAdvisoryNotifier: ${entry.key}: $error');
      }
    }

    // Nothing was reached: leave the clock alone so the next tick retries.
    if (!answered) return;

    final merged = {...previous, ...fresh};
    final checkedAt = _now();
    await _ledger.saveCheck(advisories: merged, checkedAt: checkedAt);
    if (!mounted) return;
    state = PluginAdvisoryState(
      advisories: merged,
      checking: state.checking,
      checkedAt: checkedAt,
    );

    final alerts = [
      for (final advisory in fresh.values)
        if (advisory.isFlagged && previous[advisory.pluginId] != advisory)
          advisory,
    ];
    if (alerts.isNotEmpty) onNewAlerts?.call(alerts);
  }
}

final pluginAdvisoryProvider =
    StateNotifierProvider<PluginAdvisoryNotifier, PluginAdvisoryState>((ref) {
      return PluginAdvisoryNotifier(
        installedPlugins: () => ref.read(pluginManagerProvider),
      );
    });
