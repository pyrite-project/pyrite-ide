import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/core/constants/corner_radius.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/sdk/activation_manager.dart';
import 'package:pyrite_ide/core/sdk/contribution_registry.dart';
import 'package:pyrite_ide/core/sdk/plugin_config_store.dart';
import 'package:pyrite_ide/core/sdk/plugin_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_metrics.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_resources.dart';
import 'package:pyrite_ide/core/sdk/types.dart';
import 'package:pyrite_ide/core/services/message/ide_message.dart';
import 'package:pyrite_ide/shared/dialog_form_fields.dart';
import 'package:pyrite_ide/shared/md3_widgets.dart';
import 'package:pyrite_ide/shared/studio_text.dart';

/// Monospace family for identifiers, versions and raw setting values.
///
/// Anything a user might copy into a manifest or a bug report is rendered in
/// it, so a value never reads as prose.
const String _monoFont = 'JetBrainsMono';

/// Width of the label column in a detail row, so values line up vertically.
const double _labelWidth = 132;

/// Width of the value control in a setting row. Fixed so every row's control
/// edge lines up, the way a settings editor's input column does.
const double _controlWidth = 160;

/// Height of the settings filter bar's search field.
///
/// The field draws its own box, so this is the control's layout height rather
/// than a measurement of whichever decoration slot happens to be tallest.
const double _filterFieldHeight = 36;

/// Full plugin detail page reached from the plugin center list.
///
/// The plugin center only discovers and manages; everything that describes a
/// single plugin lives here so the list item no longer opens plugin UI.
class PluginDetailPage extends ConsumerWidget {
  const PluginDetailPage({super.key, required this.pluginId});

  final String pluginId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plugin = ref.watch(pluginManagerProvider)[pluginId];
    if (plugin == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: UseText(I18nKey.pluginsDetailMissing)),
      );
    }

    final isRunning = ref.watch(pluginRunManagerProvider)[plugin] != null;
    final activation = ref.watch(activationManagerProvider)[pluginId];
    final manifest = plugin.manifest;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PluginIcon(plugin: plugin, size: 26),
            const SizedBox(width: 10),
            Flexible(child: Text(plugin.name)),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PluginHeader(plugin: plugin, isRunning: isRunning),
                if (manifest == null) ...[
                  const SizedBox(height: 12),
                  const _InvalidManifestBanner(),
                ],
                const SizedBox(height: 20),
                _MetadataSection(
                  plugin: plugin,
                  isRunning: isRunning,
                  activation: activation,
                ),
                if (manifest != null) _ConfigurationSection(pluginId: pluginId),
                _PermissionsSection(plugin: plugin),
                if (manifest != null) _ContributionsSection(pluginId: pluginId),
                _MetricsSection(pluginId: pluginId),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String pluginStatusText(WidgetRef ref, PluginStatus status) {
  final key = switch (status) {
    PluginStatus.usable => I18nKey.pluginsStatusUsable,
    PluginStatus.installing => I18nKey.pluginsStatusInstalling,
    PluginStatus.disabled => I18nKey.pluginsStatusDisabled,
    PluginStatus.uninstalled => I18nKey.pluginsStatusUninstalled,
  };
  return translateForWidget(ref, key);
}

String pluginTypeText(WidgetRef ref, PluginType type) {
  final key = switch (type) {
    PluginType.ui => I18nKey.pluginsTypeUi,
    PluginType.service => I18nKey.pluginsTypeService,
    PluginType.data => I18nKey.pluginsTypeData,
  };
  return translateForWidget(ref, key);
}

/// The MD3 surface every section's rows sit on.
///
/// Shared by the read-only sections so they read as one family of panels
/// instead of each inventing its own card.
class _Surface extends StatelessWidget {
  const _Surface({
    this.padding = const EdgeInsets.all(16),
    required this.child,
  });

  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: context.outerCorners,
      ),
      child: child,
    );
  }
}

/// A label / value line used by the read-only sections.
///
/// Values are monospace by default because most of them are identifiers,
/// versions or raw JSON; [mono] turns that off for prose such as a
/// description.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.mono = true});

  final Widget label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _labelWidth,
            child: DefaultTextStyle.merge(
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              child: label,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: mono ? _monoFont : null,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PluginIcon extends StatelessWidget {
  const _PluginIcon({required this.plugin, required this.size});

  final Plugin plugin;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = context.innerCorners;
    final icons = plugin.manifest?.icons;
    if (icons == null) return _placeholder(scheme, radius);
    return ClipRRect(
      borderRadius: radius,
      child: PluginAssetImage(
        pluginId: plugin.id,
        assetPath: icons.full,
        revision: plugin.version,
        width: size,
        height: size,
        fallback: _placeholder(scheme, radius),
      ),
    );
  }

  Widget _placeholder(ColorScheme scheme, BorderRadius radius) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: scheme.surfaceContainerHighest,
      borderRadius: radius,
    ),
    child: Icon(
      Icons.extension_outlined,
      size: size * 0.55,
      color: scheme.onSurfaceVariant,
    ),
  );
}

/// Extension-page style header: icon, name, status, publisher line and the
/// lifecycle actions that used to float above the body.
class _PluginHeader extends ConsumerWidget {
  const _PluginHeader({required this.plugin, required this.isRunning});

  final Plugin plugin;
  final bool isRunning;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PluginIcon(plugin: plugin, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Text(
                          plugin.name,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        _statusBadge(context, ref),
                        PillBadge(
                          label: pluginTypeText(ref, plugin.type),
                          containerColor: scheme.surfaceContainerHighest,
                          foregroundColor: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _publisherLine,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (plugin.description.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        plugin.description,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Actions(plugin: plugin, isRunning: isRunning),
        ],
      ),
    );
  }

  /// "author · version": the publisher line an extension page leads with.
  String get _publisherLine {
    final parts = <String>[
      if (plugin.author.isNotEmpty) plugin.author,
      plugin.version,
    ];
    return parts.join('  ·  ');
  }

  Widget _statusBadge(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return switch (plugin.status) {
      PluginStatus.disabled => PillBadge(
        label: pluginStatusText(ref, plugin.status),
        containerColor: scheme.surfaceContainerHighest,
        foregroundColor: scheme.onSurfaceVariant,
      ),
      PluginStatus.installing => PillBadge(
        label: pluginStatusText(ref, plugin.status),
        containerColor: scheme.tertiaryContainer,
        foregroundColor: scheme.onTertiaryContainer,
      ),
      PluginStatus.uninstalled => PillBadge(
        label: pluginStatusText(ref, plugin.status),
        containerColor: scheme.errorContainer,
        foregroundColor: scheme.onErrorContainer,
      ),
      PluginStatus.usable =>
        isRunning
            ? PillBadge(
                label: translateForWidget(ref, I18nKey.pluginsDetailRunning),
                icon: Icons.bolt,
                containerColor: scheme.primaryContainer,
                foregroundColor: scheme.onPrimaryContainer,
              )
            : PillBadge(
                label: pluginStatusText(ref, plugin.status),
                containerColor: scheme.secondaryContainer,
                foregroundColor: scheme.onSecondaryContainer,
              ),
    };
  }
}

class _InvalidManifestBanner extends StatelessWidget {
  const _InvalidManifestBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: context.outerCorners,
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 20, color: scheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: UseText(
              I18nKey.pluginsDetailManifestInvalid,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetadataSection extends ConsumerWidget {
  const _MetadataSection({
    required this.plugin,
    required this.isRunning,
    required this.activation,
  });

  final Plugin plugin;
  final bool isRunning;
  final ActivationRecord? activation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final error = activation?.error;
    return SettingsSection(
      title: I18nKey.pluginsDetailOverview,
      description: I18nKey.pluginsDetailOverviewDescription,
      children: [
        _Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoRow(
                label: UseText(I18nKey.pluginsDetailId),
                value: plugin.id,
              ),
              _InfoRow(
                label: UseText(I18nKey.pluginsDetailVersion),
                value: plugin.version,
              ),
              if (plugin.author.isNotEmpty)
                _InfoRow(
                  label: UseText(I18nKey.pluginsDetailAuthor),
                  value: plugin.author,
                  mono: false,
                ),
              _InfoRow(
                label: UseText(I18nKey.pluginsDetailType),
                value: pluginTypeText(ref, plugin.type),
                mono: false,
              ),
              _InfoRow(
                label: UseText(I18nKey.pluginsDetailStatus),
                value: pluginStatusText(ref, plugin.status),
                mono: false,
              ),
              _InfoRow(
                label: UseText(I18nKey.pluginsDetailRunning),
                value: isRunning
                    ? translateForWidget(ref, I18nKey.commonYes)
                    : translateForWidget(ref, I18nKey.commonNo),
                mono: false,
              ),
              if (activation != null)
                _InfoRow(
                  label: UseText(I18nKey.pluginsDetailActivation),
                  value: activation!.state.name,
                ),
              if (plugin.description.isNotEmpty)
                _InfoRow(
                  label: UseText(I18nKey.pluginsDetailDescription),
                  value: plugin.description,
                  mono: false,
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '$error',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                      fontFamily: _monoFont,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PermissionsSection extends ConsumerWidget {
  const _PermissionsSection({required this.plugin});

  final Plugin plugin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final declared = plugin.declaredPermissions;
    return SettingsSection(
      title: I18nKey.pluginsDetailPermissions,
      description: I18nKey.pluginsDetailPermissionsDescription,
      children: [
        _Surface(
          child: declared.isEmpty
              ? UseText(I18nKey.pluginsDetailPermissionsNone)
              : Column(
                  children: [
                    for (final resource in declared.keys.toList()..sort())
                      _InfoRow(
                        label: Text(
                          resource,
                          style: const TextStyle(fontFamily: _monoFont),
                        ),
                        value: (declared[resource]!.toList()..sort()).join(
                          ', ',
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _ContributionsSection extends ConsumerWidget {
  const _ContributionsSection({required this.pluginId});

  final String pluginId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(contributionRegistryProvider);
    final navigation = registry.navigation.all
        .where((entry) => entry.pluginId == pluginId)
        .toList();
    final views = registry.views.all
        .where((entry) => entry.pluginId == pluginId)
        .toList();
    final commands = registry.commands.all
        .where((entry) => entry.pluginId == pluginId)
        .toList();

    return SettingsSection(
      title: I18nKey.pluginsDetailContributions,
      description: I18nKey.pluginsDetailContributionsDescription,
      children: [
        _Surface(
          child: navigation.isEmpty && views.isEmpty && commands.isEmpty
              ? UseText(I18nKey.pluginsDetailContributionsNone)
              : Column(
                  children: [
                    for (final entry in navigation)
                      _InfoRow(
                        label: UseText(I18nKey.pluginsDetailNavigation),
                        value: '${entry.value.title} (${entry.value.id})',
                      ),
                    for (final entry in views)
                      _InfoRow(
                        label: UseText(I18nKey.pluginsDetailViews),
                        value: '${entry.value.title} (${entry.value.id})',
                      ),
                    for (final entry in commands)
                      _InfoRow(
                        label: UseText(I18nKey.pluginsDetailCommands),
                        value: '${entry.value.title} (${entry.value.id})',
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _MetricsSection extends ConsumerWidget {
  const _MetricsSection({required this.pluginId});

  final String pluginId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ref.watch(pluginMetricsProvider).forPlugin(pluginId);
    return SettingsSection(
      title: I18nKey.pluginsDiagnostics,
      description: I18nKey.pluginsDiagnosticsDescription,
      children: [
        _Surface(
          child: metrics == null
              ? UseText(I18nKey.pluginsDiagnosticsEmpty)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoRow(
                      label: UseText(I18nKey.pluginsMetricState),
                      value: metrics.state,
                    ),
                    _InfoRow(
                      label: const Text('Session'),
                      value: metrics.sessionId,
                    ),
                    _InfoRow(
                      label: const Text('Generation'),
                      value: '${metrics.generation}',
                    ),
                    _InfoRow(
                      label: UseText(I18nKey.pluginsMetricActivation),
                      value:
                          '${metrics.activationDuration?.inMilliseconds ?? '-'} ms',
                    ),
                    _InfoRow(
                      label: UseText(I18nKey.pluginsMetricMessages),
                      value: translateForWidgetWithReplacements(
                        ref,
                        I18nKey.pluginsMetricMessagesValue,
                        {
                          'sent': '${metrics.messagesSent}',
                          'received': '${metrics.messagesReceived}',
                        },
                      ),
                    ),
                    _InfoRow(
                      label: const Text('RPC p50 / p95'),
                      value:
                          '${metrics.rpcP50Ms ?? '-'} / ${metrics.rpcP95Ms ?? '-'} ms',
                    ),
                    _InfoRow(
                      label: UseText(I18nKey.pluginsMetricQueue),
                      value:
                          'event ${metrics.eventQueueDepth}/${metrics.eventQueueHighWater}, '
                          'control ${metrics.controlQueueDepth}/${metrics.controlQueueHighWater}, '
                          'patch ${metrics.patchQueueDepth}/${metrics.patchQueueHighWater}',
                    ),
                    _InfoRow(
                      label: UseText(I18nKey.pluginsMetricFailures),
                      value:
                          'timeout ${metrics.timeouts}, cancel ${metrics.cancellations}, '
                          'drop ${metrics.drops}, error ${metrics.errors}',
                    ),
                    if (metrics.lastError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: SelectableText(
                          '${metrics.lastError}\n${metrics.lastTraceback ?? ''}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontFamily: _monoFont,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// The plugin's own settings.
///
/// Laid out the way a settings editor is: a filter bar, then one row per
/// setting with the title on the left, the control on the right, the
/// description under the title and the setting id under that. Every row is
/// editable according to its declared type, and a row whose value differs from
/// its default is marked and can be reset.
class _ConfigurationSection extends ConsumerStatefulWidget {
  const _ConfigurationSection({required this.pluginId});

  final String pluginId;

  @override
  ConsumerState<_ConfigurationSection> createState() =>
      _ConfigurationSectionState();
}

class _ConfigurationSectionState extends ConsumerState<_ConfigurationSection> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  List<Map<String, dynamic>> _items = const [];
  var _loading = true;
  var _onlyModified = false;

  @override
  void initState() {
    super.initState();
    _load(spinner: true);
  }

  @override
  void didUpdateWidget(covariant _ConfigurationSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pluginId != widget.pluginId) {
      _search.clear();
      _onlyModified = false;
      _load(spinner: true);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _load({bool spinner = false}) async {
    if (spinner && mounted) setState(() => _loading = true);
    try {
      final items = await ref
          .read(pluginConfigStoreProvider)
          .list(widget.pluginId);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _loading = false;
      });
    }
  }

  Future<void> _set(String id, Object? value) async {
    try {
      await ref.read(pluginConfigStoreProvider).set(widget.pluginId, id, value);
    } catch (error) {
      if (!mounted) return;
      showIdeError(
        context,
        translateInContextWithReplacements(
          context,
          I18nKey.pluginsDetailSaveFailed,
          {'error': '$error'},
        ),
      );
    }
    await _load();
  }

  int get _modifiedCount => _items.where(_isModified).length;

  List<Map<String, dynamic>> get _visible {
    final query = _search.text.trim().toLowerCase();
    return [
      for (final item in _items)
        if (!_onlyModified || _isModified(item))
          if (query.isEmpty || _matches(item, query)) item,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return SettingsSection(
      title: I18nKey.pluginsDetailConfiguration,
      description: I18nKey.pluginsDetailConfigDescription,
      children: [
        _Surface(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_items.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: _filterBar(context),
                ),
                const Divider(height: 1),
              ],
              // A static placeholder rather than a spinner: the settings load
              // from a local file and finish in well under a frame in
              // practice, and an indeterminate indicator would schedule frames
              // for as long as it stays mounted.
              if (_loading)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: UseText(
                    I18nKey.pluginsDetailLoading,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else if (_items.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: UseText(I18nKey.pluginsDetailConfigurationNone),
                )
              else if (visible.isEmpty)
                const _NoMatch()
              else
                ..._rows(visible),
            ],
          ),
        ),
      ],
    );
  }

  /// One row per visible setting, separated by a hairline.
  ///
  /// Each row closes over its own id and default rather than over a list
  /// index, so a row's callbacks keep pointing at the setting they were built
  /// for even if the visible list changes under them.
  List<Widget> _rows(List<Map<String, dynamic>> items) {
    final rows = <Widget>[];
    for (final item in items) {
      final id = item['id']?.toString() ?? '';
      final fallback = item['default'];
      if (rows.isNotEmpty) rows.add(const Divider(height: 1));
      rows.add(
        _SettingRow(
          item: item,
          onChanged: (value) => _set(id, value),
          onReset: fallback == null ? null : () => _set(id, fallback),
        ),
      );
    }
    return rows;
  }

  /// The settings search box.
  ///
  /// The magnifier and the clear button are plain [Row] children instead of
  /// [InputDecoration] prefix/suffix icons: those slots take part in the
  /// field's height, so a button that only exists while typing would resize
  /// the box. With a collapsed decoration the row alone decides the layout,
  /// and the box keeps one height in every state.
  Widget _searchField(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListenableBuilder(
      listenable: _searchFocus,
      // Only the border colour depends on focus, so the row is built once and
      // reused while the box decoration is rebuilt.
      builder: (context, child) => Container(
        height: _filterFieldHeight,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: context.innerCorners,
        ),
        // Painted over the fill instead of insetting the child: gaining focus
        // must not nudge the text by the border width.
        foregroundDecoration: BoxDecoration(
          borderRadius: context.innerCorners,
          border: Border.all(
            color: _searchFocus.hasFocus ? scheme.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: child,
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          Icon(Icons.search, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _search,
              focusNode: _searchFocus,
              style: theme.textTheme.bodySmall,
              decoration: InputDecoration.collapsed(
                hintText: translateForWidget(
                  ref,
                  I18nKey.pluginsDetailSearchSettings,
                ),
                hintStyle: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (_search.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              tooltip: translateForWidget(ref, I18nKey.commonClose),
              onPressed: () {
                _search.clear();
                setState(() {});
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _filterBar(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Expanded(child: _searchField(context)),
        const SizedBox(width: 10),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            textStyle: theme.textTheme.labelSmall,
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 10),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            side: BorderSide(color: scheme.outlineVariant),
          ),
          segments: [
            ButtonSegment<bool>(
              value: false,
              label: UseText(I18nKey.pluginsDetailFilterAll),
            ),
            ButtonSegment<bool>(
              value: true,
              label: Text(
                '${translateForWidget(ref, I18nKey.pluginsDetailFilterModified)}'
                ' · $_modifiedCount',
              ),
            ),
          ],
          selected: {_onlyModified},
          onSelectionChanged: (next) =>
              setState(() => _onlyModified = next.first),
        ),
      ],
    );
  }

  static bool _isModified(Map<String, dynamic> item) =>
      jsonEncode(item['value']) != jsonEncode(item['default']);

  static bool _matches(Map<String, dynamic> item, String query) {
    for (final key in const ['title', 'id', 'description', 'type']) {
      if ((item[key]?.toString().toLowerCase() ?? '').contains(query)) {
        return true;
      }
    }
    return false;
  }
}

class _NoMatch extends StatelessWidget {
  const _NoMatch();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 28),
      child: Column(
        children: [
          Icon(
            Icons.filter_alt_off_outlined,
            size: 28,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(height: 10),
          UseText(
            I18nKey.pluginsDetailNoMatch,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          UseText(
            I18nKey.pluginsDetailNoMatchHint,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Uniform placeholder shown instead of a stored password. A fixed length so
/// even the value's length is not revealed.
const String _passwordMask = '••••••••';

/// One setting: title, description, id, then the control for its type.
///
/// Visual hierarchy follows the settings editor: the title is the strongest
/// element, the description is secondary, and the setting id is tertiary and
/// dim. A row whose value differs from the declaration's default shows a
/// leading reset affordance so it can be restored in one click.
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.item,
    required this.onChanged,
    required this.onReset,
  });

  final Map<String, dynamic> item;
  final ValueChanged<Object?> onChanged;
  final VoidCallback? onReset;

  String get _id => item['id']?.toString() ?? '';
  String get _title => (item['title']?.toString() ?? '').isEmpty
      ? _id
      : item['title']!.toString();
  String get _type => item['type']?.toString() ?? 'string';
  String get _description => item['description']?.toString() ?? '';
  Object? get _value => item['value'];
  Object? get _default => item['default'];
  bool get _isPassword => _type == 'password';

  List<Object?> get _enumValues =>
      (item['enum'] as List<dynamic>?)?.cast<Object?>() ?? const [];

  bool get _modified => jsonEncode(_value) != jsonEncode(_default);

  /// Text the row shows for its current value. Passwords never render their
  /// underlying string.
  String get _valueText {
    if (_isPassword) {
      final text = _value?.toString() ?? '';
      return text.isEmpty ? '' : _passwordMask;
    }
    return _display(_value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final modified = _modified;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(13, 10, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_description.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    _description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 5),
                Text(
                  _id,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontFamily: _monoFont,
                    color: scheme.outline,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Reset sits immediately left of the control it restores; absent
          // on untouched rows so only the gap distinguishes them.
          if (modified && onReset != null) ...[
            IconButton(
              icon: const Icon(Icons.restart_alt, size: 18),
              tooltip: translateInContext(
                context,
                I18nKey.pluginsDetailResetToDefault,
              ),
              onPressed: onReset,
              color: scheme.primary,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 6),
          ],
          _control(context),
        ],
      ),
    );
  }

  Widget _control(BuildContext context) {
    if (_type == 'boolean') {
      return Switch(value: _value == true, onChanged: onChanged);
    }
    if (_enumValues.isNotEmpty) return _enumControl(context);
    return _valueButton(context);
  }

  /// A select box for a declared `enum`, matching the values the store will
  /// accept.
  Widget _enumControl(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final encoded = jsonEncode(_value);
    Object? selected;
    for (final candidate in _enumValues) {
      if (jsonEncode(candidate) == encoded) {
        selected = candidate;
        break;
      }
    }
    return Container(
      constraints: const BoxConstraints(
        maxWidth: _controlWidth + 20,
        minHeight: 28,
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(10, 0, 4, 0),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: context.innerCorners,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: DropdownButton<Object?>(
        value: selected,
        isDense: true,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        icon: Icon(
          Icons.arrow_drop_down,
          size: 18,
          color: scheme.onSurfaceVariant,
        ),
        style: theme.textTheme.bodySmall?.copyWith(
          fontFamily: _monoFont,
          color: scheme.onSurface,
        ),
        hint: Text(
          translateInContext(context, I18nKey.pluginsDetailUnset),
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        items: [
          for (final candidate in _enumValues)
            DropdownMenuItem<Object?>(
              value: candidate,
              child: Text(
                _display(candidate),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }

  /// An input-box-looking button for string / number / password / array /
  /// object values.
  ///
  /// Long or structured values open a dialog; the row itself stays single
  /// line so a settings list keeps a constant row height. Passwords render
  /// their fixed mask instead of the stored string.
  Widget _valueButton(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final empty =
        _value == null || (_isPassword && (_value?.toString() ?? '').isEmpty);
    return OutlinedButton(
      onPressed: () => _openEditor(context),
      style: OutlinedButton.styleFrom(
        foregroundColor: empty ? scheme.onSurfaceVariant : scheme.onSurface,
        backgroundColor: scheme.surfaceContainerHighest,
        minimumSize: const Size(0, 28),
        padding: const EdgeInsetsDirectional.fromSTEB(10, 0, 8, 0),
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: context.innerCorners),
        textStyle: theme.textTheme.bodySmall?.copyWith(fontFamily: _monoFont),
      ),
      child: SizedBox(
        width: _controlWidth,
        child: Row(
          children: [
            Expanded(
              child: Text(
                empty
                    ? translateInContext(context, I18nKey.pluginsDetailUnset)
                    : (_isPassword ? _passwordMask : _valueText),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              _isPassword ? Icons.key_outlined : Icons.edit_outlined,
              size: 14,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEditor(BuildContext context) async {
    if (_type == 'array' || _type == 'object') {
      await _editJson(context);
      return;
    }
    await _editScalar(context);
  }

  Future<void> _editScalar(BuildContext context) async {
    final numeric = _type == 'integer' || _type == 'number';
    // The reveal toggle lives in this closure so the dialog's StatefulBuilder
    // can flip it without the row itself holding dialog-only state.
    var revealPassword = false;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => DialogFormFields(
        initialValues: [_value?.toString() ?? ''],
        selectAll: true,
        builder: (context, controllers) {
          final theme = Theme.of(context);
          final scheme = theme.colorScheme;
          return AlertDialog(
            title: UseText(
              _isPassword
                  ? I18nKey.pluginsDetailEditPassword
                  : I18nKey.pluginsDetailEditValue,
            ),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _id,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFamily: _monoFont,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (_description.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      _description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  StatefulBuilder(
                    builder: (context, setDialogState) => TextField(
                      controller: controllers[0],
                      autofocus: true,
                      obscureText: _isPassword && !revealPassword,
                      autocorrect: false,
                      enableSuggestions: !_isPassword,
                      keyboardType: numeric ? TextInputType.number : null,
                      decoration: InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: context.innerCorners,
                        ),
                        suffixIcon: _isPassword
                            ? IconButton(
                                icon: Icon(
                                  revealPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 18,
                                ),
                                tooltip: translateInContext(
                                  context,
                                  revealPassword
                                      ? I18nKey.pluginsDetailHidePassword
                                      : I18nKey.pluginsDetailShowPassword,
                                ),
                                onPressed: () => setDialogState(
                                  () => revealPassword = !revealPassword,
                                ),
                              )
                            : null,
                      ),
                      onSubmitted: (text) => Navigator.of(context).pop(text),
                    ),
                  ),
                  if (_default != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      translateInContextWithReplacements(
                        context,
                        I18nKey.pluginsDetailDefaultValue,
                        {
                          'value': _isPassword
                              ? _passwordMask
                              : _display(_default),
                        },
                      ),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontFamily: _monoFont,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: UseText(I18nKey.commonCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(controllers[0].text),
                child: UseText(I18nKey.pluginsDetailSave),
              ),
            ],
          );
        },
      ),
    );
    if (result == null || !context.mounted) return;
    Object? parsed = result;
    if (_type == 'integer') {
      parsed = int.tryParse(result.trim());
      if (parsed == null) {
        showIdeError(
          context,
          translateInContext(context, I18nKey.pluginsDetailInvalidInteger),
        );
        return;
      }
    } else if (_type == 'number') {
      parsed = num.tryParse(result.trim());
      if (parsed == null) {
        showIdeError(
          context,
          translateInContext(context, I18nKey.pluginsDetailInvalidNumber),
        );
        return;
      }
    }
    onChanged(parsed);
  }

  Future<void> _editJson(BuildContext context) async {
    const encoder = JsonEncoder.withIndent('  ');
    final seed =
        _value ?? (_type == 'array' ? <Object?>[] : <String, Object?>{});
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => DialogFormFields(
        initialValues: [encoder.convert(seed)],
        builder: (context, controllers) {
          final theme = Theme.of(context);
          final scheme = theme.colorScheme;
          return AlertDialog(
            title: UseText(I18nKey.pluginsDetailEditJson),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _id,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFamily: _monoFont,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 260,
                    child: TextField(
                      controller: controllers[0],
                      autofocus: true,
                      expands: true,
                      maxLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: _monoFont,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(
                          borderRadius: context.innerCorners,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: UseText(I18nKey.commonCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(controllers[0].text),
                child: UseText(I18nKey.pluginsDetailSave),
              ),
            ],
          );
        },
      ),
    );
    if (result == null || !context.mounted) return;
    Object? decoded;
    try {
      decoded = jsonDecode(result);
    } catch (error) {
      showIdeError(
        context,
        translateInContextWithReplacements(
          context,
          I18nKey.pluginsDetailInvalidJson,
          {'error': '$error'},
        ),
      );
      return;
    }
    final wrongShape =
        (_type == 'array' && decoded is! List) ||
        (_type == 'object' && decoded is! Map);
    if (wrongShape) {
      showIdeError(
        context,
        translateInContextWithReplacements(
          context,
          I18nKey.pluginsDetailInvalidJson,
          {'error': _type},
        ),
      );
      return;
    }
    onChanged(decoded);
  }

  String _display(Object? value) {
    if (value == null) return 'null';
    if (value is String) return value;
    return jsonEncode(value);
  }
}

class _Actions extends ConsumerWidget {
  const _Actions({required this.plugin, required this.isRunning});

  final Plugin plugin;
  final bool isRunning;

  /// Only UI plugins have a navigation container to open.
  bool get _canOpen =>
      plugin.type == PluginType.ui &&
      plugin.status == PluginStatus.usable &&
      plugin.manifest != null &&
      plugin.manifest!.contributes.navigationContainers.isNotEmpty;

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final container = plugin.manifest!.contributes.navigationContainers.first;
    final view = plugin.manifest!.contributes.views
        .where((entry) => entry.container == container.id)
        .firstOrNull;
    await ref
        .read(activationManagerProvider.notifier)
        .activateForView(plugin, view?.id ?? container.id);
    if (!context.mounted) return;
    context.push(
      Uri(
        path: '/plugin-view',
        queryParameters: {
          'plugin': plugin.id,
          'container': container.id,
          if (view != null) 'view': view.id,
        },
      ).toString(),
    );
  }

  /// Enabling revalidates the manifest, so it can fail with a conflict or a
  /// schema error. Surface that instead of dropping it into an async gap.
  Future<void> _changeStatus(
    BuildContext context,
    WidgetRef ref,
    PluginStatus status,
  ) async {
    try {
      await ref
          .read(pluginManagerProvider.notifier)
          .changeStatus(plugin.id, status);
    } catch (error) {
      if (context.mounted) showIdeError(context, '$error');
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: UseText(I18nKey.pluginsConfirmDeleteTitle),
        content: Text(
          translateForWidget(
            ref,
            I18nKey.pluginsConfirmDeleteMessage,
          ).replaceAll('{name}', plugin.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: UseText(I18nKey.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: UseText(I18nKey.pluginsActionDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(pluginManagerProvider.notifier).uninstall(plugin.id);
      if (context.mounted) context.pop();
    } catch (error) {
      if (context.mounted) {
        showIdeError(
          context,
          '${translateForWidget(ref, I18nKey.pluginsUninstallFailed)}: $error',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isUsable = plugin.status == PluginStatus.usable;
    final isService = plugin.type == PluginType.service;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (_canOpen)
          FilledButton.icon(
            onPressed: () => unawaited(_open(context, ref)),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: UseText(I18nKey.pluginsActionOpen),
          ),
        if (isUsable)
          OutlinedButton.icon(
            onPressed: () =>
                unawaited(_changeStatus(context, ref, PluginStatus.disabled)),
            icon: const Icon(Icons.pause_circle_outline, size: 18),
            label: UseText(I18nKey.pluginsActionDisable),
          ),
        if (plugin.status == PluginStatus.disabled)
          OutlinedButton.icon(
            onPressed: () =>
                unawaited(_changeStatus(context, ref, PluginStatus.usable)),
            icon: const Icon(Icons.play_circle_outline, size: 18),
            label: UseText(I18nKey.pluginsActionEnable),
          ),
        if (isUsable && isService && !isRunning)
          OutlinedButton.icon(
            onPressed: () =>
                ref.read(pluginRunManagerProvider.notifier).start(plugin),
            icon: const Icon(Icons.play_arrow, size: 18),
            label: UseText(I18nKey.pluginsActionStart),
          ),
        if (isUsable && isService && isRunning)
          OutlinedButton.icon(
            onPressed: () => unawaited(
              ref.read(pluginRunManagerProvider.notifier).stop(plugin),
            ),
            icon: const Icon(Icons.stop, size: 18),
            label: UseText(I18nKey.pluginsActionStop),
          ),
        if (isUsable)
          OutlinedButton.icon(
            onPressed: () =>
                ref.read(pluginManagerProvider.notifier).restart(plugin),
            icon: const Icon(Icons.refresh, size: 18),
            label: UseText(I18nKey.pluginsActionRestart),
          ),
        OutlinedButton.icon(
          onPressed: () => unawaited(_confirmDelete(context, ref)),
          style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
          icon: const Icon(Icons.delete_outline, size: 18),
          label: UseText(I18nKey.pluginsActionDelete),
        ),
      ],
    );
  }
}
