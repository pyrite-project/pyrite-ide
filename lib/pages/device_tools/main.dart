import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/models/serial_port_filter.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/serial/serial_port_filter_provider.dart';
import 'package:pyrite_ide/core/services/serial/serial_provider.dart';
import 'package:pyrite_ide/core/services/serial/web_repl_provider.dart';
import 'package:pyrite_ide/pages/device_tools/device_status_panel.dart';
import 'package:pyrite_ide/pages/device_tools/serial_port_list.dart';
import 'package:pyrite_ide/shared/md3_widgets.dart';
import 'package:pyrite_ide/shared/search_field.dart';
import 'package:pyrite_ide/shared/studio_text.dart';

class Tools extends ConsumerStatefulWidget {
  const Tools({super.key, this.compact = false});

  final bool compact;

  @override
  ConsumerState<Tools> createState() => _ToolsState();
}

class _ToolsState extends ConsumerState<Tools> {
  bool _showDeviceStatus = false;

  late final TextEditingController _searchController = TextEditingController(
    text: ref.read(serialPortFilterProvider).query,
  );

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _updateFilter(SerialPortFilter Function(SerialPortFilter) update) {
    final notifier = ref.read(serialPortFilterProvider.notifier);
    notifier.state = update(notifier.state);
  }

  void _clearFilter() {
    _searchController.clear();
    ref.read(serialPortFilterProvider.notifier).state =
        const SerialPortFilter();
  }

  @override
  Widget build(BuildContext context) {
    final body = buildBoardManager(context);
    if (widget.compact) return body;
    return Scaffold(
      appBar: AppBar(title: const UseText(I18nKey.devicesTitle)),
      body: body,
    );
  }

  Widget buildBoardManager(BuildContext context) {
    final state = ref.watch(serialProvider);
    final webReplState = ref.watch(webReplProvider).state;
    final webReplActive =
        webReplState == WebReplState.waitingPassword ||
        webReplState == WebReplState.connected;
    final compact =
        widget.compact || ref.watch(themeStyle) == ThemeStyle.compact;
    final filter = ref.watch(serialPortFilterProvider);
    final result = filter.apply(state.ports);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: buildConnectionSummary(
            context,
            state.isConnected,
            state.selectedPortName,
            compact: compact,
            onDisconnect: state.isConnected
                ? () => ref.read(serialProvider.notifier).disconnectPort()
                : null,
            onDeviceStatus: state.isConnected
                ? () => setState(() => _showDeviceStatus = !_showDeviceStatus)
                : null,
            showDeviceStatus: _showDeviceStatus,
          ),
        ),
        if (_showDeviceStatus && state.isConnected)
          SliverToBoxAdapter(
            child: SizedBox(height: 270, child: const DeviceStatusPanel()),
          ),
        SliverToBoxAdapter(
          child: PaneHeader(
            title: I18nKey.devicesAvailableSerialTitle,
            subtitle: I18nKey.devicesAvailableSerialSubtitle,
            leadingIcon: Icons.usb,
            compact: compact,
            actions: [
              IconButton(
                tooltip: translateForWidget(ref, I18nKey.devicesRefreshSerial),
                onPressed: () => ref.read(serialProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh),
              ),
              buildFilterMenu(filter),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 8),
            child: OptionsSearchField(
              controller: _searchController,
              options: filter.options,
              hintText: translateForWidget(
                ref,
                I18nKey.devicesSerialFilterHint,
              ),
              hasError: result.regexError != null,
              onChanged: (query) =>
                  _updateFilter((filter) => filter.copyWith(query: query)),
              onOptionsChanged: (options) =>
                  _updateFilter((filter) => filter.copyWith(options: options)),
            ),
          ),
        ),
        if (result.total == 0)
          SliverFillRemaining(
            hasScrollBody: false,
            child: WorkspaceEmptyState(
              icon: Icons.usb_outlined,
              title: I18nKey.devicesEmptySerialTitle,
              message: I18nKey.devicesEmptySerialMessage,
              actionLabel: I18nKey.devicesRefreshSerial,
              onAction: () => ref.read(serialProvider.notifier).refresh(),
            ),
          )
        else if (result.regexError case final regexError?)
          SliverFillRemaining(
            hasScrollBody: false,
            child: WorkspaceEmptyState(
              icon: Icons.error_outline,
              title: I18nKey.devicesSerialFilterInvalidRegex,
              message: regexError,
              actionLabel: I18nKey.devicesSerialFilterClear,
              onAction: _clearFilter,
            ),
          )
        else if (result.visible.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: WorkspaceEmptyState(
              icon: Icons.filter_alt_off_outlined,
              title: I18nKey.devicesSerialFilterNoMatchTitle,
              message: I18nKey.devicesSerialFilterNoMatchMessage,
              actionLabel: I18nKey.devicesSerialFilterClear,
              onAction: _clearFilter,
            ),
          )
        else ...[
          if (filter.isActive)
            SliverToBoxAdapter(
              child: buildFilterSummary(
                context,
                shown: result.visible.length,
                total: result.total,
              ),
            ),
          SerialPortList(
            ports: result.visible,
            compact: compact,
            onConnect: webReplActive
                ? null
                : (path) => ref.read(serialProvider.notifier).connectPort(path),
          ),
        ],
      ],
    );
  }

  Widget buildConnectionSummary(
    BuildContext context,
    bool isConnected,
    String? selectedPortName, {
    VoidCallback? onDisconnect,
    VoidCallback? onDeviceStatus,
    bool showDeviceStatus = false,
    bool compact = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isConnected
            ? scheme.primaryContainer
            : scheme.surfaceContainerLow,
        borderRadius: context.effectiveRadius,
        border: Border.all(
          color: isConnected ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isConnected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: isConnected
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    UseText(
                      isConnected
                          ? I18nKey.devicesConnected
                          : I18nKey.devicesDisconnected,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    UseText(
                      isConnected
                          ? selectedPortName ?? I18nKey.devicesSerialConnected
                          : I18nKey.devicesConnectionHint,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isConnected
                            ? scheme.onPrimaryContainer
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (onDeviceStatus != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 4),
                  child: Tooltip(
                    message: translateForWidget(
                      ref,
                      showDeviceStatus
                          ? I18nKey.devicesHideStatus
                          : I18nKey.devicesShowStatus,
                    ),
                    child: IconButton(
                      onPressed: onDeviceStatus,
                      icon: Icon(
                        showDeviceStatus
                            ? Icons.keyboard_arrow_up
                            : Icons.memory,
                        size: 20,
                      ),
                      style: IconButton.styleFrom(
                        foregroundColor: isConnected
                            ? scheme.onPrimaryContainer
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              if (onDisconnect != null)
                TextButton.icon(
                  onPressed: onDisconnect,
                  icon: const Icon(Icons.link_off, size: 18),
                  label: const UseText(I18nKey.devicesDisconnect),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildFilterMenu(SerialPortFilter filter) {
    return MenuAnchor(
      menuChildren: [
        CheckboxMenuButton(
          value: filter.usbOnly,
          onChanged: (value) => _updateFilter(
            (filter) => filter.copyWith(usbOnly: value ?? false),
          ),
          child: const UseText(I18nKey.devicesSerialFilterUsbOnly),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.filter_alt_off_outlined, size: 18),
          onPressed: filter.isActive ? _clearFilter : null,
          child: const UseText(I18nKey.devicesSerialFilterClear),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        tooltip: translateForWidget(ref, I18nKey.devicesSerialFilterMenu),
        isSelected: filter.usbOnly,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.filter_list),
        selectedIcon: const Icon(Icons.filter_alt),
      ),
    );
  }

  Widget buildFilterSummary(
    BuildContext context, {
    required int shown,
    required int total,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              translateForWidget(
                ref,
                I18nKey.devicesSerialFilterCount,
              ).replaceAll('{shown}', '$shown').replaceAll('{total}', '$total'),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          TextButton(
            onPressed: _clearFilter,
            child: const UseText(I18nKey.devicesSerialFilterClear),
          ),
        ],
      ),
    );
  }
}
