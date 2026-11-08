import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_advisory_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_install_link.dart';
import 'package:pyrite_ide/core/sdk/plugin_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_registry_client.dart';
import 'package:pyrite_ide/core/sdk/plugin_registry_ledger.dart';
import 'package:pyrite_ide/core/sdk/trusted_plugin_origins.dart';

enum PluginInstallPhase { loading, ready, installing, installed, failed }

enum PluginInstallStep { downloading, installing }

class PluginInstallState {
  const PluginInstallState({
    this.phase = PluginInstallPhase.loading,
    this.step,
    this.release,
    this.sourceTrusted = true,
    this.updated = false,
    this.error,
  });

  final PluginInstallPhase phase;
  final PluginInstallStep? step;

  /// What the registry says about the release; null for a local file.
  final PluginRegistryRelease? release;

  /// Whether the user has installed from this registry site before. Local
  /// files have no site, so they count as trusted.
  final bool sourceTrusted;

  /// Whether the install replaced an already installed plugin.
  final bool updated;
  final Object? error;

  PluginInstallState copyWith({
    PluginInstallPhase? phase,
    PluginInstallStep? step,
    PluginRegistryRelease? release,
    bool? sourceTrusted,
    bool? updated,
    Object? error,
  }) => PluginInstallState(
    phase: phase ?? this.phase,
    step: step,
    release: release ?? this.release,
    sourceTrusted: sourceTrusted ?? this.sourceTrusted,
    updated: updated ?? this.updated,
    error: error,
  );
}

typedef PluginPackageInstaller = Future<bool> Function(String packagePath);

/// Drives one install tab: describe the release, wait for the user's decision,
/// then download, verify and install.
///
/// The decision rules live here rather than in the widget so they hold for any
/// caller: an unreachable-or-withdrawn release never installs, a high severity
/// advisory needs explicit acknowledgement, and a site the user has not used
/// before needs explicit trust.
class PluginInstallController extends StateNotifier<PluginInstallState> {
  PluginInstallController({
    required this.intent,
    required this.client,
    required this.trustedOrigins,
    required this.installPackage,
    required this.ledger,
    this.onRegistryInstalled,
    Future<Directory> Function()? downloadRoot,
  }) : _downloadRoot = downloadRoot ?? _defaultDownloadRoot,
       super(const PluginInstallState());

  final PluginInstallIntent intent;
  final PluginRegistryClient client;
  final TrustedPluginOrigins trustedOrigins;
  final PluginPackageInstaller installPackage;
  final PluginRegistryLedger ledger;

  /// Called after a registry install has been recorded in the ledger.
  final VoidCallback? onRegistryInstalled;
  final Future<Directory> Function() _downloadRoot;

  static Future<Directory> _defaultDownloadRoot() async => Directory(
    path.join((await getTemporaryDirectory()).path, 'pyrite_plugin_downloads'),
  );

  Future<void> load() async {
    final target = intent;
    if (target is! RegistryInstallIntent) {
      state = const PluginInstallState(phase: PluginInstallPhase.ready);
      return;
    }
    state = const PluginInstallState();
    try {
      final trusted = await trustedOrigins.load();
      final release = await client.fetchRelease(target);
      if (!mounted) return;
      state = PluginInstallState(
        phase: PluginInstallPhase.ready,
        release: release,
        sourceTrusted: trusted.contains(target.origin),
      );
    } on Object catch (error) {
      if (mounted) {
        state = PluginInstallState(
          phase: PluginInstallPhase.failed,
          error: error,
        );
      }
    }
  }

  Future<void> retry() => load();

  bool get canInstall {
    final release = state.release;
    return state.phase == PluginInstallPhase.ready &&
        (release == null || release.installable);
  }

  Future<void> install({
    bool trustSource = false,
    bool acknowledged = false,
  }) async {
    if (!canInstall) return;
    final release = state.release;
    if (release != null &&
        release.moderation.requiresAcknowledgement &&
        !acknowledged) {
      return;
    }
    if (!state.sourceTrusted && !trustSource) return;

    final target = intent;
    Directory? workDirectory;
    try {
      if (target is RegistryInstallIntent && release != null) {
        if (!state.sourceTrusted) await trustedOrigins.trust(target.origin);
        state = state.copyWith(
          phase: PluginInstallPhase.installing,
          step: PluginInstallStep.downloading,
          sourceTrusted: true,
        );
        workDirectory = Directory(
          path.join(
            (await _downloadRoot()).path,
            '${DateTime.now().microsecondsSinceEpoch}',
          ),
        );
        final package = await client.downloadPackage(
          target,
          release,
          workDirectory,
        );
        state = state.copyWith(
          phase: PluginInstallPhase.installing,
          step: PluginInstallStep.installing,
        );
        final updated = await installPackage(package.path);
        await _recordProvenance(target, release);
        _finish(updated);
      } else if (target is LocalInstallIntent) {
        state = state.copyWith(
          phase: PluginInstallPhase.installing,
          step: PluginInstallStep.installing,
        );
        _finish(await installPackage(target.packagePath));
      }
    } on Object catch (error) {
      if (mounted) {
        state = state.copyWith(phase: PluginInstallPhase.failed, error: error);
      }
    } finally {
      await _cleanUp(workDirectory);
    }
  }

  /// Remembers where the plugin came from so the IDE can keep checking on it.
  /// The install has already succeeded, so a ledger problem is only logged.
  Future<void> _recordProvenance(
    RegistryInstallIntent target,
    PluginRegistryRelease release,
  ) async {
    try {
      await ledger.recordInstall(
        RegistrySource(
          pluginId: target.pluginId,
          origin: target.origin,
          version: target.version,
        ),
        advisory: PluginAdvisory(
          pluginId: target.pluginId,
          version: target.version,
          installable: release.installable,
          moderation: release.moderation,
        ),
      );
      onRegistryInstalled?.call();
    } on Object catch (error) {
      debugPrint('PluginInstallController: could not record source: $error');
    }
  }

  void _finish(bool updated) {
    if (!mounted) return;
    state = state.copyWith(
      phase: PluginInstallPhase.installed,
      updated: updated,
    );
  }

  Future<void> _cleanUp(Directory? directory) async {
    if (directory == null) return;
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } on FileSystemException {
      // The temp directory is swept by the operating system.
    }
  }
}

final pluginInstallControllerProvider = StateNotifierProvider.autoDispose
    .family<PluginInstallController, PluginInstallState, PluginInstallIntent>((
      ref,
      intent,
    ) {
      final controller = PluginInstallController(
        intent: intent,
        client: PluginRegistryClient(),
        trustedOrigins: TrustedPluginOrigins(),
        installPackage: ref.read(pluginManagerProvider.notifier).install,
        ledger: PluginRegistryLedger(),
        onRegistryInstalled: () =>
            unawaited(ref.read(pluginAdvisoryProvider.notifier).reload()),
      );
      unawaited(controller.load());
      return controller;
    });
