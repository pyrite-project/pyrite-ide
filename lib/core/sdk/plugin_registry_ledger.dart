import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_registry_client.dart';

const _fileName = 'plugin_registry_ledger.json';

/// Where an installed plugin came from.
class RegistrySource {
  const RegistrySource({
    required this.pluginId,
    required this.origin,
    required this.version,
  });

  final String pluginId;
  final String origin;
  final String version;

  Map<String, Object?> toJson() => {'origin': origin, 'version': version};

  @override
  bool operator ==(Object other) =>
      other is RegistrySource &&
      other.pluginId == pluginId &&
      other.origin == origin &&
      other.version == version;

  @override
  int get hashCode => Object.hash(pluginId, origin, version);
}

class RegistryLedgerSnapshot {
  const RegistryLedgerSnapshot({
    this.sources = const {},
    this.advisories = const {},
    this.checkedAt,
  });

  /// Plugins installed from a registry, by plugin id.
  final Map<String, RegistrySource> sources;

  /// The registry's last answer for those plugins, by plugin id.
  final Map<String, PluginAdvisory> advisories;

  /// When the registries were last asked, whether or not anything changed.
  final DateTime? checkedAt;
}

/// Remembers which installed plugins came from a registry site, and what that
/// site last said about them, so a warning is on screen before the network is.
///
/// A corrupt or unreadable file reads as empty: it only ever costs the user a
/// re-check, and must never stop the IDE from starting.
class PluginRegistryLedger {
  PluginRegistryLedger({Future<Directory> Function()? supportDirectory})
    : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _supportDirectory;
  Future<void> _writes = Future.value();

  Future<File> _file() async =>
      File(path.join((await _supportDirectory()).path, _fileName));

  Future<RegistryLedgerSnapshot> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const RegistryLedgerSnapshot();
      final json = jsonDecode(await file.readAsString());
      return json is Map<String, dynamic>
          ? _decode(json)
          : const RegistryLedgerSnapshot();
    } on FormatException {
      return const RegistryLedgerSnapshot();
    } on FileSystemException catch (error) {
      debugPrint('PluginRegistryLedger: cannot read $_fileName: $error');
      return const RegistryLedgerSnapshot();
    }
  }

  /// Notes that [source] was just installed. Whatever was known about an older
  /// release of the same plugin no longer applies; [advisory] is what the
  /// registry said about the release it was installed from.
  Future<void> recordInstall(
    RegistrySource source, {
    PluginAdvisory? advisory,
  }) => _update((snapshot) {
    final advisories = {...snapshot.advisories}..remove(source.pluginId);
    if (advisory != null) advisories[source.pluginId] = advisory;
    return RegistryLedgerSnapshot(
      sources: {...snapshot.sources, source.pluginId: source},
      advisories: advisories,
      checkedAt: snapshot.checkedAt,
    );
  });

  Future<void> forget(Iterable<String> pluginIds) => _update((snapshot) {
    final gone = pluginIds.toSet();
    return RegistryLedgerSnapshot(
      sources: {...snapshot.sources}..removeWhere((id, _) => gone.contains(id)),
      advisories: {...snapshot.advisories}
        ..removeWhere((id, _) => gone.contains(id)),
      checkedAt: snapshot.checkedAt,
    );
  });

  Future<void> saveCheck({
    required Map<String, PluginAdvisory> advisories,
    required DateTime checkedAt,
  }) => _update(
    (snapshot) => RegistryLedgerSnapshot(
      sources: snapshot.sources,
      advisories: advisories,
      checkedAt: checkedAt,
    ),
  );

  // Writes are chained so two quick updates cannot read the same snapshot and
  // lose one of the changes.
  Future<void> _update(
    RegistryLedgerSnapshot Function(RegistryLedgerSnapshot) change,
  ) {
    final next = _writes.then((_) async {
      final file = await _file();
      final updated = change(await read());
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(jsonEncode(_encode(updated)));
      await temporary.rename(file.path);
    });
    _writes = next.catchError((Object _) {});
    return next;
  }

  static Map<String, Object?> _encode(RegistryLedgerSnapshot snapshot) => {
    'sources': {
      for (final entry in snapshot.sources.entries)
        entry.key: entry.value.toJson(),
    },
    'advisories': {
      for (final entry in snapshot.advisories.entries)
        entry.key: entry.value.toJson(),
    },
    'checkedAt': snapshot.checkedAt?.toUtc().toIso8601String(),
  };

  static RegistryLedgerSnapshot _decode(Map<String, dynamic> json) {
    final sources = <String, RegistrySource>{};
    final rawSources = json['sources'];
    if (rawSources is Map<String, dynamic>) {
      for (final entry in rawSources.entries) {
        final value = entry.value;
        if (value is Map<String, dynamic> &&
            value['origin'] is String &&
            value['version'] is String) {
          sources[entry.key] = RegistrySource(
            pluginId: entry.key,
            origin: value['origin'] as String,
            version: value['version'] as String,
          );
        }
      }
    }
    final advisories = <String, PluginAdvisory>{};
    final rawAdvisories = json['advisories'];
    if (rawAdvisories is Map<String, dynamic>) {
      for (final entry in rawAdvisories.entries) {
        final value = entry.value;
        if (value is! Map<String, dynamic>) continue;
        try {
          advisories[entry.key] = PluginAdvisory.fromJson(value);
        } on PluginRegistryException {
          // A damaged entry is dropped; the next check restores it.
        }
      }
    }
    final checkedAt = json['checkedAt'];
    return RegistryLedgerSnapshot(
      sources: sources,
      advisories: advisories,
      checkedAt: checkedAt is String ? DateTime.tryParse(checkedAt) : null,
    );
  }
}
