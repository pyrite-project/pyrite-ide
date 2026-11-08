import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/sdk/plugin_advisory_provider.dart';
import 'package:pyrite_ide/pages/plugins/moderation_banner.dart';

/// A small warning mark beside a plugin's name when the registry it was
/// installed from has flagged that release. Nothing is shown otherwise.
class PluginAdvisoryBadge extends ConsumerWidget {
  const PluginAdvisoryBadge({super.key, required this.pluginId});

  final String pluginId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final advisory = ref.watch(
      pluginAdvisoryProvider.select((state) => state.flaggedFor(pluginId)),
    );
    if (advisory == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final moderation = advisory.moderation;
    final message = [
      pluginModerationTitle(ref, moderation),
      if ((moderation.message ?? '').isNotEmpty) moderation.message!,
    ].join('\n');
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Tooltip(
        message: message,
        child: Icon(
          isSeriousModeration(moderation)
              ? Icons.warning_amber_rounded
              : Icons.info_outline,
          size: 18,
          color: isSeriousModeration(moderation)
              ? scheme.error
              : scheme.tertiary,
        ),
      ),
    );
  }
}
