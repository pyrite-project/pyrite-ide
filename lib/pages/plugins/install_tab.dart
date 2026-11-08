import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_install_link.dart';
import 'package:pyrite_ide/core/sdk/plugin_install_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_registry_client.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/pages/plugins/moderation_banner.dart';

/// The confirmation page for installing one plugin, shown as an editor tab.
///
/// It describes only what is about to be installed and from where; the forum
/// topic remains the plugin's detail page.
class PluginInstallTab extends ConsumerStatefulWidget {
  const PluginInstallTab({super.key, required this.intent});

  final PluginInstallIntent intent;

  @override
  ConsumerState<PluginInstallTab> createState() => _PluginInstallTabState();
}

class _PluginInstallTabState extends ConsumerState<PluginInstallTab> {
  bool _trustSource = false;
  bool _acknowledged = false;

  PluginInstallIntent get _intent => widget.intent;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pluginInstallControllerProvider(_intent));
    final controller = ref.read(
      pluginInstallControllerProvider(_intent).notifier,
    );
    final theme = Theme.of(context);
    final release = state.release;

    String t(I18nKey key) => translateForWidget(ref, key);

    final needsTrust = !state.sourceTrusted;
    final needsAcknowledgement =
        release?.moderation.requiresAcknowledgement ?? false;
    final busy = state.phase == PluginInstallPhase.installing;
    final canPress =
        controller.canInstall &&
        (!needsTrust || _trustSource) &&
        (!needsAcknowledgement || _acknowledged);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(intent: _intent, release: release),
                  const SizedBox(height: 16),
                  _SourceRow(
                    intent: _intent,
                    label: t(I18nKey.pluginInstallSource),
                  ),
                  if (release != null && release.permissions.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _Chips(
                      label: t(I18nKey.pluginsDetailPermissions),
                      values: release.permissions,
                    ),
                  ],
                  if (release != null && release.platforms.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _Chips(
                      label: t(I18nKey.pluginsDetailPlatforms),
                      values: release.platforms,
                    ),
                  ],
                  if (release != null && release.moderation.isFlagged) ...[
                    const SizedBox(height: 16),
                    PluginModerationBanner(moderation: release.moderation),
                  ],
                  if (needsTrust && state.phase == PluginInstallPhase.ready)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(t(I18nKey.pluginInstallTrustSource)),
                      subtitle: Text(t(I18nKey.pluginInstallUnknownSource)),
                      value: _trustSource,
                      onChanged: (value) =>
                          setState(() => _trustSource = value ?? false),
                    ),
                  if (needsAcknowledgement &&
                      state.phase == PluginInstallPhase.ready)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(t(I18nKey.pluginInstallAcknowledge)),
                      value: _acknowledged,
                      onChanged: (value) =>
                          setState(() => _acknowledged = value ?? false),
                    ),
                  const SizedBox(height: 16),
                  _Status(state: state),
                  const SizedBox(height: 16),
                  _Actions(
                    state: state,
                    canInstall: canPress,
                    busy: busy,
                    onInstall: () => controller.install(
                      trustSource: _trustSource,
                      acknowledged: _acknowledged,
                    ),
                    onRetry: controller.retry,
                    onClose: () => ref
                        .read(tabbedViewControllerProvider.notifier)
                        .closeTabById(_intent.tabId),
                    blockedText: release != null && !release.installable
                        ? t(I18nKey.pluginInstallBlocked)
                        : null,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.intent, required this.release});

  final PluginInstallIntent intent;
  final PluginRegistryRelease? release;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final target = intent;
    final name =
        release?.name ??
        (target is RegistryInstallIntent
            ? target.pluginId
            : translateForWidget(ref, I18nKey.pluginInstallTabTitleFile));
    final version =
        release?.version ??
        (target is RegistryInstallIntent ? target.version : null);
    final byline = [
      if (target is RegistryInstallIntent) target.pluginId,
      if (release?.author != null) release!.author!,
    ].join(' · ');

    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.extension_outlined,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                version == null ? name : '$name  v$version',
                style: theme.textTheme.titleLarge,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (byline.isNotEmpty)
                Text(
                  byline,
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SourceRow extends ConsumerWidget {
  const _SourceRow({required this.intent, required this.label});

  final PluginInstallIntent intent;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = intent;
    final value = switch (target) {
      RegistryInstallIntent() => target.origin,
      LocalInstallIntent() => target.packagePath,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label  ', style: Theme.of(context).textTheme.bodySmall),
        Expanded(
          child: SelectableText(
            value,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _Chips extends StatelessWidget {
  const _Chips({required this.label, required this.values});

  final String label;
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final value in values)
              Chip(
                label: Text(value, style: theme.textTheme.bodySmall),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ],
    );
  }
}

class _Status extends ConsumerWidget {
  const _Status({required this.state});

  final PluginInstallState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String t(I18nKey key) => translateForWidget(ref, key);

    switch (state.phase) {
      case PluginInstallPhase.loading:
        return _Progress(label: t(I18nKey.pluginInstallLoading));
      case PluginInstallPhase.installing:
        return _Progress(
          label: state.step == PluginInstallStep.downloading
              ? t(I18nKey.pluginInstallDownloading)
              : t(I18nKey.pluginInstallInstalling),
        );
      case PluginInstallPhase.installed:
        return Text(
          state.updated
              ? t(I18nKey.pluginInstallUpdated)
              : t(I18nKey.pluginInstallDone),
          style: TextStyle(color: Theme.of(context).colorScheme.primary),
        );
      case PluginInstallPhase.failed:
        return Text(
          _errorText(ref, state.error),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        );
      case PluginInstallPhase.ready:
        return const SizedBox.shrink();
    }
  }

  static String _errorText(WidgetRef ref, Object? error) {
    if (error is PluginRegistryException) {
      final key = switch (error.code) {
        PluginRegistryErrorCode.unreachable =>
          I18nKey.pluginInstallErrorUnreachable,
        PluginRegistryErrorCode.notFound => I18nKey.pluginInstallErrorNotFound,
        PluginRegistryErrorCode.unavailable =>
          I18nKey.pluginInstallErrorUnavailable,
        PluginRegistryErrorCode.badResponse =>
          I18nKey.pluginInstallErrorBadResponse,
        PluginRegistryErrorCode.tooLarge => I18nKey.pluginInstallErrorTooLarge,
        PluginRegistryErrorCode.hashMismatch =>
          I18nKey.pluginInstallErrorHashMismatch,
      };
      return translateForWidget(ref, key);
    }
    return '${translateForWidget(ref, I18nKey.pluginsInstallFailed)}: $error';
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(height: 8),
        const LinearProgressIndicator(),
      ],
    );
  }
}

class _Actions extends ConsumerWidget {
  const _Actions({
    required this.state,
    required this.canInstall,
    required this.busy,
    required this.onInstall,
    required this.onRetry,
    required this.onClose,
    required this.blockedText,
    required this.style,
  });

  final PluginInstallState state;
  final bool canInstall;
  final bool busy;
  final VoidCallback onInstall;
  final VoidCallback onRetry;
  final VoidCallback onClose;
  final String? blockedText;
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String t(I18nKey key) => translateForWidget(ref, key);

    if (state.phase == PluginInstallPhase.installed) {
      return Align(
        alignment: Alignment.centerRight,
        child: FilledButton(
          onPressed: onClose,
          child: Text(t(I18nKey.pluginInstallCancel)),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (blockedText != null)
          Expanded(child: Text(blockedText!, style: style))
        else
          const Spacer(),
        TextButton(
          onPressed: busy ? null : onClose,
          child: Text(t(I18nKey.pluginInstallCancel)),
        ),
        const SizedBox(width: 8),
        if (state.phase == PluginInstallPhase.failed)
          FilledButton(
            onPressed: onRetry,
            child: Text(t(I18nKey.pluginInstallRetry)),
          )
        else
          FilledButton(
            onPressed: canInstall && !busy ? onInstall : null,
            child: Text(t(I18nKey.pluginInstallAction)),
          ),
      ],
    );
  }
}
