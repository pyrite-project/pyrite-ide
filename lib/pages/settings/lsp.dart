import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/models/settings.dart';
import 'package:pyrite_ide/core/services/data_registry.dart';
import 'package:pyrite_ide/core/services/editor/lsp_stubs_refresh.dart';
import 'package:pyrite_ide/core/services/message/ide_message.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/shared/dialog_form_fields.dart';
import 'package:pyrite_ide/shared/md3_widgets.dart';
import 'package:pyrite_ide/shared/studio_text.dart';

class LspSettings extends ConsumerWidget {
  const LspSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final body = ListView(
      padding: EdgeInsets.all(12),
      children: [
        SettingsSection(
          title: I18nKey.settingsLspServiceSection,
          description: I18nKey.settingsLspServiceDescription,
          children: [
            SwitchListTile(
              title: const UseText(I18nKey.settingsLspEnable),
              value: ref.watch(useLsp),
              onChanged: (value) {
                ref.read(useLsp.notifier).state = value;
              },
            ),

            ListTile(title: const UseText(I18nKey.settingsLspConnectionType)),
            RadioGroup<LspType>(
              groupValue: ref.watch(lspType),
              onChanged: (value) {
                if (value != null) ref.read(lspType.notifier).state = value;
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    RadioListTile<LspType>(
                      title: const Text("WebSocket"),
                      subtitle: const UseText(
                        I18nKey.settingsLspWebSocketSubtitle,
                      ),
                      value: LspType.webSocket,
                      contentPadding: EdgeInsets.zero,
                    ),
                    RadioListTile<LspType>(
                      title: const Text("stdio"),
                      subtitle: const UseText(I18nKey.settingsLspStdioSubtitle),
                      value: LspType.stdio,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ),
            if (ref.watch(lspType) == LspType.webSocket) ...[
              ListTile(
                title: const UseText(I18nKey.settingsLspWebSocketAddress),
                subtitle: Text("ws://${ref.watch(lspWebSocketPath)}"),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showPathDialog(context, ref),
              ),
            ] else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  children: [
                    TextFormField(
                      initialValue: ref.read(lspStdioExecutable),
                      decoration: const InputDecoration(
                        label: UseText(I18nKey.settingsLspExecutablePath),
                        helper: UseText(I18nKey.settingsLspExecutablePathHint),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        ref.read(lspStdioExecutable.notifier).state = value;
                      },
                      onFieldSubmitted: (value) {
                        ref.read(lspStdioExecutable.notifier).state = value
                            .trim();
                        showIdeSuccess(
                          context,
                          translateForWidget(
                            ref,
                            I18nKey.settingsLspExecutableUpdated,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: ref.read(lspStdioArgs),
                      decoration: const InputDecoration(
                        label: UseText(I18nKey.settingsLspArgs),
                        helper: UseText(I18nKey.settingsLspArgsHint),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        ref.read(lspStdioArgs.notifier).state = value;
                      },
                      onFieldSubmitted: (value) {
                        ref.read(lspStdioArgs.notifier).state = value.trim();
                        showIdeSuccess(
                          context,
                          translateForWidget(
                            ref,
                            I18nKey.settingsLspArgsUpdated,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const UseText(I18nKey.settingsLspVirtualEnvironment),
              subtitle: Text(
                ref.watch(lspVirtualEnvironment).isEmpty
                    ? translateForWidget(
                        ref,
                        I18nKey.settingsLspVirtualEnvironmentSubtitle,
                      )
                    : ref.watch(lspVirtualEnvironment),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showVirtualEnvironmentDialog(context, ref),
            ),
          ],
        ),
        SettingsSection(
          title: I18nKey.settingsLspBasedPyrightSection,
          children: [
            ListTile(
              leading: const Icon(Icons.rule_outlined),
              title: const UseText(
                I18nKey.settingsLspBasedPyrightTypeCheckingMode,
              ),
              subtitle: UseText(
                _basedPyrightTypeCheckingModeLabel(
                  ref.watch(lspBasedPyrightTypeCheckingMode),
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  _showBasedPyrightTypeCheckingModeDialog(context, ref),
            ),
          ],
        ),
        SettingsSection(
          title: I18nKey.settingsLspDiagnosticsSection,
          children: [
            SwitchListTile(
              title: const UseText(I18nKey.settingsLspWarningDiagnostics),
              subtitle: const UseText(
                I18nKey.settingsLspWarningDiagnosticsSubtitle,
              ),
              value: !ref.watch(disableWarning),
              onChanged: (value) {
                ref.read(disableWarning.notifier).state = !value;
              },
            ),

            SwitchListTile(
              title: const UseText(I18nKey.settingsLspErrorDiagnostics),
              subtitle: const UseText(
                I18nKey.settingsLspErrorDiagnosticsSubtitle,
              ),
              value: !ref.watch(disableError),
              onChanged: (value) {
                ref.read(disableError.notifier).state = !value;
              },
            ),
          ],
        ),
        SettingsSection(
          title: "MicroPython Stubs",
          children: [
            SwitchListTile(
              title: const UseText(I18nKey.settingsLspEnableStubs),
              value: ref.watch(microPythonStubsEnabled),
              onChanged: (value) {
                ref.read(microPythonStubsEnabled.notifier).state = value;
                _showStubsRestartDialogIfNeeded(context, ref);
              },
            ),

            SwitchListTile(
              title: const UseText(I18nKey.settingsLspAutoDetectLayer),
              subtitle: const UseText(
                I18nKey.settingsLspAutoDetectLayerSubtitle,
              ),
              value: ref.watch(microPythonStubsAutoDetectLayers),
              onChanged: (value) {
                ref.read(microPythonStubsAutoDetectLayers.notifier).state =
                    value;
              },
            ),

            ListTile(
              leading: const Icon(Icons.layers_outlined),
              title: const Text("Stubs Layers"),
              subtitle: Text(
                _layersSummary(ref.watch(microPythonStubsLayers), ref),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showLayersDialog(context, ref),
            ),

            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const UseText(I18nKey.settingsLspExtraPaths),
              subtitle: Text(
                _pathsSummary(ref.watch(microPythonStubsExtraPaths), ref),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showExtraPathsDialog(context, ref),
            ),
          ],
        ),
        SettingsSection(
          title: I18nKey.settingsLspFeaturesSection,
          description: I18nKey.settingsLspFeaturesDescription,
          children: [
            _CapabilitySwitch(
              title: I18nKey.settingsLspSemanticHighlighting,
              description: I18nKey.settingsLspSemanticHighlightingDescription,
              provider: lspSemanticHighlighting,
            ),

            _CapabilitySwitch(
              title: I18nKey.settingsLspCodeCompletion,
              provider: lspCodeCompletion,
            ),

            _CapabilitySwitch(
              title: I18nKey.settingsLspHoverInfo,
              provider: lspHoverInfo,
            ),

            _CapabilitySwitch(
              title: I18nKey.settingsLspCodeAction,
              description: I18nKey.settingsLspCodeActionDescription,
              provider: lspCodeAction,
            ),

            _CapabilitySwitch(
              title: I18nKey.settingsLspSignatureHelp,
              description: I18nKey.settingsLspSignatureHelpDescription,
              provider: lspSignatureHelp,
            ),

            _CapabilitySwitch(
              title: I18nKey.settingsLspDocumentColor,
              description: I18nKey.settingsLspDocumentColorDescription,
              provider: lspDocumentColor,
            ),

            _CapabilitySwitch(
              title: I18nKey.settingsLspDocumentHighlight,
              description: I18nKey.settingsLspDocumentHighlightDescription,
              provider: lspDocumentHighlight,
            ),

            _CapabilitySwitch(
              title: I18nKey.settingsLspCodeFolding,
              description: I18nKey.settingsLspCodeFoldingDescription,
              provider: lspCodeFolding,
            ),

            _CapabilitySwitch(
              title: I18nKey.settingsLspShowInlayHints,
              description: I18nKey.settingsLspShowInlayHintsDescription,
              provider: lspShowInlayHints,
            ),

            _CapabilitySwitch(
              title: I18nKey.settingsLspGoToDefinition,
              provider: lspGoToDefinition,
            ),

            _CapabilitySwitch(
              title: I18nKey.settingsLspRename,
              provider: lspRename,
            ),
          ],
        ),
        SettingsSection(
          title: I18nKey.settingsLspScope,
          children: [
            _CapabilitySwitch(
              title: I18nKey.settingsLspAlwaysStart,
              description: I18nKey.settingsLspAlwaysStartDescription,
              provider: lspAlwaysStart,
            ),
          ],
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const UseText(I18nKey.settingsLspPageTitle)),
      body: body,
    );
  }

  String _layersSummary(List<MicroPythonStubsLayer> layers, WidgetRef ref) {
    if (layers.isEmpty) {
      return translateForWidget(ref, I18nKey.settingsLspNotConfigured);
    }
    return layers
        .map((layer) => '${layer.provider}/${layer.profile}')
        .join(', ');
  }

  String _pathsSummary(List<String> paths, WidgetRef ref) {
    if (paths.isEmpty) {
      return translateForWidget(ref, I18nKey.settingsLspNotConfigured);
    }
    return paths.length == 1
        ? paths.first
        : translateForWidgetWithReplacements(
            ref,
            I18nKey.settingsLspPathCount,
            {'count': paths.length.toString()},
          );
  }

  void _showLayersDialog(BuildContext context, WidgetRef ref) async {
    final layers = List<MicroPythonStubsLayer>.from(
      ref.read(microPythonStubsLayers),
    );
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final providers = ref.read(dataRegistryProvider).allStubsProviders;
          return AlertDialog(
            title: const Text("Stubs Layers"),
            content: SizedBox(
              width: 560,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (layers.isEmpty)
                    const ListTile(
                      leading: Icon(Icons.layers_clear_outlined),
                      title: UseText(I18nKey.settingsLspNoLayerConfigured),
                      subtitle: UseText(
                        I18nKey.settingsLspNoLayerConfiguredSubtitle,
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 360),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: layers.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) => _StubsLayerTile(
                          layer: layers[index],
                          profile: _findProfile(ref, layers[index]),
                          canMoveUp: index > 0,
                          canMoveDown: index < layers.length - 1,
                          onMoveUp: () => setDialogState(() {
                            final item = layers.removeAt(index);
                            layers.insert(index - 1, item);
                          }),
                          onMoveDown: () => setDialogState(() {
                            final item = layers.removeAt(index);
                            layers.insert(index + 1, item);
                          }),
                          onDelete: () => setDialogState(() {
                            layers.removeAt(index);
                          }),
                          translate: (key, [replacements = const {}]) =>
                              translateInContextWithReplacements(
                                context,
                                key,
                                replacements,
                              ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: providers.isEmpty
                          ? null
                          : () async {
                              final layer = await _showAddLayerDialog(
                                context,
                                ref,
                                layers,
                              );
                              if (layer == null) return;
                              setDialogState(() => layers.add(layer));
                            },
                      icon: const Icon(Icons.add),
                      label: const UseText(I18nKey.settingsLspAddLayer),
                    ),
                  ),
                  if (providers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: UseText(I18nKey.settingsLspNoStubsProvider),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => context.pop(),
                child: const UseText(I18nKey.commonCancel),
              ),
              FilledButton(
                onPressed: () {
                  ref.read(microPythonStubsLayers.notifier).state =
                      List.unmodifiable(layers);
                  refreshOpenLspStubsConfiguration(ref.read);
                  context.pop();
                  showIdeSuccess(
                    context,
                    translateForWidget(ref, I18nKey.settingsLspLayersUpdated),
                  );
                  _showStubsRestartDialogIfNeeded(context, ref);
                },
                child: const UseText(I18nKey.commonSave),
              ),
            ],
          );
        },
      ),
    );
  }

  StubsProfileEntry? _findProfile(WidgetRef ref, MicroPythonStubsLayer layer) {
    return ref
        .read(dataRegistryProvider)
        .getStubsProfile(layer.provider, layer.profile);
  }

  Future<MicroPythonStubsLayer?> _showAddLayerDialog(
    BuildContext context,
    WidgetRef ref,
    List<MicroPythonStubsLayer> selected,
  ) async {
    final providers = ref.read(dataRegistryProvider).allStubsProviders;
    return showDialog<MicroPythonStubsLayer>(
      context: context,
      builder: (context) => AlertDialog(
        title: const UseText(I18nKey.settingsLspAddStubsLayer),
        content: SizedBox(
          width: 560,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: providers.length,
              itemBuilder: (context, providerIndex) {
                final provider = providers[providerIndex];
                return ExpansionTile(
                  initiallyExpanded: providerIndex == 0,
                  title: Text(provider.providerId),
                  subtitle: Text(
                    [
                      if (provider.version.isNotEmpty) provider.version,
                      '${provider.profiles.length} profiles',
                    ].join(' · '),
                  ),
                  children: [
                    for (final profile in provider.profiles)
                      Builder(
                        builder: (context) {
                          final alreadySelected = selected.any(
                            (layer) =>
                                layer.provider == provider.providerId &&
                                layer.profile == profile.id,
                          );
                          return ListTile(
                            enabled: !alreadySelected,
                            title: Text(profile.label ?? profile.id),
                            subtitle: Text(
                              '${provider.providerId}/${profile.id}\n${profile.path}',
                            ),
                            isThreeLine: true,
                            trailing: alreadySelected
                                ? const UseText(I18nKey.settingsLspAlreadyAdded)
                                : const Icon(Icons.add),
                            onTap: alreadySelected
                                ? null
                                : () => context.pop(
                                    MicroPythonStubsLayer(
                                      provider: provider.providerId,
                                      profile: profile.id,
                                    ),
                                  ),
                          );
                        },
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: const UseText(I18nKey.commonCancel),
          ),
        ],
      ),
    );
  }

  /// Stubs reach servers like Zuban only through the spawned process's
  /// environment, so settings saved while one is running cannot reach it.
  void _showStubsRestartDialogIfNeeded(BuildContext context, WidgetRef ref) {
    if (!anyOpenLspNeedsRestartForStubs(ref.read)) return;
    unawaited(
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const UseText(I18nKey.settingsLspStubsRestartTitle),
          content: const UseText(I18nKey.settingsLspStubsRestartContent),
          actions: [
            TextButton(
              onPressed: () => dialogContext.pop(),
              child: const UseText(I18nKey.commonConfirm),
            ),
          ],
        ),
      ),
    );
  }

  void _showExtraPathsDialog(BuildContext context, WidgetRef ref) async {
    final initial = ref.read(microPythonStubsExtraPaths).join('\n');
    await showDialog(
      context: context,
      builder: (context) => DialogFormFields(
        initialValues: [initial],
        builder: (context, c) => AlertDialog(
          title: const UseText(I18nKey.settingsLspExtraPathsDialog),
          content: SizedBox(
            width: 460,
            child: TextField(
              controller: c[0],
              minLines: 6,
              maxLines: 12,
              decoration: const InputDecoration(
                helper: UseText(I18nKey.settingsLspExtraPathsHelper),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => context.pop(),
              child: const UseText(I18nKey.commonCancel),
            ),
            FilledButton(
              onPressed: () {
                ref.read(microPythonStubsExtraPaths.notifier).state = c[0].text
                    .split('\n')
                    .map((line) => line.trim())
                    .where((line) => line.isNotEmpty)
                    .toList();
                context.pop();
                _showStubsRestartDialogIfNeeded(context, ref);
              },
              child: const UseText(I18nKey.commonSave),
            ),
          ],
        ),
      ),
    );
  }

  void showPathDialog(BuildContext context, WidgetRef ref) async {
    final initial = ref.read(lspWebSocketPath);
    await showDialog(
      context: context,
      builder: (context) => DialogFormFields(
        initialValues: [initial],
        builder: (context, c) => AlertDialog(
          title: const UseText(I18nKey.settingsLspWebSocketAddress),
          content: TextField(
            controller: c[0],
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              label: UseText(I18nKey.settingsLspAddress),
              helper: UseText(I18nKey.settingsLspAddressHint),
              prefixText: "ws://",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => context.pop(),
              child: const UseText(I18nKey.commonCancel),
            ),
            FilledButton(
              onPressed: () {
                final value = c[0].text.trim().replaceFirst(
                  RegExp(r'^ws://'),
                  '',
                );
                if (value.isEmpty) return;
                final Uri? uri;
                try {
                  uri = Uri.tryParse("ws://$value");
                  if (uri == null ||
                      uri.host.isEmpty ||
                      !uri.hasPort ||
                      uri.port <= 0 ||
                      uri.port > 65535) {
                    throw const FormatException("Invalid WebSocket address");
                  }
                } on FormatException {
                  showIdeError(
                    context,
                    translateForWidget(ref, I18nKey.settingsLspInvalidAddress),
                  );
                  return;
                }
                ref.read(lspWebSocketPath.notifier).state = value;
                context.pop();
                showIdeSuccess(
                  context,
                  translateForWidget(ref, I18nKey.settingsLspAddressUpdated),
                );
              },
              child: const UseText(I18nKey.commonSave),
            ),
          ],
        ),
      ),
    );
  }

  void showVirtualEnvironmentDialog(BuildContext context, WidgetRef ref) async {
    final initial = ref.read(lspVirtualEnvironment);
    await showDialog(
      context: context,
      builder: (context) => DialogFormFields(
        initialValues: [initial],
        builder: (context, c) => AlertDialog(
          title: const UseText(I18nKey.settingsLspVirtualEnvironment),
          content: TextField(
            controller: c[0],
            decoration: InputDecoration(
              label: const UseText(I18nKey.settingsLspVirtualEnvironment),
              helper: const UseText(I18nKey.settingsLspVirtualEnvironmentHint),
              suffixIcon: IconButton(
                tooltip: translateInContext(context, I18nKey.lspPickVirtualEnv),
                icon: const Icon(Icons.folder_open_outlined),
                onPressed: () async {
                  final directoryPath = await getDirectoryPath();
                  if (directoryPath != null) c[0].text = directoryPath;
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => context.pop(),
              child: const UseText(I18nKey.commonCancel),
            ),
            TextButton(
              onPressed: () {
                ref.read(lspVirtualEnvironment.notifier).state = '';
                refreshOpenLspConfiguration(ref.read);
                context.pop();
              },
              child: const UseText(I18nKey.lspClearEnvironment),
            ),
            FilledButton(
              onPressed: () {
                ref.read(lspVirtualEnvironment.notifier).state = c[0].text
                    .trim();
                refreshOpenLspConfiguration(ref.read);
                context.pop();
                showIdeSuccess(
                  context,
                  translateForWidget(
                    ref,
                    I18nKey.settingsLspVirtualEnvironmentUpdated,
                  ),
                );
              },
              child: const UseText(I18nKey.commonSave),
            ),
          ],
        ),
      ),
    );
  }

  void _showBasedPyrightTypeCheckingModeDialog(
    BuildContext context,
    WidgetRef ref,
  ) {
    final current = ref.read(lspBasedPyrightTypeCheckingMode);
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const UseText(I18nKey.settingsLspBasedPyrightTypeCheckingMode),
        children: BasedPyrightTypeCheckingMode.values.map((mode) {
          return SimpleDialogOption(
            child: ListTile(
              title: UseText(_basedPyrightTypeCheckingModeLabel(mode)),
              trailing: mode == current ? const Icon(Icons.check) : null,
              minTileHeight: 0,
              onTap: () {
                ref.read(lspBasedPyrightTypeCheckingMode.notifier).state = mode;
                refreshOpenLspConfiguration(ref.read);
                Navigator.pop(context);
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  I18nKey _basedPyrightTypeCheckingModeLabel(
    BasedPyrightTypeCheckingMode mode,
  ) => switch (mode) {
    BasedPyrightTypeCheckingMode.off =>
      I18nKey.settingsLspBasedPyrightTypeCheckingModeOff,
    BasedPyrightTypeCheckingMode.basic =>
      I18nKey.settingsLspBasedPyrightTypeCheckingModeBasic,
    BasedPyrightTypeCheckingMode.standard =>
      I18nKey.settingsLspBasedPyrightTypeCheckingModeStandard,
    BasedPyrightTypeCheckingMode.strict =>
      I18nKey.settingsLspBasedPyrightTypeCheckingModeStrict,
    BasedPyrightTypeCheckingMode.all =>
      I18nKey.settingsLspBasedPyrightTypeCheckingModeAll,
  };
}

/// A labelled on/off switch backed by one settings provider.
///
/// [description] spells out what the switch actually changes in the editor, so
/// the settings page does not leave the reader guessing which layer a given
/// protocol capability ends up affecting.
class _CapabilitySwitch extends ConsumerWidget {
  const _CapabilitySwitch({
    required this.title,
    this.description,
    required this.provider,
  });

  final Object title;
  final Object? description;
  final StateProvider<bool> provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SwitchListTile(
      title: UseText(title),
      subtitle: description == null ? null : UseText(description!),
      value: ref.watch(provider),
      onChanged: (value) => ref.read(provider.notifier).state = value,
    );
  }
}

class _StubsLayerTile extends StatelessWidget {
  const _StubsLayerTile({
    required this.layer,
    required this.profile,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
    required this.translate,
  });

  final MicroPythonStubsLayer layer;
  final StubsProfileEntry? profile;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onDelete;
  final I18nTranslate translate;

  @override
  Widget build(BuildContext context) {
    final title = profile?.label ?? '${layer.provider}/${layer.profile}';
    final subtitle = profile == null
        ? translate(I18nKey.settingsLspMissingProfile, {
            'profile': '${layer.provider}/${layer.profile}',
          })
        : '${layer.provider}/${layer.profile}\n${profile!.path}';
    return ListTile(
      leading: Icon(
        profile == null ? Icons.warning_amber_outlined : Icons.layers_outlined,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      isThreeLine: profile != null,
      trailing: Wrap(
        spacing: 4,
        children: [
          IconButton(
            tooltip: translate(I18nKey.commonMoveUp),
            onPressed: canMoveUp ? onMoveUp : null,
            icon: const Icon(Icons.keyboard_arrow_up),
          ),
          IconButton(
            tooltip: translate(I18nKey.commonMoveDown),
            onPressed: canMoveDown ? onMoveDown : null,
            icon: const Icon(Icons.keyboard_arrow_down),
          ),
          IconButton(
            tooltip: translate(I18nKey.gitDelete),
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}
