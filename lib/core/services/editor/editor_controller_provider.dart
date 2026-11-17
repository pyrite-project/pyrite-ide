import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:code_forge/code_forge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/models/settings.dart';
import 'package:pyrite_ide/core/services/editor/code_forge_controller.dart';
import 'package:pyrite_ide/core/services/editor/editor_split.dart';
import 'package:pyrite_ide/core/services/editor/lsp_stdio_args.dart';
import 'package:pyrite_ide/core/services/editor/lsp_stubs_config.dart';
import 'package:pyrite_ide/core/services/editor/lsp_workspace_path.dart';
import 'package:pyrite_ide/core/services/editor/workspace_lsp_config_pool.dart';
import 'package:pyrite_ide/core/services/file/canonical_path.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/core/services/message/ide_message.dart';
import 'package:pyrite_ide/core/services/output/ide_output_log.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/core/utils/display_path.dart';

/// The language id sent to the language server for every document.
///
/// The language id is no longer a setting: this IDE ships one Python language
/// server integration, and the document language shown to the user comes from
/// the per-file grammar in `editor_language.dart` instead. Anything that wants
/// a second language server needs a per-language server mapping, not a single
/// global id.
const String defaultLspLanguageId = 'python';

/// Files larger than this open read-only.
///
/// Multi-megabyte text files are logs or data dumps rather than code; editing
/// a document that size makes every keystroke and caret move traverse the
/// whole buffer. The full content is still loaded — a truncated preview could
/// be written back over the real file on save — but the editor is marked
/// read-only so it is never offered as editable.
const int maxEditableFileLength = 5 * 1024 * 1024;

class EditorControllerMapNotifier
    extends StateNotifier<Map<String, CodeForgeController>> {
  final Ref ref;
  EditorControllerMapNotifier(this.ref) : super({}) {
    for (final provider in lspCapabilityProviders) {
      ref.listen<bool>(provider, (_, _) => _applyLspCapabilities());
    }
    ref.listen<bool>(lspDocumentColor, (_, enabled) {
      _updateDocumentColorPicker(enabled);
    });
    ref.listen<bool>(lspShowInlayHints, (_, visible) {
      _updateInlayHintsVisibility(visible);
    });
    // A launch change must reach the tabs that are already open, not just the
    // next file opened: the settings page hands the language server slot to a
    // plugin and the plugin writes transport/executable/arguments a moment
    // later, so every one of these listens for the same migration.
    ref.listen<String?>(lspPluginServerId, (_, _) => _scheduleLspMigration());
    ref.listen<LspType>(lspType, (_, _) => _scheduleLspMigration());
    ref.listen<String>(lspStdioExecutable, (_, _) => _scheduleLspMigration());
    ref.listen<String>(lspStdioArgs, (_, _) => _scheduleLspMigration());
    ref.listen<String>(lspWebSocketPath, (_, _) => _scheduleLspMigration());
    ref.listen<bool>(useLsp, (_, _) => _scheduleLspMigration());
  }

  Timer? _lspMigrationTimer;
  bool _lspMigrating = false;
  bool _lspMigrationPending = false;

  /// Debounces a launch-settings change into one migration of all open tabs.
  ///
  /// The plugin writes several settings in a row (transport, executable,
  /// arguments), each of which evicts the pooled config; debouncing merges
  /// that burst so the server is restarted once, with the final settings.
  void _scheduleLspMigration() {
    _lspMigrationTimer?.cancel();
    _lspMigrationTimer = Timer(
      const Duration(milliseconds: 600),
      () => unawaited(_migrateEditorsToCurrentLsp()),
    );
  }

  /// Re-points every open editor at the language server the current launch
  /// settings describe.
  ///
  /// A pooled config freezes its transport and executable at spawn time, so a
  /// settings change cannot be adopted by the running process: the pool is
  /// drained (which disposes the old servers) and each tab re-attaches to a
  /// config built from the new settings. When the new settings name no usable
  /// server, the tab is detached — fully editable, but offline — instead of
  /// being left holding a disposed config that fails every request.
  Future<void> _migrateEditorsToCurrentLsp() async {
    if (_lspMigrating) {
      _lspMigrationPending = true;
      return;
    }
    if (_lspRestartInFlight.isNotEmpty) {
      // A crash restart is mid-flight; retry once it settled.
      _scheduleLspMigration();
      return;
    }
    _lspMigrating = true;
    try {
      final controllers = Map<String, CodeForgeController>.from(state);
      _lspConfigPool.evictAll();
      if (controllers.isEmpty) return;
      for (final entry in controllers.entries) {
        final controller = entry.value;
        if (state[entry.key] != controller) continue; // closed meanwhile
        final enabled =
            ref.read(useLsp) &&
            (path.extension(entry.key) == '.py' || ref.read(lspAlwaysStart));
        if (!enabled) {
          controller.detachLsp();
          continue;
        }
        final workspacePath = lspWorkspacePathForFile(
          File(entry.key),
          ref.read(fileProvider),
        );
        final acquired = await _lspConfigPool.acquire(workspacePath);
        final newConfig = acquired.config;
        if (newConfig == null) {
          controller.detachLsp();
          continue;
        }
        if (acquired.created) {
          unawaited(_sendWorkspaceConfiguration(newConfig));
        }
        await controller.reattachLsp(newConfig);
      }
    } catch (error) {
      debugPrint('LSP migration failed: $error');
    } finally {
      _lspMigrating = false;
      if (_lspMigrationPending) {
        _lspMigrationPending = false;
        _scheduleLspMigration();
      }
    }
  }

  @override
  void dispose() {
    _lspMigrationTimer?.cancel();
    super.dispose();
  }

  /// Pushes the current capability settings into every running language server
  /// and re-runs the editor features that render what the server sends.
  ///
  /// A pooled config keeps the [LspClientCapabilities] it was built with, and
  /// every request gate reads that instance, so overwriting its flags is what
  /// makes a switch take effect without closing the workspace's tabs. Whatever
  /// the server already sent under the previous setting then needs clearing,
  /// which is what the per-controller refresh is for.
  void _applyLspCapabilities() {
    final capabilities = _readLspCapabilities(ref);
    for (final config in _lspConfigPool.activeConfigs) {
      config.capabilities.applyFrom(capabilities);
    }
    for (final controller in state.values) {
      unawaited(controller.refreshLspFeatures());
    }
  }

  /// Evicts every pooled workspace config so the next file open spawns a
  /// language server from the current launch settings.
  ///
  /// Live servers are disposed on purpose: the transport, executable,
  /// arguments and the plugin server in use describe the *launch*, which a
  /// running process cannot adopt — keeping the old one would keep answering
  /// with whatever server the settings used to point at.
  void evictLspConfigs() {
    _lspConfigPool.evictAll();
    // Draining the pool leaves every open tab holding a disposed config;
    // schedule the migration so they land on a server built from the new
    // settings instead of failing requests until they are reopened.
    _scheduleLspMigration();
  }

  /// One language server per workspace root, shared by every open file under
  /// it.
  ///
  /// Each editor used to start its own server, so a session with N tabs kept
  /// N identical processes alive and restored sessions serialized N server
  /// startups. The pool refcounts controllers; [removePath] releases a tab's
  /// seat, and only the last one under a workspace root stops the server.
  ///
  /// The stubs and venv settings sent to the server are captured when the
  /// workspace's first file opens and stay fixed until its last file closes —
  /// the same negotiation window a real IDE has with one server per project.
  /// The capability switches are the exception: [_applyLspCapabilities]
  /// rewrites them on every running server, because the request gates read the
  /// config's own capability instance.
  late final WorkspaceLspConfigPool<LspConfig> _lspConfigPool =
      WorkspaceLspConfigPool<LspConfig>(
        create: _createWorkspaceLspConfig,
        onEvict: (config) => config.dispose(),
        isAlive: (config) => config.isUsable,
      );

  Future<CodeForgeController?> createNewEditorController(
    File file, {
    String? initialText,
    bool openReadOnly = false,
  }) async {
    // The map is keyed by the exact path string and `openedFile` is matched
    // against it elsewhere, so every registration of the same file must land
    // on one spelling regardless of how the caller spelled it.
    file = File(canonicalLocalPath(file.path));
    String text = initialText ?? "";
    var openedReadOnly = openReadOnly;
    var tooLarge = false;
    if (initialText == null) {
      try {
        tooLarge = await file.length() > maxEditableFileLength;
        openedReadOnly = openedReadOnly || tooLarge;
        text = await file.readAsString();
      } on FileSystemException {
        return null;
      } on FormatException {
        // Binary or non-UTF-8 content reaching the headless path (session
        // restore has no context for dialogs): keep the buffer usable with a
        // malformed-tolerant decode and block editing so garbage is never
        // written back over the file.
        openedReadOnly = true;
        text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
      }
    }
    final projectPath = lspWorkspacePathForFile(file, ref.read(fileProvider));

    LspConfig? lspConfig;
    if (ref.read(useLsp) &&
        (path.extension(file.path) == ".py" || ref.read(lspAlwaysStart))) {
      final acquired = await _lspConfigPool.acquire(projectPath);
      lspConfig = acquired.config;
      if (lspConfig != null && acquired.created) {
        unawaited(_sendWorkspaceConfiguration(lspConfig));
      }
    }

    final CodeForgeController controller = PyriteCodeForgeController(
      lspConfig: lspConfig,
    );
    // Bind the path before the buffer. The editor widget only assigns
    // `openedFile` itself when it finds the path unset, and that assignment
    // re-reads the file from disk — which would clobber a restored unsaved
    // buffer with the stale on-disk text. The setter's own synchronous read
    // happens here, before `text` replaces it with the intended content; this
    // mirrors the preview pane in lsp_location_dialog, which pre-sets
    // `openedFile` for the same reason.
    controller.openedFile = file.path;
    controller.text = text;
    if (openedReadOnly) {
      controller.readOnly = true;
      // Only the size case gets a notice here: a binary file opened through
      // the interactive flow already saw its own dialog, and the headless
      // restore path surfaces its state through the read-only editor itself.
      if (tooLarge) {
        ref
            .read(ideMessageProvider.notifier)
            .show(
              translate(
                ref,
                I18nKey.editorFileTooLargeReadOnly,
              ).replaceAll('{path}', displayPathName(file.path)),
              type: IdeMessageType.warning,
              duration: const Duration(seconds: 12),
              closeable: true,
            );
      }
    }
    state = {...state, file.path: controller};
    controller.setDocumentColorsEnabled(ref.read(lspDocumentColor));
    if (ref.read(lspShowInlayHints)) {
      unawaited(_showInlayHintsWhenReady(controller));
    }
    return controller;
  }

  /// Builds a fresh LSP configuration for [workspacePath].
  ///
  /// Runs at most once per workspace at a time; the pool hands the result to
  /// every controller opened under the same root. Returning null (no
  /// executable configured, or the server failed to start) leaves the file's
  /// editor fully offline.
  Future<LspConfig?> _createWorkspaceLspConfig(String workspacePath) async {
    final type = ref.read(lspType);
    final capabilities = _readLspCapabilities(ref);
    final stubsConfig = buildLspStubsConfig(
      ref.read,
      workspacePath: workspacePath,
    );
    if (stubsConfig.paths.isNotEmpty) {
      ref
          .read(ideOutputLogProvider.notifier)
          .add(
            IdeOutputSource.ide,
            'LSP stubs paths: ${stubsConfig.paths.join(Platform.pathSeparator)}',
          );
    }
    if (stubsConfig.virtualEnvironment.isNotEmpty) {
      ref
          .read(ideOutputLogProvider.notifier)
          .add(
            IdeOutputSource.ide,
            'LSP virtual environment: ${stubsConfig.virtualEnvironment}',
          );
    }
    if (type == LspType.webSocket) {
      final config = LspSocketConfig(
        workspacePath: workspacePath,
        languageId: defaultLspLanguageId,
        serverUrl: "ws://${ref.read(lspWebSocketPath)}",
        capabilities: capabilities,
        initializationOptions: stubsConfig.initializationOptions,
        workspaceConfiguration: stubsConfig.workspaceConfiguration,
        disableWarning: ref.read(disableWarning),
        disableError: ref.read(disableError),
      );
      config.onUnexpectedExit = () => _onLspServerCrash(workspacePath, config);
      return config;
    }
    if (type == LspType.stdio) {
      final executable = ref.read(lspStdioExecutable).trim();
      if (executable.isEmpty) return null;
      final args = splitLspStdioArgs(ref.read(lspStdioArgs));
      try {
        final config = await LspStdioConfig.start(
          executable: executable,
          args: args,
          workspacePath: workspacePath,
          languageId: defaultLspLanguageId,
          capabilities: capabilities,
          initializationOptions: stubsConfig.initializationOptions,
          workspaceConfiguration: stubsConfig.workspaceConfiguration,
          environment: stubsConfig.environment,
          disableWarning: ref.read(disableWarning),
          disableError: ref.read(disableError),
        );
        config.onUnexpectedExit = () =>
            _onLspServerCrash(workspacePath, config);
        return config;
      } catch (e) {
        debugPrint('LSP stdio start failed: $e');
        ref
            .read(ideOutputLogProvider.notifier)
            .add(
              IdeOutputSource.ide,
              translate(
                ref,
                I18nKey.lspStartFailedOutput,
              ).replaceAll('{error}', e.toString()),
            );
        return null;
      }
    }
    return null;
  }

  void _updateInlayHintsVisibility(bool visible) {
    for (final controller in state.values) {
      if (visible) {
        unawaited(_showInlayHintsWhenReady(controller));
      } else {
        controller.hideInlayHints();
      }
    }
  }

  /// Restart bookkeeping for crashed language servers, keyed by workspace.
  final Set<String> _lspRestartInFlight = {};
  final Map<String, List<DateTime>> _lspCrashTimes = {};

  /// Called when a server dies without the client stopping it — a crashed
  /// stdio process or a dropped WebSocket connection. Schedules one restart
  /// per workspace; repeated crashes inside a minute give up for good, so a
  /// deterministically crashing server cannot turn into a restart loop.
  void _onLspServerCrash(String workspacePath, LspConfig deadConfig) {
    if (_lspRestartInFlight.contains(workspacePath)) return;
    _lspRestartInFlight.add(workspacePath);
    unawaited(_restartLspAfterCrash(workspacePath, deadConfig));
  }

  Future<void> _restartLspAfterCrash(
    String workspacePath,
    LspConfig deadConfig,
  ) async {
    try {
      final now = DateTime.now();
      final crashes = _lspCrashTimes.putIfAbsent(workspacePath, () => []);
      crashes.removeWhere(
        (time) => now.difference(time) > const Duration(minutes: 1),
      );
      crashes.add(now);
      if (crashes.length > 3) {
        // A server that keeps dying (zuban panicking on the same hover, for
        // example) must not turn into a restart loop; hand the decision back
        // to the user with one explicit notice.
        _lspCrashTimes.remove(workspacePath);
        _lspConfigPool.evict(workspacePath);
        final note = translate(ref, I18nKey.editorLspCrashLoopStopped);
        ref.read(ideOutputLogProvider.notifier).add(IdeOutputSource.ide, note);
        ref
            .read(ideMessageProvider.notifier)
            .show(
              note,
              type: IdeMessageType.warning,
              duration: const Duration(seconds: 12),
              closeable: true,
            );
        return;
      }

      // 1s, 2s, 4s… capped, so a workspace that recovers still restarts fast.
      final backoff = Duration(seconds: 1 << (crashes.length - 1).clamp(0, 5));
      await Future<void>.delayed(backoff);
      if (!ref.read(useLsp)) return;
      final affected = [
        for (final entry in state.entries)
          if (identical(entry.value.lspConfig, deadConfig)) entry.key,
      ];
      if (affected.isEmpty) return;
      for (final filePath in affected) {
        final controller = state[filePath];
        if (controller == null ||
            !identical(controller.lspConfig, deadConfig)) {
          continue;
        }
        _lspConfigPool.release(deadConfig);
        final acquired = await _lspConfigPool.acquire(workspacePath);
        final newConfig = acquired.config;
        if (newConfig == null) {
          ref
              .read(ideOutputLogProvider.notifier)
              .add(
                IdeOutputSource.ide,
                translate(
                  ref,
                  I18nKey.lspStartFailedOutput,
                ).replaceAll('{error}', 'restart'),
              );
          continue;
        }
        if (acquired.created) {
          unawaited(_sendWorkspaceConfiguration(newConfig));
        }
        await controller.reattachLsp(newConfig);
      }
      ref
          .read(ideOutputLogProvider.notifier)
          .add(
            IdeOutputSource.ide,
            translate(
              ref,
              I18nKey.editorLspCrashRestarted,
            ).replaceAll('{count}', crashes.length.toString()),
          );
    } catch (error) {
      debugPrint('LSP crash restart failed: $error');
    } finally {
      _lspRestartInFlight.remove(workspacePath);
    }
  }

  void _updateDocumentColorPicker(bool enabled) {
    for (final controller in state.values) {
      controller.setDocumentColorsEnabled(enabled, force: enabled);
    }
  }

  Future<void> _showInlayHintsWhenReady(CodeForgeController controller) async {
    for (var attempt = 0; attempt < 30; attempt++) {
      if (!ref.read(lspShowInlayHints)) return;
      final lspConfig = controller.lspConfig;
      if (lspConfig?.isInitialized == true && controller.openedFile != null) {
        await controller.showInlayHints(readOnly: false);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> _sendWorkspaceConfiguration(LspConfig lspConfig) async {
    if (lspConfig.workspaceConfiguration.isEmpty) return;
    for (var attempt = 0; attempt < 30; attempt++) {
      if (lspConfig.isInitialized) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!lspConfig.isInitialized) return;
    try {
      ref
          .read(ideOutputLogProvider.notifier)
          .add(
            IdeOutputSource.ide,
            'LSP workspace configuration: ${lspConfig.workspaceConfiguration}',
          );
      await lspConfig.sendNotification(
        method: 'workspace/didChangeConfiguration',
        params: {'settings': lspConfig.workspaceConfiguration},
      );
    } catch (error) {
      debugPrint('LSP workspace configuration failed: $error');
    }
  }

  UndoRedoController createNewUndoRedoController() {
    return UndoRedoController();
  }

  void movePath(String oldPath, String newPath) {
    if (oldPath == newPath) return;
    final controller = state[oldPath];
    if (controller == null) return;
    final next = Map<String, CodeForgeController>.from(state)
      ..remove(oldPath)
      ..[newPath] = controller;
    state = next;
  }

  /// Drops the controller registered for [filePath] from the map.
  ///
  /// Disposing the controller itself is left to the caller so tab teardown
  /// stays in one place. The controller's seat on its workspace's shared
  /// language server is released here; the server is stopped only when the
  /// last controller under that workspace root goes away.
  void removePath(String filePath) {
    if (!state.containsKey(filePath)) return;
    _lspConfigPool.release(state[filePath]?.lspConfig);
    state = Map<String, CodeForgeController>.from(state)..remove(filePath);
  }

  /// The value of the tab the editor is acting on.
  ///
  /// Null for tabs that are not documents -- a console surface dragged into the
  /// editor strip, or the welcome page -- which is what keeps the shared
  /// editing commands from reading document members off them.
  TabDataValue? get selectedEditorValue =>
      editorTabValueOf(ref.read(activeEditorControllerProvider).selectedTab);

  void redo() {
    if (selectedEditorValue?.type == "file") {
      getSelectedUndoRedoController()?.redo();
    }
  }

  void undo() {
    if (selectedEditorValue?.type == "file") {
      getSelectedUndoRedoController()?.undo();
    }
  }

  void cut() {
    if (selectedEditorValue?.type == "file") {
      getSelectedController()?.cut();
    }
  }

  void copy() {
    if (selectedEditorValue?.type == "file") {
      getSelectedController()?.copy();
    }
  }

  void paste() {
    if (selectedEditorValue?.type == "file") {
      getSelectedController()?.paste();
    }
  }

  CodeForgeController? getSelectedController() {
    return selectedEditorValue?.editorController;
  }

  UndoRedoController? getSelectedUndoRedoController() {
    return selectedEditorValue?.undoRedoController;
  }
}

final StateNotifierProvider<
  EditorControllerMapNotifier,
  Map<String, CodeForgeController>
>
editorControllerMapProvider = StateNotifierProvider(
  EditorControllerMapNotifier.new,
);

/// Snapshots the LSP capability settings as the client capabilities to negotiate.
///
/// Read in two places: when a workspace's server is created, and again on every
/// capability change so the already-running servers can be brought up to date.
LspClientCapabilities _readLspCapabilities(Ref ref) => LspClientCapabilities(
  semanticHighlighting: ref.read(lspSemanticHighlighting),
  codeCompletion: ref.read(lspCodeCompletion),
  hoverInfo: ref.read(lspHoverInfo),
  codeAction: ref.read(lspCodeAction),
  signatureHelp: ref.read(lspSignatureHelp),
  documentColor: ref.read(lspDocumentColor),
  documentHighlight: ref.read(lspDocumentHighlight),
  codeFolding: ref.read(lspCodeFolding),
  inlayHint: ref.read(lspShowInlayHints),
  goToDefinition: ref.read(lspGoToDefinition),
  rename: ref.read(lspRename),
);
