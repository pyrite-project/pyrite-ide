import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_registry_client.dart';

/// What a registry says about a plugin release: a notice, a deprecation, a
/// security advisory or a withdrawal, in the colour that matches its weight.
class PluginModerationBanner extends ConsumerWidget {
  const PluginModerationBanner({super.key, required this.moderation});

  final PluginModeration moderation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSeriousModeration(moderation)
            ? scheme.errorContainer
            : scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            pluginModerationTitle(ref, moderation),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if ((moderation.message ?? '').isNotEmpty) Text(moderation.message!),
        ],
      ),
    );
  }
}

const _levelKeys = {
  'notice': I18nKey.pluginInstallLevelNotice,
  'deprecated': I18nKey.pluginInstallLevelDeprecated,
  'advisory': I18nKey.pluginInstallLevelAdvisory,
  'withdrawn': I18nKey.pluginInstallLevelWithdrawn,
  'delisted': I18nKey.pluginInstallLevelDelisted,
  'takedown': I18nKey.pluginInstallLevelTakedown,
};

const _severityKeys = {
  'low': I18nKey.pluginInstallSeverityLow,
  'moderate': I18nKey.pluginInstallSeverityModerate,
  'high': I18nKey.pluginInstallSeverityHigh,
  'critical': I18nKey.pluginInstallSeverityCritical,
};

/// Advisories and removals read as warnings; notices and deprecations as hints.
bool isSeriousModeration(PluginModeration moderation) => const {
  'advisory',
  'withdrawn',
  'delisted',
  'takedown',
}.contains(moderation.level);

/// "High · Security advisory": severity first, then what kind of notice it is.
String pluginModerationTitle(WidgetRef ref, PluginModeration moderation) =>
    pluginModerationTitleWith(
      (key) => translateForWidget(ref, key),
      moderation,
    );

/// [pluginModerationTitle] for callers without a widget: [translate] resolves
/// an i18n key to text.
String pluginModerationTitleWith(
  String Function(I18nKey key) translate,
  PluginModeration moderation,
) {
  final levelKey = _levelKeys[moderation.level];
  final severityKey = _severityKeys[moderation.severity];
  return [
    if (severityKey != null) translate(severityKey),
    if (levelKey != null) translate(levelKey) else moderation.level,
  ].join(' · ');
}
