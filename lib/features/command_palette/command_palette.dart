import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/constants/corner_radius.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/sdk/command_service.dart';
import 'package:pyrite_ide/core/sdk/contribution_registry.dart';
import 'package:pyrite_ide/core/sdk/menu_resolver.dart';
import 'package:pyrite_ide/core/sdk/plugin_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/types.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/core/services/message/ide_message.dart';
import 'package:pyrite_ide/core/services/search/project_file_index.dart';
import 'package:pyrite_ide/features/command_palette/builtin_entries.dart';
import 'package:pyrite_ide/features/command_palette/palette_entry.dart';
import 'package:pyrite_ide/features/command_palette/palette_recent.dart';
import 'package:pyrite_ide/features/command_palette/palette_search.dart';

/// Maximum number of rows a single section contributes.
const int paletteSectionLimit = 50;

/// The state of the project file index as the palette renders it.
///
/// The dialog normally derives this from [projectFileIndexProvider]; widget
/// tests and previews can construct one directly so they do not need a real
/// workspace on disk.
enum PaletteFileIndexStatus { loading, ready, empty, noProject, error }

class PaletteFileIndexState {
  const PaletteFileIndexState({
    required this.status,
    this.files = const <ProjectFileEntry>[],
    this.error,
    this.truncated = false,
    this.limit = projectFileIndexLimit,
    this.onRetry,
  });

  factory PaletteFileIndexState.loading() =>
      const PaletteFileIndexState(status: PaletteFileIndexStatus.loading);

  factory PaletteFileIndexState.empty() =>
      const PaletteFileIndexState(status: PaletteFileIndexStatus.empty);

  factory PaletteFileIndexState.noProject() =>
      const PaletteFileIndexState(status: PaletteFileIndexStatus.noProject);

  factory PaletteFileIndexState.ready(
    List<ProjectFileEntry> files, {
    bool truncated = false,
    int limit = projectFileIndexLimit,
  }) => PaletteFileIndexState(
    status: PaletteFileIndexStatus.ready,
    files: files,
    truncated: truncated,
    limit: limit,
  );

  factory PaletteFileIndexState.failure(
    Object error, {
    VoidCallback? onRetry,
  }) => PaletteFileIndexState(
    status: PaletteFileIndexStatus.error,
    error: error,
    onRetry: onRetry,
  );

  final PaletteFileIndexStatus status;

  /// Indexed files; only meaningful when [status] is
  /// [PaletteFileIndexStatus.ready].
  final List<ProjectFileEntry> files;

  /// The error behind [PaletteFileIndexStatus.error].
  final Object? error;

  /// Whether the index stopped before visiting every project file.
  final bool truncated;

  /// The index bound shown by the truncation hint.
  final int limit;

  final VoidCallback? onRetry;
}

/// Opens the command palette above the current route.
///
/// [mode] biases the ranking: [PaletteLaunchMode.commands] (the default, bound
/// to `Cmd/Ctrl+Shift+P`) puts commands and navigation first, while
/// [PaletteLaunchMode.files] (bound to `Cmd/Ctrl+P`) puts project files first.
/// A query starting with `>` always hides project files.
///
/// [entries] and [fileIndexState] exist so tests and previews can drive the
/// dialog without a real plugin runtime or project; production callers leave
/// them null.
Future<void> showCommandPalette(
  BuildContext context, {
  PaletteLaunchMode mode = PaletteLaunchMode.commands,
  List<PaletteEntry>? entries,
  PaletteFileIndexState? fileIndexState,
  CommandPaletteHooks hooks = const CommandPaletteHooks(),
  String initialQuery = '',
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => CommandPaletteDialog(
      mode: mode,
      entries: entries,
      fileIndexState: fileIndexState,
      hooks: hooks,
      initialQuery: initialQuery,
    ),
  );
}

/// The palette dialog itself.
///
/// Exposed separately from [showCommandPalette] so widget tests can inject
/// explicit entries and file-index state.
class CommandPaletteDialog extends ConsumerStatefulWidget {
  const CommandPaletteDialog({
    super.key,
    this.mode = PaletteLaunchMode.commands,
    this.entries,
    this.fileIndexState,
    this.hooks = const CommandPaletteHooks(),
    this.initialQuery = '',
  });

  final PaletteLaunchMode mode;

  /// Overrides the built-in/plugin entries. Project files still come from
  /// [fileIndexState].
  final List<PaletteEntry>? entries;

  /// Overrides the provider-backed project file index.
  final PaletteFileIndexState? fileIndexState;

  final CommandPaletteHooks hooks;
  final String initialQuery;

  @override
  ConsumerState<CommandPaletteDialog> createState() =>
      _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends ConsumerState<CommandPaletteDialog> {
  late final TextEditingController _queryController;
  late final FocusNode _focusNode;

  final Map<String, GlobalKey> _rowKeys = {};
  List<GlobalKey> _selectableKeys = const [];
  List<PaletteEntry> _selectableEntries = const [];
  int _selectedIndex = 0;
  int _paintedSelectedIndex = -1;
  bool _revealSelection = false;
  String? _executingId;

  // Identity cache: the provider hands out the same list until the workspace
  // or its contents change, so mapping it to entries once per change keeps
  // typing cheap even when the index holds thousands of files.
  List<ProjectFileEntry>? _cachedFileSource;
  List<PaletteEntry> _cachedFileEntries = const [];

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: widget.initialQuery);
    _focusNode = FocusNode(debugLabel: 'command palette search');
  }

  @override
  void dispose() {
    _queryController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fileState = _resolveFileIndexState();
    final entries = _collectEntries(context, fileState);
    final recentIds = ref.watch(recentPaletteIdsProvider);
    final rawQuery = _queryController.text;
    final effectiveQuery = paletteEffectiveQuery(rawQuery);
    final forceCommands = paletteForcesCommands(rawQuery);
    final sections = _buildSections(
      context: context,
      entries: entries,
      fileState: fileState,
      recentIds: recentIds,
      effectiveQuery: effectiveQuery,
      forceCommands: forceCommands,
    );

    final selectable = <PaletteEntry>[
      for (final section in sections) ...section.entries,
    ];
    final selectedIndex = selectable.isEmpty
        ? -1
        : _selectedIndex.clamp(0, selectable.length - 1);

    final children = <Widget>[];
    final selectableKeys = <GlobalKey>[];
    for (final section in sections) {
      final showSection =
          section.entries.isNotEmpty || section.leading.isNotEmpty;
      if (!showSection) continue;
      children.add(_sectionHeader(context, section.title));
      children.addAll(section.leading);
      for (final entry in section.entries) {
        final index = selectableKeys.length;
        final key = _rowKeys.putIfAbsent(
          '${section.keyPrefix}:${entry.id}',
          GlobalKey.new,
        );
        selectableKeys.add(key);
        children.add(
          _entryTile(entry: entry, selected: index == selectedIndex, key: key),
        );
      }
      children.addAll(section.trailing);
    }

    final hasContent =
        selectable.isNotEmpty ||
        sections.any((section) => section.leading.isNotEmpty);
    _selectableEntries = selectable;
    _selectableKeys = selectableKeys;
    _paintedSelectedIndex = selectedIndex;
    _scheduleRevealSelection();

    final width = math.min(MediaQuery.sizeOf(context).width * 0.8, 640.0);
    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: context.outerCorners),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: 480),
        child: CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                _moveSelection(1),
            const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                _moveSelection(-1),
            const SingleActivator(LogicalKeyboardKey.pageDown): () =>
                _moveSelection(10),
            const SingleActivator(LogicalKeyboardKey.pageUp): () =>
                _moveSelection(-10),
            // Enter intentionally stays with the text field: the engine turns
            // it into a `done` action on platforms where a physical Enter
            // submits, and handling the raw key here as well would run the
            // selected command twice.
            const SingleActivator(LogicalKeyboardKey.escape): _close,
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _searchField(theme, forceCommands),
              Divider(height: 1, color: theme.dividerColor),
              Flexible(
                child: hasContent
                    ? ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        children: children,
                      )
                    : _emptyState(context, fileState, forceCommands),
              ),
              Divider(height: 1, color: theme.dividerColor),
              _footer(context, theme, forceCommands),
            ],
          ),
        ),
      ),
    );
  }

  PaletteFileIndexState _resolveFileIndexState() {
    final injected = widget.fileIndexState;
    if (injected != null) return injected;
    if (widget.entries != null) return PaletteFileIndexState.empty();
    final root = ref.watch(fileProvider);
    if (root == null) return PaletteFileIndexState.noProject();
    final projectFiles = ref.watch(projectFileIndexProvider);
    return projectFiles.when(
      data: (files) => files.isEmpty
          ? PaletteFileIndexState.empty()
          : PaletteFileIndexState.ready(
              files,
              truncated: files.length >= projectFileIndexLimit,
            ),
      loading: PaletteFileIndexState.loading,
      error: (error, stackTrace) => PaletteFileIndexState.failure(
        error,
        onRetry: () => ref.invalidate(projectFileIndexProvider),
      ),
    );
  }

  List<PaletteEntry> _collectEntries(
    BuildContext context,
    PaletteFileIndexState fileState,
  ) {
    final base = widget.entries != null
        ? widget.entries!
        : <PaletteEntry>[
            ...buildBuiltinPaletteEntries(context, ref, hooks: widget.hooks),
            ..._pluginEntries(),
          ];
    final files = fileState.status == PaletteFileIndexStatus.ready
        ? _fileEntriesFor(fileState.files)
        : const <PaletteEntry>[];
    return [...base, ...files];
  }

  List<PaletteEntry> _fileEntriesFor(List<ProjectFileEntry> files) {
    if (!identical(_cachedFileSource, files)) {
      _cachedFileSource = files;
      _cachedFileEntries = buildFilePaletteEntries(files);
    }
    return _cachedFileEntries;
  }

  List<PaletteEntry> _pluginEntries() {
    final plugins = ref.watch(pluginManagerProvider);
    final usablePluginIds = <String>{
      for (final plugin in plugins.values)
        if (plugin.status == PluginStatus.usable) plugin.id,
    };
    if (usablePluginIds.isEmpty) return const <PaletteEntry>[];

    final registry = ref.watch(contributionRegistryProvider);
    final resolver = ref.watch(menuResolverProvider);
    final entries = <String, PaletteEntry>{};

    void add({
      required String commandId,
      required String title,
      required bool enabled,
    }) {
      final key = commandId.toLowerCase();
      if (entries.containsKey(key)) return;
      entries[key] = PaletteEntry(
        id: 'plugin:$commandId',
        title: title,
        category: PaletteCategory.command,
        icon: Icons.extension_outlined,
        enabled: enabled,
        onSelect: (context, ref) =>
            ref.read(commandServiceProvider).execute(commandId),
      );
    }

    for (final item in resolver.resolve(
      location: MenuResolver.commandPalette,
      enabledPluginIds: usablePluginIds,
    )) {
      add(
        commandId: item.commandId,
        title: item.title,
        enabled: item.enabled && resolver.isCommandEnabled(item.commandId),
      );
    }
    for (final contribution in registry.commands.visible) {
      if (!usablePluginIds.contains(contribution.pluginId)) continue;
      final command = contribution.value;
      add(
        commandId: command.id,
        title: command.title,
        enabled: resolver.isCommandEnabled(command.id),
      );
    }
    return entries.values.toList(growable: false);
  }

  List<_PaletteSectionData> _buildSections({
    required BuildContext context,
    required List<PaletteEntry> entries,
    required PaletteFileIndexState fileState,
    required List<String> recentIds,
    required String effectiveQuery,
    required bool forceCommands,
  }) {
    final ranked = rankPaletteEntries(
      entries,
      query: _queryController.text,
      mode: widget.mode,
      recentIds: recentIds,
    );
    final buckets = <PaletteCategory, List<PaletteEntry>>{
      for (final category in PaletteCategory.values) category: <PaletteEntry>[],
    };
    for (final entry in ranked) {
      buckets[entry.category]!.add(entry);
    }

    final sections = <_PaletteSectionData>[];
    if (effectiveQuery.isEmpty && recentIds.isNotEmpty) {
      final byId = <String, PaletteEntry>{
        for (final entry in entries) entry.id: entry,
      };
      final recents = <PaletteEntry>[];
      for (final id in recentIds) {
        final entry = byId[id];
        if (entry == null) continue;
        if (widget.mode == PaletteLaunchMode.files) {
          if (entry.category != PaletteCategory.file) continue;
        } else if (entry.category == PaletteCategory.file) {
          continue;
        }
        recents.add(entry);
        if (recents.length >= maxRecentPaletteEntries) break;
      }
      if (recents.isNotEmpty) {
        sections.add(
          _PaletteSectionData(
            title: I18nKey.paletteSectionRecent,
            keyPrefix: 'recent',
            entries: recents,
          ),
        );
      }
    }

    sections.add(
      _PaletteSectionData(
        title: I18nKey.paletteSectionCommands,
        keyPrefix: 'commands',
        entries: buckets[PaletteCategory.command]!
            .take(paletteSectionLimit)
            .toList(growable: false),
      ),
    );

    if (!forceCommands) {
      final showFileStatus =
          effectiveQuery.isEmpty ||
          widget.mode == PaletteLaunchMode.files ||
          fileState.status == PaletteFileIndexStatus.error;
      final leading = <Widget>[];
      final trailing = <Widget>[];
      final status = _fileStatusWidget(context, fileState);
      if (status != null && showFileStatus) leading.add(status);
      final files = buckets[PaletteCategory.file]!
          .take(paletteSectionLimit)
          .toList(growable: false);
      if (showFileStatus && fileState.truncated && files.isNotEmpty) {
        trailing.add(_truncationHint(context, fileState));
      }
      if (files.isNotEmpty || leading.isNotEmpty) {
        sections.add(
          _PaletteSectionData(
            title: I18nKey.paletteSectionFiles,
            keyPrefix: 'files',
            entries: files,
            leading: leading,
            trailing: trailing,
          ),
        );
      }
    }

    sections.add(
      _PaletteSectionData(
        title: I18nKey.paletteSectionNavigation,
        keyPrefix: 'navigation',
        entries: buckets[PaletteCategory.navigation]!
            .take(paletteSectionLimit)
            .toList(growable: false),
      ),
    );
    sections.add(
      _PaletteSectionData(
        title: I18nKey.paletteSectionSettings,
        keyPrefix: 'settings',
        entries: buckets[PaletteCategory.setting]!
            .take(paletteSectionLimit)
            .toList(growable: false),
      ),
    );

    return sections
        .where(
          (section) =>
              section.entries.isNotEmpty ||
              section.leading.isNotEmpty ||
              section.trailing.isNotEmpty,
        )
        .toList(growable: false);
  }

  Widget _searchField(ThemeData theme, bool forceCommands) {
    final hint = translateForWidget(
      ref,
      forceCommands || widget.mode == PaletteLaunchMode.files
          ? I18nKey.paletteFileModeHint
          : I18nKey.paletteSearchHint,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      child: Row(
        children: [
          Icon(
            Icons.search,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _queryController,
              focusNode: _focusNode,
              autofocus: true,
              maxLines: 1,
              textInputAction: TextInputAction.go,
              style: theme.textTheme.titleMedium,
              onChanged: (value) => setState(() {
                _selectedIndex = 0;
                _revealSelection = true;
                _rowKeys.clear();
              }),
              onSubmitted: (_) => _executeSelected(),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.7,
                  ),
                ),
              ),
            ),
          ),
          if (forceCommands)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                translateForWidget(ref, I18nKey.paletteCommandsOnlyHint),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context, ThemeData theme, bool forceCommands) {
    final hint = forceCommands
        ? I18nKey.paletteCommandsOnlyHint
        : widget.mode == PaletteLaunchMode.files
        ? I18nKey.paletteFileModeHint
        : I18nKey.paletteSearchHint;
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              translateForWidget(ref, hint),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            translateForWidget(ref, I18nKey.paletteShortcutHint),
            style: style,
          ),
        ],
      ),
    );
  }

  Widget _emptyState(
    BuildContext context,
    PaletteFileIndexState fileState,
    bool forceCommands,
  ) {
    final theme = Theme.of(context);
    // A loading index is still progress; showing "no matches" over it would
    // claim something the palette does not know yet.
    if (!forceCommands && fileState.status == PaletteFileIndexStatus.loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Text(
          translateForWidget(ref, I18nKey.paletteEmpty),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, I18nKey title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Text(
        translateForWidget(ref, title),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _entryTile({
    required PaletteEntry entry,
    required bool selected,
    required Key key,
  }) {
    final theme = Theme.of(context);
    final muted = entry.enabled ? null : theme.disabledColor;
    return Material(
      key: key,
      color: selected
          ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.55)
          : Colors.transparent,
      child: InkWell(
        onTap: entry.canExecute ? () => _executeEntry(entry) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                entry.icon ?? _categoryIcon(entry.category),
                size: 18,
                color: muted ?? theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                    ),
                    if (entry.subtitle != null && entry.subtitle!.isNotEmpty)
                      Text(
                        entry.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: muted ?? theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (_executingId == entry.id)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (!entry.enabled)
                Text(
                  translateForWidget(ref, I18nKey.paletteDisabled),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.disabledColor,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _fileStatusWidget(
    BuildContext context,
    PaletteFileIndexState fileState,
  ) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10);
    switch (fileState.status) {
      case PaletteFileIndexStatus.loading:
        return Padding(
          padding: padding,
          child: Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  translateForWidget(ref, I18nKey.paletteFileIndexLoading),
                  style: style,
                ),
              ),
            ],
          ),
        );
      case PaletteFileIndexStatus.empty:
        return Padding(
          padding: padding,
          child: Text(
            translateForWidget(ref, I18nKey.paletteFileIndexEmpty),
            style: style,
          ),
        );
      case PaletteFileIndexStatus.noProject:
        return Padding(
          padding: padding,
          child: Text(
            translateForWidget(ref, I18nKey.paletteFileIndexNoProject),
            style: style,
          ),
        );
      case PaletteFileIndexStatus.error:
        return Padding(
          padding: padding,
          child: Row(
            children: [
              Icon(
                Icons.error_outline,
                size: 16,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  translateInContextWithReplacements(
                    context,
                    I18nKey.paletteFileIndexError,
                    {'error': '${fileState.error}'},
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: style?.copyWith(color: theme.colorScheme.error),
                ),
              ),
              if (fileState.onRetry != null)
                TextButton(
                  onPressed: fileState.onRetry,
                  child: Text(
                    translateForWidget(ref, I18nKey.paletteFileIndexRetry),
                  ),
                ),
            ],
          ),
        );
      case PaletteFileIndexStatus.ready:
        return null;
    }
  }

  Widget _truncationHint(
    BuildContext context,
    PaletteFileIndexState fileState,
  ) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Text(
        translateForWidgetWithReplacements(
          ref,
          I18nKey.paletteFileIndexTruncated,
          {'limit': '${fileState.limit}'},
        ),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  void _moveSelection(int delta) {
    final count = _selectableEntries.length;
    if (count == 0) return;
    setState(() {
      _selectedIndex = (_paintedSelectedIndex + delta).clamp(0, count - 1);
      _revealSelection = true;
    });
  }

  void _scheduleRevealSelection() {
    if (!_revealSelection) return;
    _revealSelection = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final index = _paintedSelectedIndex;
      if (index < 0 || index >= _selectableKeys.length) return;
      final selectedContext = _selectableKeys[index].currentContext;
      if (selectedContext == null) return;
      Scrollable.ensureVisible(
        selectedContext,
        alignment: 0.5,
        duration: const Duration(milliseconds: 80),
      );
    });
  }

  void _executeSelected() {
    final index = _paintedSelectedIndex;
    if (index < 0 || index >= _selectableEntries.length) return;
    _executeEntry(_selectableEntries[index]);
  }

  Future<void> _executeEntry(PaletteEntry entry) async {
    if (!entry.canExecute || _executingId != null) return;
    final callback = entry.onSelect;
    if (callback == null) return;
    ref.read(recentPaletteIdsProvider.notifier).record(entry.id);
    setState(() => _executingId = entry.id);
    try {
      await callback(context, ref);
    } on CommandException catch (error) {
      _showExecuteError(error.message);
    } catch (error) {
      _showExecuteError('$error');
    } finally {
      if (mounted) {
        setState(() => _executingId = null);
        Navigator.of(context).maybePop();
      }
    }
  }

  void _showExecuteError(String message) {
    if (!mounted) return;
    showIdeError(
      context,
      translateInContextWithReplacements(
        context,
        I18nKey.paletteExecuteFailed,
        {'error': message},
      ),
    );
  }

  void _close() {
    if (ModalRoute.of(context)?.isActive ?? false) {
      Navigator.of(context).pop();
    }
  }
}

class _PaletteSectionData {
  const _PaletteSectionData({
    required this.title,
    required this.keyPrefix,
    this.entries = const <PaletteEntry>[],
    this.leading = const <Widget>[],
    this.trailing = const <Widget>[],
  });

  final I18nKey title;
  final String keyPrefix;
  final List<PaletteEntry> entries;
  final List<Widget> leading;
  final List<Widget> trailing;
}

IconData _categoryIcon(PaletteCategory category) {
  return switch (category) {
    PaletteCategory.command => Icons.chevron_right,
    PaletteCategory.file => Icons.insert_drive_file_outlined,
    PaletteCategory.navigation => Icons.arrow_forward,
    PaletteCategory.setting => Icons.settings_outlined,
  };
}
