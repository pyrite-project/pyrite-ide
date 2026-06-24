import 'dart:io';
import 'package:code_forge/code_forge/code_area.dart';
import 'package:code_forge/code_forge/controller.dart';
import 'package:code_forge/code_forge/styling.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:m3_floating_toolbar/m3_floating_toolbar.dart';
import 'package:m3_floating_toolbar/m3_floating_toolbar_action.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/board_manager/utils.dart';
import 'package:pyrite_ide/core/services/editor/editor_controller_provider.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/board_file_items_provider.dart';
import 'package:pyrite_ide/core/services/file/board_workspace_provider.dart';
import 'package:pyrite_ide/core/services/file/local_file_items_provider.dart';
import 'package:pyrite_ide/core/services/file/local_workspace_provider.dart';
import 'package:pyrite_ide/core/services/file/upload_and_download_diff.dart';
import 'package:pyrite_ide/core/services/function_page.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/core/services/shortcut_utils.dart';
import 'package:re_highlight/languages/python.dart';

class EditCore extends ConsumerStatefulWidget {
  const EditCore({
    super.key,
    required this.file,
    required this.editorController,
  });
  final File file;
  final CodeForgeController editorController;

  @override
  ConsumerState<EditCore> createState() => _EditCoreState();
}

class _EditCoreState extends ConsumerState<EditCore> {
  @override
  Widget build(BuildContext context) {
    if (pendingUploadProviderMap[widget.file.path] == null) {
      pendingUploadProviderMap[widget.file.path] = StateProvider((ref) => null);
    }
    if (pendingDownloadProviderMap[widget.file.path] == null) {
      pendingDownloadProviderMap[widget.file.path] = StateProvider(
        (ref) => null,
      );
    }
    final pending = ref.watch(pendingUploadProviderMap[widget.file.path]!);
    final pendingDownload = ref.watch(
      pendingDownloadProviderMap[widget.file.path]!,
    );
    final confirmAct = ref.watch(confirmShortcutProvider);
    final cancelAct = ref.watch(cancelShortcutProvider);

    final bindings = <ShortcutActivator, VoidCallback>{
      SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
        saveFile(context, ref);
      },
      SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true): () {
        ref.read(localWorkspaceProvider.notifier).saveAs();
      },
      SingleActivator(LogicalKeyboardKey.keyN, control: true): () {
        ref.read(tabbedViewControllerProvider.notifier).createFile();
      },
      SingleActivator(LogicalKeyboardKey.keyO, control: true): () {
        ref.read(tabbedViewControllerProvider.notifier).openFile(context);
      },
      SingleActivator(LogicalKeyboardKey.keyU, control: true): () {
        ref
            .read(localWorkspaceProvider.notifier)
            .uploadSelectedLocalItem(context);
      },
      SingleActivator(LogicalKeyboardKey.keyR, control: true): () {
        runCurrentFile(context, ref);
      },
    };

    if (pending != null || pendingDownload != null) {
      bindings[stringToActivator(confirmAct)] = () =>
          _handleConfirm(context, ref);
      bindings[stringToActivator(cancelAct)] = () =>
          _handleCancel(context, ref);
    }

    return Focus(
      canRequestFocus: false,
      child: CallbackShortcuts(
        bindings: bindings,
        child: Stack(
          children: [
            body(context, ref),
            if (pending != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: Center(
                  child: M3FloatingToolbar(
                    actions: [
                      M3FloatingToolbarAction(
                        icon: Icons.close,
                        label: '取消',
                        onPressed: () => _handleCancel(context, ref),
                        semanticLabel: '',
                      ),
                      M3FloatingToolbarAction(
                        icon: Icons.cloud_upload,
                        label: '确认上传',
                        onPressed: () => _confirmUpload(ref, pending, context),
                        semanticLabel: '',
                      ),
                    ],
                  ),
                ),
              ),
            if (pendingDownload != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: Center(
                  child: M3FloatingToolbar(
                    actions: [
                      M3FloatingToolbarAction(
                        icon: Icons.close,
                        label: '取消',
                        onPressed: () => _handleCancel(context, ref),
                        semanticLabel: '',
                      ),
                      M3FloatingToolbarAction(
                        icon: Icons.cloud_download,
                        label: '确认下载',
                        onPressed: () =>
                            _confirmDownload(ref, pendingDownload, context),
                        semanticLabel: '',
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget body(BuildContext context, WidgetRef ref) {
    final theme = Map.of(ref.watch(editorThemeMode));
    return CodeForge(
      filePath: widget.file.path,
      editorTheme: theme,
      language: langPython,
      controller: widget.editorController,
      matchHighlightStyle: const MatchHighlightStyle(
        currentMatchStyle: TextStyle(backgroundColor: Color(0xFFFFA726)),
        otherMatchStyle: TextStyle(backgroundColor: Color(0x55FFFF00)),
      ),
      textStyle: TextStyle(
        fontSize: ref.watch(editorFontSize),
        fontFamily: editorTextFonts[ref.watch(editorTextFontProvider)],
      ),
      lineWrap: ref.watch(editorWordWrap),
      useSpaceAsTab: true,
      tabSize: 4,
    );
  }

  void _handleConfirm(BuildContext context, WidgetRef ref) {
    final pending = ref.read(pendingUploadProviderMap[widget.file.path]!);
    if (pending != null) {
      _confirmUpload(ref, pending, context);
      return;
    }
    final pendingDownload = ref.read(
      pendingDownloadProviderMap[widget.file.path]!,
    );
    if (pendingDownload != null) {
      _confirmDownload(ref, pendingDownload, context);
    }
  }

  void _handleCancel(BuildContext context, WidgetRef ref) {
    ref
        .read(editorControllerMapProvider.notifier)
        .getSelectedController()
        ?.clearGitDiffDecorations();
    // print(ref.read(editorControllerMapProvider));

    ref.read(pendingUploadProviderMap[widget.file.path]!.notifier).state = null;
    ref.read(pendingDownloadProviderMap[widget.file.path]!.notifier).state =
        null;
    if (context.mounted) context.go('/file');
  }

  Future<void> _confirmUpload(
    WidgetRef ref,
    PendingUpload pending,
    BuildContext context,
  ) async {
    try {
      ref
          .read(editorControllerMapProvider.notifier)
          .getSelectedController()
          ?.clearGitDiffDecorations();
      final currentContent = pending.content;
      await ref
          .read(boardWorkspaceProvider.notifier)
          .writeFile(pending.targetPath, currentContent);
      ref.read(boardFileItemsProvider.notifier).buildRootFileListItems();

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("已上传到设备：${pending.targetPath}")));
    } catch (_) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("上传失败")));
    } finally {
      ref.read(pendingUploadProviderMap[widget.file.path]!.notifier).state =
          null;
      if (context.mounted) context.go('/file');
    }
  }

  Future<void> _confirmDownload(
    WidgetRef ref,
    PendingDownload pending,
    BuildContext context,
  ) async {
    try {
      final currentContent = pending.content;
      await File(pending.localPath).writeAsString(currentContent);
      ref.read(localFileItemsProvider.notifier).buildRootFileListItems();
      ref
          .read(editorControllerMapProvider.notifier)
          .getSelectedController()
          ?.clearGitDiffDecorations();

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("已下载到本地：${pending.localPath}")));
    } catch (_) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("下载失败")));
    } finally {
      ref.read(pendingDownloadProviderMap[widget.file.path]!.notifier).state =
          null;
      if (context.mounted) context.go('/file');
    }
  }
}

Future<void> runCurrentFile(BuildContext context, WidgetRef ref) async {
  saveFile(context, ref, quiet: true);

  final controller = ref
      .read(editorControllerMapProvider.notifier)
      .getSelectedController();

  ref.read(consolePageShow.notifier).state = true;
  ref.read(getUsbSerialProvider().notifier).sendCommand("\x03");
  await Future.delayed(const Duration(milliseconds: 160));

  ref
      .read(getUsbSerialProvider().notifier)
      .sendCommand("exec('${controller!.text}')\r");
  showEditorSnackBar(context, "正在运行：${controller.openedFile}");
}

void showEditorSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future saveFile(BuildContext context, WidgetRef ref, {quiet = false}) async {
  await ref.read(localWorkspaceProvider.notifier).saveFile();

  if (!quiet) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("已保存当前文件")));
  }
}
