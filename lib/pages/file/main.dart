import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/services/file/ui_utils.dart';
import 'package:pyrite_ide/core/services/serial/device_executor.dart';
import 'package:pyrite_ide/core/services/serial/utils.dart';
import 'package:pyrite_ide/core/services/file/board_file_items_provider.dart';
import 'package:pyrite_ide/core/services/file/board_provider.dart';
import 'package:pyrite_ide/core/services/file/board_file_tree_view.dart';
import 'package:pyrite_ide/core/services/file/local_file_items_provider.dart';
import 'package:pyrite_ide/core/services/file/local_file_tree_view.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/core/services/file/local_utils.dart' as local;
import 'package:pyrite_ide/core/services/message/ide_message.dart';
import 'package:pyrite_ide/shared/md3_widgets.dart';
import 'package:pyrite_ide/shared/pyrite_context_menu.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import 'package:super_context_menu/super_context_menu.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:super_tree/super_tree.dart';

final localFileSelectionModeProvider = StateProvider<bool>((ref) => false);
final boardFileSelectionModeProvider = StateProvider<bool>((ref) => false);
final localFileScrollControllerProvider = Provider.autoDispose((ref) {
  final controller = ScrollController();
  ref.onDispose(controller.dispose);
  return controller;
});
final boardFileScrollControllerProvider = Provider.autoDispose((ref) {
  final controller = ScrollController();
  ref.onDispose(controller.dispose);
  return controller;
});

enum _FileDragSource { local, board }

class _FileDragData {
  const _FileDragData({required this.source, required this.paths});

  final _FileDragSource source;
  final List<String> paths;
}

const _dragSourceKey = 'source';
const _dragPathsKey = 'paths';
const _localDragSourceValue = 'local';
const _boardDragSourceValue = 'board';
final Map<String, Rect> _dragHandleRects = <String, Rect>{};
final Map<_FileDragSource, Rect> _dropRegionRects = <_FileDragSource, Rect>{};

class _DropRegionBounds extends SingleChildRenderObjectWidget {
  const _DropRegionBounds({required this.source, required super.child});

  final _FileDragSource source;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderDropRegionBounds(source);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderDropRegionBounds renderObject,
  ) {
    renderObject.source = source;
  }
}

class _RenderDropRegionBounds extends RenderProxyBox {
  _RenderDropRegionBounds(this._source);

  _FileDragSource _source;

  set source(_FileDragSource value) {
    if (_source == value) return;
    _dropRegionRects.remove(_source);
    _source = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (hasSize) {
      _dropRegionRects[_source] = localToGlobal(Offset.zero) & size;
    }
  }

  @override
  void detach() {
    _dropRegionRects.remove(_source);
    super.detach();
  }
}

void _scrollControllerBy(ScrollController controller, double delta) {
  if (!controller.hasClients || delta == 0) return;
  final position = controller.position;
  final next = (position.pixels + delta).clamp(
    position.minScrollExtent,
    position.maxScrollExtent,
  );
  if (next == position.pixels) return;
  position.jumpTo(next);
}

class _DragHandleBounds extends SingleChildRenderObjectWidget {
  const _DragHandleBounds({required this.handleId, required super.child});

  final String handleId;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderDragHandleBounds(handleId);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderDragHandleBounds renderObject,
  ) {
    renderObject.handleId = handleId;
  }
}

class _RenderDragHandleBounds extends RenderProxyBox {
  _RenderDragHandleBounds(this._handleId);

  String _handleId;

  set handleId(String value) {
    if (_handleId == value) return;
    _dragHandleRects.remove(_handleId);
    _handleId = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (hasSize) {
      _dragHandleRects[_handleId] = localToGlobal(Offset.zero) & size;
    }
  }

  @override
  void detach() {
    _dragHandleRects.remove(_handleId);
    super.detach();
  }
}

class ProjectFiles extends ConsumerWidget {
  const ProjectFiles({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final body = buildWorkspace(context, ref);

    return Scaffold(body: body);
  }

  Widget buildWorkspace(BuildContext context, WidgetRef ref) {
    return shadcn.ShadcnLayer(
      theme: shadcn.ThemeData(
        colorScheme: Theme.of(context).brightness == Brightness.light
            ? shadcn.ColorSchemes.lightNeutral
            : shadcn.ColorSchemes.darkNeutral,
      ),
      child: shadcn.ResizablePanel.vertical(
        optionalDivider: false,
        draggerBuilder: (context) {
          return shadcn.HorizontalResizableDragger();
        },
        children: [
          shadcn.ResizablePane.flex(
            initialFlex: 1,
            minSize: 180,
            child: buildLocalDropRegion(
              context,
              ref,
              buildLocalFiles(context, ref),
            ),
          ),
          shadcn.ResizablePane.flex(
            initialFlex: 1,
            minSize: 180,
            child: buildBoardDropRegion(
              context,
              ref,
              buildBoardFiles(context, ref),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildLocalDropRegion(
    BuildContext context,
    WidgetRef ref,
    Widget child,
  ) {
    final scrollController = ref.watch(localFileScrollControllerProvider);
    return _DropRegionBounds(
      source: _FileDragSource.local,
      child: DropRegion(
        formats: const [Formats.fileUri, Formats.plainText],
        hitTestBehavior: HitTestBehavior.opaque,
        onDropOver: (event) {
          _autoScrollDropRegion(
            _FileDragSource.local,
            scrollController,
            event.position.global,
          );
          return _hasDragSource(event.session, _FileDragSource.local)
              ? DropOperation.move
              : _hasDragSource(event.session, _FileDragSource.board) ||
                    _hasExternalFiles(event.session)
              ? DropOperation.copy
              : DropOperation.none;
        },
        onPerformDrop: (event) async {
          final targetFolderPath = _localFolderPathForDrop(
            ref,
            event.position.global,
          );
          final localData = _dragData(event.session, _FileDragSource.local);
          if (localData != null && localData.paths.isNotEmpty) {
            final targetFolder =
                targetFolderPath ?? ref.read(fileProvider)?.path;
            if (targetFolder == null) return;
            await _moveLocalPathsToFolder(
              context,
              ref,
              localData.paths,
              targetFolder,
            );
            return;
          }

          final data = _dragData(event.session, _FileDragSource.board);
          if (data != null && data.paths.isNotEmpty) {
            _selectBoardPaths(ref, data.paths);
            await _downloadSelectedBoardItems(
              context,
              ref,
              localFolderPath: targetFolderPath,
            );
            return;
          }

          final paths = await _externalFilePaths(event.session);
          if (paths.isEmpty) return;
          await _importExternalPaths(
            context,
            ref,
            paths,
            localFolderPath: targetFolderPath,
          );
        },
        child: child,
      ),
    );
  }

  Widget buildBoardDropRegion(
    BuildContext context,
    WidgetRef ref,
    Widget child,
  ) {
    final scrollController = ref.watch(boardFileScrollControllerProvider);
    return _DropRegionBounds(
      source: _FileDragSource.board,
      child: DropRegion(
        formats: const [Formats.fileUri, Formats.plainText],
        hitTestBehavior: HitTestBehavior.opaque,
        onDropOver: (event) {
          _autoScrollDropRegion(
            _FileDragSource.board,
            scrollController,
            event.position.global,
          );
          return ref.read(getUsbSerialProvider()).isConnected &&
                  _hasDragSource(event.session, _FileDragSource.board)
              ? DropOperation.move
              : ref.read(getUsbSerialProvider()).isConnected &&
                    (_hasDragSource(event.session, _FileDragSource.local) ||
                        _hasExternalFiles(event.session))
              ? DropOperation.copy
              : DropOperation.none;
        },
        onPerformDrop: (event) async {
          final targetFolderPath = _boardFolderPathForDrop(
            ref,
            event.position.global,
          );
          final boardData = _dragData(event.session, _FileDragSource.board);
          if (boardData != null && boardData.paths.isNotEmpty) {
            await _moveBoardPathsToFolder(
              context,
              ref,
              boardData.paths,
              targetFolderPath ?? '/',
            );
            return;
          }

          final data = _dragData(event.session, _FileDragSource.local);
          if (data != null && data.paths.isNotEmpty) {
            _selectLocalPaths(ref, data.paths);
            await _uploadSelectedLocalItems(
              context,
              ref,
              boardFolderPath: targetFolderPath,
            );
            return;
          }

          final paths = await _externalFilePaths(event.session);
          if (paths.isEmpty) return;
          await _uploadLocalPaths(
            context,
            ref,
            paths,
            boardFolderPath: targetFolderPath,
          );
        },
        child: child,
      ),
    );
  }

  void _autoScrollDropRegion(
    _FileDragSource source,
    ScrollController controller,
    Offset globalPosition,
  ) {
    final rect = _dropRegionRects[source];
    if (rect == null) return;
    const edgeThreshold = 56.0;
    const maxDelta = 28.0;
    final distanceToTop = globalPosition.dy - rect.top;
    final distanceToBottom = rect.bottom - globalPosition.dy;
    if (distanceToTop < edgeThreshold) {
      final ratio = ((edgeThreshold - distanceToTop) / edgeThreshold).clamp(
        0.0,
        1.0,
      );
      _scrollBy(controller, -maxDelta * ratio);
    } else if (distanceToBottom < edgeThreshold) {
      final ratio = ((edgeThreshold - distanceToBottom) / edgeThreshold).clamp(
        0.0,
        1.0,
      );
      _scrollBy(controller, maxDelta * ratio);
    }
  }

  void _scrollBy(ScrollController controller, double delta) {
    _scrollControllerBy(controller, delta);
  }

  String? _localFolderPathForDrop(WidgetRef ref, Offset globalPosition) {
    final controller = ref.read(localFileTreeViewControllerProvider);
    final targetNode = controller.findVisibleNodeAtGlobalPosition(
      globalPosition,
    );
    if (targetNode != null) {
      if (targetNode.data is FolderItem) return targetNode.id;
      return path.dirname(targetNode.id);
    }

    return ref.read(fileProvider.notifier).getFocusFolderNode()?.id;
  }

  String? _boardFolderPathForDrop(WidgetRef ref, Offset globalPosition) {
    final controller = ref.read(boardFileTreeViewControllerProvider);
    final targetNode = controller.findVisibleNodeAtGlobalPosition(
      globalPosition,
    );
    if (targetNode != null) {
      if (targetNode.data is FolderItem) return targetNode.id;
      return path.posix.dirname(targetNode.id);
    }

    return ref.read(boardProvider.notifier).getFocusFolderNode()?.id ?? '/';
  }

  String _localMoveTargetFolder(
    WidgetRef ref,
    TreeNode<FileSystemItem> targetNode,
    NodeDropPosition position,
  ) {
    if (position == NodeDropPosition.inside && targetNode.data is FolderItem) {
      return targetNode.id;
    }
    return targetNode.parent?.id ?? ref.read(fileProvider)!.path;
  }

  String _boardMoveTargetFolder(
    TreeNode<FileSystemItem> targetNode,
    NodeDropPosition position,
  ) {
    if (position == NodeDropPosition.inside && targetNode.data is FolderItem) {
      return targetNode.id;
    }
    return targetNode.parent?.id ?? '/';
  }

  List<TreeNode<FileSystemItem>> _localNodesForPaths(
    WidgetRef ref,
    List<String> paths,
  ) {
    final controller = ref.read(localFileTreeViewControllerProvider);
    return paths
        .map(controller.findNodeById)
        .whereType<TreeNode<FileSystemItem>>()
        .toList(growable: false);
  }

  List<TreeNode<FileSystemItem>> _boardNodesForPaths(
    WidgetRef ref,
    List<String> paths,
  ) {
    final controller = ref.read(boardFileTreeViewControllerProvider);
    return paths
        .map(controller.findNodeById)
        .whereType<TreeNode<FileSystemItem>>()
        .toList(growable: false);
  }

  Future<void> _moveLocalPathsToFolder(
    BuildContext context,
    WidgetRef ref,
    List<String> paths,
    String targetFolder,
  ) async {
    final nodes = _localNodesForPaths(ref, paths)
        .where((node) => !_isLocalNodeAlreadyInFolder(node, targetFolder))
        .toList(growable: false);
    if (nodes.isEmpty) return;

    await _moveLocalNodesToFolder(
      context,
      ref,
      nodes,
      TreeNode(id: targetFolder, data: FolderItem(path.basename(targetFolder))),
      NodeDropPosition.inside,
    );
  }

  Future<void> _moveBoardPathsToFolder(
    BuildContext context,
    WidgetRef ref,
    List<String> paths,
    String targetFolder,
  ) async {
    final nodes = _boardNodesForPaths(ref, paths)
        .where((node) => !_isBoardNodeAlreadyInFolder(node, targetFolder))
        .toList(growable: false);
    if (nodes.isEmpty) return;

    await _moveBoardNodesToFolder(
      context,
      ref,
      nodes,
      TreeNode(
        id: targetFolder,
        data: FolderItem(path.posix.basename(targetFolder)),
      ),
      NodeDropPosition.inside,
    );
  }

  Future<bool> _moveLocalNodesToFolder(
    BuildContext context,
    WidgetRef ref,
    List<TreeNode<FileSystemItem>> draggedNodes,
    TreeNode<FileSystemItem> targetNode,
    NodeDropPosition position,
  ) async {
    final targetFolder = _localMoveTargetFolder(ref, targetNode, position);
    final nodes = draggedNodes
        .where((node) => !_isLocalNodeAlreadyInFolder(node, targetFolder))
        .toList(growable: false);
    if (nodes.isEmpty) return true;

    unawaited(_confirmAndMoveLocalNodes(context, ref, nodes, targetFolder));
    return true;
  }

  Future<void> _confirmAndMoveLocalNodes(
    BuildContext context,
    WidgetRef ref,
    List<TreeNode<FileSystemItem>> nodes,
    String targetFolder,
  ) async {
    await Future<void>.delayed(Duration.zero);
    if (!context.mounted) return;
    if (!await _confirmMoveItems(context, nodes, targetFolder)) return;
    try {
      await ref
          .read(fileProvider.notifier)
          .moveLocalNodes(context, nodes, targetFolder);
    } catch (error) {
      if (!context.mounted) return;
      showIdeError(context, "移动失败：$error");
    }
  }

  Future<bool> _moveBoardNodesToFolder(
    BuildContext context,
    WidgetRef ref,
    List<TreeNode<FileSystemItem>> draggedNodes,
    TreeNode<FileSystemItem> targetNode,
    NodeDropPosition position,
  ) async {
    final targetFolder = _boardMoveTargetFolder(targetNode, position);
    final nodes = draggedNodes
        .where((node) => !_isBoardNodeAlreadyInFolder(node, targetFolder))
        .toList(growable: false);
    if (nodes.isEmpty) return true;

    unawaited(_confirmAndMoveBoardNodes(context, ref, nodes, targetFolder));
    return true;
  }

  Future<void> _confirmAndMoveBoardNodes(
    BuildContext context,
    WidgetRef ref,
    List<TreeNode<FileSystemItem>> nodes,
    String targetFolder,
  ) async {
    await Future<void>.delayed(Duration.zero);
    if (!context.mounted) return;
    if (!await _confirmMoveItems(context, nodes, targetFolder)) return;
    try {
      await ref
          .read(boardProvider.notifier)
          .moveBoardNodes(context, nodes, targetFolder);
    } on DeviceNotReadyException catch (_) {
      if (!context.mounted) return;
      final sendCtrlC = await showDeviceNotReadyDialog(
        context,
        operation: "移动设备文件",
      );
      if (sendCtrlC) {
        ref.read(getUsbSerialProvider().notifier).sendCommand("\x03");
      }
    } catch (error) {
      if (!context.mounted) return;
      showIdeError(context, "移动失败：$error");
    }
  }

  Future<bool> _confirmMoveItems(
    BuildContext context,
    List<TreeNode<FileSystemItem>> nodes,
    String targetFolder,
  ) async {
    final sourceLabel = nodes.length == 1
        ? nodes.single.data.name
        : "选中的 ${nodes.length} 个项目";
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.drive_file_move_outline),
        title: const Text("确认移动"),
        content: Text("是否要将「$sourceLabel」移动到「$targetFolder」？"),
        actions: [
          TextButton(onPressed: () => ctx.pop(false), child: const Text("取消")),
          FilledButton(onPressed: () => ctx.pop(true), child: const Text("移动")),
        ],
      ),
    );
    return result ?? false;
  }

  bool _isLocalNodeAlreadyInFolder(
    TreeNode<FileSystemItem> node,
    String targetFolder,
  ) {
    return path.equals(
      path.normalize(path.absolute(path.dirname(node.id))),
      path.normalize(path.absolute(targetFolder)),
    );
  }

  bool _isBoardNodeAlreadyInFolder(
    TreeNode<FileSystemItem> node,
    String targetFolder,
  ) {
    final parent = path.posix.normalize(path.posix.dirname(node.id));
    final target = path.posix.normalize(
      targetFolder.isEmpty ? '/' : targetFolder,
    );
    return parent == target;
  }

  Future<void> _downloadSelectedBoardItems(
    BuildContext context,
    WidgetRef ref, {
    String? localFolderPath,
  }) async {
    try {
      await ref
          .read(boardProvider.notifier)
          .downloadSelectedBoardItems(
            context,
            localFolderPath: localFolderPath,
          );
    } on DeviceNotReadyException catch (_) {
      if (!context.mounted) return;
      final sendCtrlC = await showDeviceNotReadyDialog(
        context,
        operation: "下载设备文件",
      );
      if (sendCtrlC) {
        ref.read(getUsbSerialProvider().notifier).sendCommand("\x03");
      }
    } catch (error) {
      if (!context.mounted) return;
      showIdeError(context, "下载失败：$error");
    }
  }

  Future<void> _uploadSelectedLocalItems(
    BuildContext context,
    WidgetRef ref, {
    String? boardFolderPath,
  }) async {
    try {
      await ref
          .read(fileProvider.notifier)
          .uploadSelectedLocalItems(context, boardFolderPath: boardFolderPath);
    } on DeviceNotReadyException catch (_) {
      if (!context.mounted) return;
      final sendCtrlC = await showDeviceNotReadyDialog(
        context,
        operation: "上传文件到设备",
      );
      if (sendCtrlC) {
        ref.read(getUsbSerialProvider().notifier).sendCommand("\x03");
      }
    } catch (error) {
      if (!context.mounted) return;
      showIdeError(context, "上传失败：$error");
    }
  }

  Future<void> _importExternalPaths(
    BuildContext context,
    WidgetRef ref,
    List<String> paths, {
    String? localFolderPath,
  }) async {
    try {
      await ref
          .read(fileProvider.notifier)
          .importExternalPaths(
            context,
            paths,
            localFolderPath: localFolderPath,
          );
    } catch (error) {
      if (!context.mounted) return;
      showIdeError(context, "导入失败：$error");
    }
  }

  Future<void> _uploadLocalPaths(
    BuildContext context,
    WidgetRef ref,
    List<String> paths, {
    String? boardFolderPath,
  }) async {
    try {
      await ref
          .read(fileProvider.notifier)
          .uploadLocalPaths(context, paths, boardFolderPath: boardFolderPath);
    } on DeviceNotReadyException catch (_) {
      if (!context.mounted) return;
      final sendCtrlC = await showDeviceNotReadyDialog(
        context,
        operation: "上传文件到设备",
      );
      if (sendCtrlC) {
        ref.read(getUsbSerialProvider().notifier).sendCommand("\x03");
      }
    } catch (error) {
      if (!context.mounted) return;
      showIdeError(context, "上传失败：$error");
    }
  }

  bool _hasDragSource(DropSession session, _FileDragSource source) {
    return _dragData(session, source) != null;
  }

  bool _hasExternalFiles(DropSession session) {
    return session.items.any((item) => item.canProvide(Formats.fileUri));
  }

  Future<List<String>> _externalFilePaths(DropSession session) async {
    final paths = <String>[];
    for (final item in session.items) {
      final uri = await _readFileUri(item);
      if (uri != null && uri.isScheme('file')) {
        paths.add(uri.toFilePath());
      }
    }
    return paths;
  }

  Future<Uri?> _readFileUri(DropItem item) async {
    final reader = item.dataReader;
    if (reader == null || !reader.canProvide(Formats.fileUri)) return null;

    final completer = Completer<Uri?>();
    final progress = reader.getValue<Uri>(
      Formats.fileUri,
      (value) => completer.complete(value),
      onError: completer.completeError,
    );
    if (progress == null) return null;
    return completer.future;
  }

  _FileDragData? _dragData(DropSession session, _FileDragSource source) {
    for (final item in session.items) {
      final localData = item.localData;
      if (localData is Map) {
        final sourceValue = localData[_dragSourceKey];
        final expectedSourceValue = source == _FileDragSource.local
            ? _localDragSourceValue
            : _boardDragSourceValue;
        if (sourceValue != expectedSourceValue) continue;

        final rawPaths = localData[_dragPathsKey];
        if (rawPaths is! List) continue;
        final paths = rawPaths.whereType<String>().toList(growable: false);
        if (paths.isEmpty) continue;
        return _FileDragData(source: source, paths: paths);
      }
    }
    return null;
  }

  void _selectLocalPaths(WidgetRef ref, List<String> paths) {
    final controller = ref.read(localFileTreeViewControllerProvider);
    controller.deselectAll();
    for (final path in paths) {
      if (controller.findNodeById(path) != null) {
        controller.toggleSelection(path);
      }
    }
  }

  void _selectBoardPaths(WidgetRef ref, List<String> paths) {
    final controller = ref.read(boardFileTreeViewControllerProvider);
    controller.deselectAll();
    for (final path in paths) {
      if (controller.findNodeById(path) != null) {
        controller.toggleSelection(path);
      }
    }
  }

  Widget _wrapFileDragSource({
    required WidgetRef ref,
    required TreeNode<FileSystemItem> node,
    required _FileDragSource source,
    required Widget child,
  }) {
    return DragItemWidget(
      allowedOperations: () => [DropOperation.copy, DropOperation.move],
      dragItemProvider: (_) {
        final paths = source == _FileDragSource.local
            ? _localDragPaths(ref, node)
            : _boardDragPaths(ref, node);
        if (paths.isEmpty) return null;
        final item = DragItem(
          localData: {
            _dragSourceKey: source == _FileDragSource.local
                ? _localDragSourceValue
                : _boardDragSourceValue,
            _dragPathsKey: paths,
          },
        );
        item.add(Formats.plainText(paths.join('\n')));
        return item;
      },
      child: child,
    );
  }

  Widget _buildDragHandle(_FileDragSource source, String nodeId) {
    final handleId = _dragHandleId(source, nodeId);
    return DraggableWidget(
      hitTestBehavior: HitTestBehavior.opaque,
      child: Tooltip(
        message: "拖拽选中项",
        child: _DragHandleBounds(
          handleId: handleId,
          child: const SizedBox.square(
            dimension: 28,
            child: Icon(Icons.drag_indicator, size: 18),
          ),
        ),
      ),
    );
  }

  String _dragHandleId(_FileDragSource source, String nodeId) {
    return '${source.name}:$nodeId';
  }

  bool _isDragHandlePointer(
    _FileDragSource source,
    String nodeId,
    Offset globalPosition,
  ) {
    return _dragHandleRects[_dragHandleId(source, nodeId)]?.contains(
          globalPosition,
        ) ??
        false;
  }

  List<String> _localDragPaths(WidgetRef ref, TreeNode<FileSystemItem> node) {
    final controller = ref.read(localFileTreeViewControllerProvider);
    if (!controller.selectedNodeIds.contains(node.id)) return [node.id];
    return ref
        .read(fileProvider.notifier)
        .getSelectedNodes()
        .map((node) => node.id)
        .toList(growable: false);
  }

  List<String> _boardDragPaths(WidgetRef ref, TreeNode<FileSystemItem> node) {
    final controller = ref.read(boardFileTreeViewControllerProvider);
    if (!controller.selectedNodeIds.contains(node.id)) return [node.id];
    return ref
        .read(boardProvider.notifier)
        .getSelectedNodes()
        .map((node) => node.id)
        .toList(growable: false);
  }

  Menu _buildLocalNodeMenu(
    BuildContext context,
    WidgetRef ref,
    Directory localWorkspace,
    TreeNode<FileSystemItem> node,
  ) {
    final localController = ref.read(localFileTreeViewControllerProvider);
    if (!localController.selectedNodeIds.contains(node.id)) {
      localController.setSelectedNodeId(node.id);
    }
    final selectedNodes = ref.read(fileProvider.notifier).getSelectedNodes();
    final selectedCount = selectedNodes.length;

    final TreeNode<FileSystemItem>? boardFileTarget = ref
        .read(boardProvider.notifier)
        .getFocusFileNode();
    final TreeNode<FileSystemItem>? boardFolderTarget = ref
        .read(boardProvider.notifier)
        .getFocusFolderNode();
    final TreeNode<FileSystemItem>? localFolderTarget = ref
        .read(fileProvider.notifier)
        .getFocusFolderNode();

    return Menu(
      children: [
        MenuAction(
          title: "重命名",
          callback: () => ref
              .read(localFileTreeViewControllerProvider)
              .setRenamingNodeId(node.id),
          attributes: MenuActionAttributes(disabled: selectedCount != 1),
        ),
        MenuAction(
          title: selectedCount > 1 ? "删除选中的 $selectedCount 个项目" : "删除",
          callback: () async {
            if (await confirmDelete(
              context,
              selectedCount > 1 ? "$selectedCount 个项目" : node.data.name,
            )) {
              await ref
                  .read(fileProvider.notifier)
                  .deleteSelectedLocalItems(context);
            }
          },
        ),
        MenuSeparator(),
        MenuAction(
          title: selectedCount > 1
              ? "上传选中的 $selectedCount 个项目到设备文件夹 ${boardFolderTarget?.id ?? "/"}"
              : "上传到设备文件夹 ${boardFolderTarget?.id ?? "/"}",
          callback: () => _uploadSelectedLocalItems(context, ref),
          attributes: MenuActionAttributes(
            disabled: !ref.watch(getUsbSerialProvider()).isConnected,
          ),
        ),
        MenuAction(
          title: "覆盖设备文件 ${boardFileTarget?.id ?? "（未选择设备文件）"}",
          callback: () async {
            try {
              final bytes = await File(node.id).readAsBytes();
              await ref
                  .read(boardProvider.notifier)
                  .writeFileBytes(boardFileTarget!.id, bytes);
              ref
                  .read(boardFileItemsProvider.notifier)
                  .buildRootFileListItems();

              if (!context.mounted) return;
              showEditorSnackBar(context, "已覆盖设备文件：${boardFileTarget.id}");
            } on DeviceNotReadyException catch (_) {
              if (!context.mounted) return;
              final sendCtrlC = await showDeviceNotReadyDialog(
                context,
                operation: "覆盖设备文件",
              );
              if (sendCtrlC) {
                ref.read(getUsbSerialProvider().notifier).sendCommand("\x03");
              }
            }
          },
          attributes: MenuActionAttributes(
            disabled:
                !ref.watch(getUsbSerialProvider()).isConnected ||
                selectedCount != 1 ||
                (boardFileTarget == null || (node.data is FolderItem)),
          ),
        ),
        MenuSeparator(),
        MenuAction(
          title: "在 ${localFolderTarget?.id ?? localWorkspace.path} 新建文件",
          callback: () async {
            final parentDir = localFolderTarget?.id ?? localWorkspace.path;
            final uniquePath = await local.getUniqueFilePath(
              path.join(parentDir, "new_file"),
            );
            await ref.read(fileProvider.notifier).createFile(uniquePath);
          },
        ),
        MenuAction(
          title: "在 ${localFolderTarget?.id ?? localWorkspace.path} 新建文件夹",
          callback: () async {
            final parentDir = localFolderTarget?.id ?? localWorkspace.path;
            final uniquePath = await local.getUniqueFolderPath(
              path.join(parentDir, "new_folder"),
            );
            await ref.read(fileProvider.notifier).createFolder(uniquePath);
          },
        ),
      ],
    );
  }

  Menu _buildBoardNodeMenu(
    BuildContext context,
    WidgetRef ref,
    TreeNode<FileSystemItem> node,
  ) {
    final boardController = ref.read(boardFileTreeViewControllerProvider);
    if (!boardController.selectedNodeIds.contains(node.id)) {
      boardController.setSelectedNodeId(node.id);
    }
    final selectedNodes = ref.read(boardProvider.notifier).getSelectedNodes();
    final selectedCount = selectedNodes.length;

    final TreeNode<FileSystemItem>? localFileTarget = ref
        .read(fileProvider.notifier)
        .getFocusFileNode();
    final TreeNode<FileSystemItem>? localFolderTarget = ref
        .read(fileProvider.notifier)
        .getFocusFolderNode();

    return Menu(
      children: [
        MenuAction(
          title: "重命名",
          callback: () => ref
              .read(boardFileTreeViewControllerProvider)
              .setRenamingNodeId(node.id),
          attributes: MenuActionAttributes(disabled: selectedCount != 1),
        ),
        MenuAction(
          title: selectedCount > 1 ? "删除选中的 $selectedCount 个项目" : "删除",
          callback: () async {
            if (await confirmDelete(
              context,
              selectedCount > 1 ? "$selectedCount 个项目" : node.data.name,
            )) {
              try {
                await ref
                    .read(boardProvider.notifier)
                    .deleteSelectedBoardItems(context);
              } on DeviceNotReadyException catch (_) {
                if (!context.mounted) return;
                final sendCtrlC = await showDeviceNotReadyDialog(
                  context,
                  operation: "删除设备文件",
                );
                if (sendCtrlC) {
                  ref.read(getUsbSerialProvider().notifier).sendCommand("\x03");
                }
              }
            }
          },
        ),
        MenuSeparator(),
        MenuAction(
          title: selectedCount > 1
              ? "下载选中的 $selectedCount 个项目到本地文件夹 ${localFolderTarget?.id ?? ref.watch(fileProvider)?.path ?? "（未打开本地项目）"}"
              : "下载到本地文件夹 ${localFolderTarget?.id ?? ref.watch(fileProvider)?.path ?? "（未打开本地项目）"}",
          callback: () => _downloadSelectedBoardItems(context, ref),
          attributes: MenuActionAttributes(
            disabled:
                !ref.watch(getUsbSerialProvider()).isConnected ||
                (ref.watch(fileProvider)?.path == null),
          ),
        ),
        MenuAction(
          title: "覆盖本地文件 ${localFileTarget?.id ?? "（未选择本地文件）"}",
          callback: () async {
            try {
              final bytes = await ref
                  .read(boardProvider.notifier)
                  .getFileBytes(node.id);
              await File(localFileTarget!.id).writeAsBytes(bytes);
              ref
                  .read(localFileItemsProvider.notifier)
                  .buildRootFileListItems();

              if (!context.mounted) return;
              showEditorSnackBar(context, "已覆盖本地文件：${localFileTarget.id}");
            } on DeviceNotReadyException catch (_) {
              if (!context.mounted) return;
              final sendCtrlC = await showDeviceNotReadyDialog(
                context,
                operation: "读取设备文件",
              );
              if (sendCtrlC) {
                ref.read(getUsbSerialProvider().notifier).sendCommand("\x03");
              }
            }
          },
          attributes: MenuActionAttributes(
            disabled:
                (localFileTarget == null) ||
                selectedCount != 1 ||
                ((ref.watch(fileProvider)?.path == null) ||
                    (node.data is FolderItem)),
          ),
        ),
      ],
    );
  }

  Widget buildLocalHeader(
    BuildContext context,
    WidgetRef ref,
    Directory localWorkspace,
  ) {
    final selectionMode = ref.watch(localFileSelectionModeProvider);
    final controller = ref.watch(localFileTreeViewControllerProvider);
    final isConnected = ref.watch(getUsbSerialProvider()).isConnected;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final selectedCount = controller.selectedNodeIds.length;
        return PaneHeader(
          title: selectionMode ? "已选择 $selectedCount 项" : "本地项目",
          subtitle: localWorkspace.path,
          leadingIcon: selectionMode ? Icons.checklist : Icons.folder_outlined,
          compact: true,
          actions: selectionMode
              ? [
                  IconButton(
                    tooltip: "上传选中项",
                    onPressed: isConnected && selectedCount > 0
                        ? () => _uploadSelectedLocalItems(context, ref)
                        : null,
                    icon: const Icon(Icons.upload_outlined),
                  ),
                  IconButton(
                    tooltip: "删除选中项",
                    onPressed: selectedCount > 0
                        ? () async {
                            if (await confirmDelete(
                              context,
                              "$selectedCount 个项目",
                            )) {
                              await ref
                                  .read(fileProvider.notifier)
                                  .deleteSelectedLocalItems(context);
                            }
                          }
                        : null,
                    icon: const Icon(Icons.delete_outline),
                  ),
                  IconButton(
                    tooltip: "清除选择",
                    onPressed: selectedCount > 0
                        ? () => controller.deselectAll()
                        : null,
                    icon: const Icon(Icons.deselect),
                  ),
                  IconButton(
                    tooltip: "退出选择模式",
                    onPressed: () {
                      controller.deselectAll();
                      ref.read(localFileSelectionModeProvider.notifier).state =
                          false;
                    },
                    icon: const Icon(Icons.close),
                  ),
                ]
              : [
                  IconButton(
                    tooltip: "选择项目",
                    onPressed: () {
                      ref.read(localFileSelectionModeProvider.notifier).state =
                          true;
                    },
                    icon: const Icon(Icons.checklist),
                  ),
                  IconButton(
                    tooltip: "新建文件",
                    onPressed: () async {
                      final parentPath = ref.read(fileProvider)?.path ?? '';
                      final uniquePath = await local.getUniqueFilePath(
                        path.join(parentPath, "new_file"),
                      );
                      await ref
                          .read(fileProvider.notifier)
                          .createFile(uniquePath);
                    },
                    icon: const Icon(Icons.note_add_outlined),
                  ),
                  IconButton(
                    tooltip: "新建文件夹",
                    onPressed: () async {
                      final parentPath = ref.read(fileProvider)?.path ?? '';
                      final uniquePath = await local.getUniqueFolderPath(
                        path.join(parentPath, "new_folder"),
                      );
                      await ref
                          .read(fileProvider.notifier)
                          .createFolder(uniquePath);
                    },
                    icon: const Icon(Icons.create_new_folder_outlined),
                  ),
                  IconButton(
                    tooltip: "刷新本地文件",
                    onPressed: () => ref
                        .read(localFileItemsProvider.notifier)
                        .buildRootFileListItems(),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
        );
      },
    );
  }

  Widget buildBoardHeader(
    BuildContext context,
    WidgetRef ref,
    String? selectedPortName,
  ) {
    final selectionMode = ref.watch(boardFileSelectionModeProvider);
    final controller = ref.watch(boardFileTreeViewControllerProvider);
    final hasLocalWorkspace = ref.watch(fileProvider)?.path != null;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final selectedCount = controller.selectedNodeIds.length;
        return PaneHeader(
          title: selectionMode ? "已选择 $selectedCount 项" : "设备文件",
          subtitle: "已连接：$selectedPortName",
          leadingIcon: selectionMode
              ? Icons.checklist
              : Icons.developer_board_outlined,
          compact: true,
          actions: selectionMode
              ? [
                  IconButton(
                    tooltip: "下载选中项",
                    onPressed: hasLocalWorkspace && selectedCount > 0
                        ? () => _downloadSelectedBoardItems(context, ref)
                        : null,
                    icon: const Icon(Icons.download_outlined),
                  ),
                  IconButton(
                    tooltip: "删除选中项",
                    onPressed: selectedCount > 0
                        ? () async {
                            if (await confirmDelete(
                              context,
                              "$selectedCount 个项目",
                            )) {
                              try {
                                await ref
                                    .read(boardProvider.notifier)
                                    .deleteSelectedBoardItems(context);
                              } on DeviceNotReadyException catch (_) {
                                if (!context.mounted) return;
                                final sendCtrlC =
                                    await showDeviceNotReadyDialog(
                                      context,
                                      operation: "删除设备文件",
                                    );
                                if (sendCtrlC) {
                                  ref
                                      .read(getUsbSerialProvider().notifier)
                                      .sendCommand("\x03");
                                }
                              }
                            }
                          }
                        : null,
                    icon: const Icon(Icons.delete_outline),
                  ),
                  IconButton(
                    tooltip: "清除选择",
                    onPressed: selectedCount > 0
                        ? () => controller.deselectAll()
                        : null,
                    icon: const Icon(Icons.deselect),
                  ),
                  IconButton(
                    tooltip: "退出选择模式",
                    onPressed: () {
                      controller.deselectAll();
                      ref.read(boardFileSelectionModeProvider.notifier).state =
                          false;
                    },
                    icon: const Icon(Icons.close),
                  ),
                ]
              : [
                  IconButton(
                    tooltip: "选择项目",
                    onPressed: () {
                      ref.read(boardFileSelectionModeProvider.notifier).state =
                          true;
                    },
                    icon: const Icon(Icons.checklist),
                  ),
                  IconButton(
                    tooltip: "刷新设备文件",
                    onPressed: () async {
                      try {
                        await ref
                            .watch(boardFileItemsProvider.notifier)
                            .buildRootFileListItems();
                      } on DeviceNotReadyException catch (_) {
                        if (!context.mounted) return;
                        final sendCtrlC = await showDeviceNotReadyDialog(
                          context,
                          operation: "刷新设备文件",
                        );
                        if (sendCtrlC) {
                          ref
                              .read(getUsbSerialProvider().notifier)
                              .sendCommand("\x03");
                        }
                      }
                    },
                    icon: const Icon(Icons.refresh),
                  ),
                ],
        );
      },
    );
  }

  Widget buildLocalFiles(BuildContext context, WidgetRef ref) {
    if (ref.watch(fileProvider) != null) {
      final localWorkspace = ref.watch(fileProvider)!;
      final selectionMode = ref.watch(localFileSelectionModeProvider);
      return Column(
        children: [
          buildLocalHeader(context, ref, localWorkspace),
          // buildLocalActionStrip(context, ref),
          Expanded(
            child: SuperTreeView<FileSystemItem>(
              logic: TreeViewConfig(
                expansionTrigger: selectionMode
                    ? ExpansionTrigger.iconTap
                    : ExpansionTrigger.tap,
                ignorePrimaryPointerDown: (node, event) => _isDragHandlePointer(
                  _FileDragSource.local,
                  node.id,
                  event.position,
                ),
                rowWrapperBuilder: (context, node, child) =>
                    PyriteContextMenuWidget(
                      menuProvider: (_) => _buildLocalNodeMenu(
                        context,
                        ref,
                        localWorkspace,
                        node,
                      ),
                      child: _wrapFileDragSource(
                        ref: ref,
                        node: node,
                        source: _FileDragSource.local,
                        child: child,
                      ),
                    ),
                dragAndDrop: TreeDragAndDropConfig<FileSystemItem>(
                  onMoveNodes: (draggedNodes, targetNode, position) =>
                      _moveLocalNodesToFolder(
                        context,
                        ref,
                        draggedNodes,
                        targetNode,
                        position,
                      ),
                ),
                enableDragAndDrop: ref.watch(localEnableDragAndDrop),
                selectionMode: selectionMode
                    ? SelectionMode.none
                    : SelectionMode.multiple,
                onNodeDoubleTap: selectionMode
                    ? null
                    : (id) =>
                          ref.read(fileProvider.notifier).openFile(context, id),
                namingStrategy: TreeNamingStrategy.always,
              ),
              style: SuperTreeThemes.material().treeStyle.copyWith(
                selectedColor: Theme.of(context).colorScheme.secondaryContainer,
              ),
              controller: ref.watch(localFileTreeViewControllerProvider),
              scrollController: ref.watch(localFileScrollControllerProvider),
              prefixBuilder:
                  (BuildContext context, TreeNode<FileSystemItem> node) {
                    return SuperTreeThemes.material().fileSystemIconProvider!
                        .getIcon(node);
                  },
              contentBuilder:
                  (
                    BuildContext context,
                    TreeNode<FileSystemItem> node,
                    Widget? renameField,
                  ) {
                    if (renameField != null) {
                      return renameField;
                    }
                    final isGitIgnored = local.isGitIgnoredItem(node.data);
                    final localController = ref.watch(
                      localFileTreeViewControllerProvider,
                    );
                    final isSelected = localController.selectedNodeIds.contains(
                      node.id,
                    );
                    final label = Text(
                      node.data.name,
                      style: isGitIgnored
                          ? TextStyle(
                              color: Theme.of(context).colorScheme.outline,
                            )
                          : null,
                    );
                    final row = Row(
                      children: [
                        if (selectionMode)
                          SizedBox.square(
                            dimension: 28,
                            child: IgnorePointer(
                              child: Checkbox(
                                value: isSelected,
                                onChanged: (_) {},
                              ),
                            ),
                          ),
                        _buildDragHandle(_FileDragSource.local, node.id),
                        const SizedBox(width: 4),
                        Expanded(child: label),
                      ],
                    );
                    return selectionMode
                        ? GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () =>
                                localController.toggleSelection(node.id),
                            child: row,
                          )
                        : row;
                  },
            ),
          ),
        ],
      );
    } else {
      return WorkspaceEmptyState(
        icon: Icons.folder_outlined,
        title: "打开一个本地项目",
        message: "选择保存 MicroPython 脚本的文件夹，然后就可以在本地和设备之间同步文件。",
        actionLabel: "打开文件夹",
        onAction: () => ref.read(localFileItemsProvider.notifier).openFolder(),
      );
    }
  }

  Widget buildLocalActionStrip(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isConnected = ref.watch(getUsbSerialProvider()).isConnected;
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            FilledButton.tonalIcon(
              onPressed: isConnected
                  ? () async {
                      try {
                        await ref
                            .read(fileProvider.notifier)
                            .uploadSelectedLocalFileItem(context);
                      } on DeviceNotReadyException catch (_) {
                        if (!context.mounted) return;
                        final sendCtrlC = await showDeviceNotReadyDialog(
                          context,
                          operation: "上传文件到设备",
                        );
                        if (sendCtrlC) {
                          ref
                              .read(getUsbSerialProvider().notifier)
                              .sendCommand("\x03");
                        }
                      }
                    }
                  : null,
              icon: const Icon(Icons.upload_outlined, size: 18),
              label: Text("上传选中项"),
            ),
            const SizedBox(width: 6),
            TextButton.icon(
              onPressed: () => ref
                  .read(localFileItemsProvider.notifier)
                  .buildRootFileListItems(),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text("刷新"),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildBoardFiles(BuildContext context, WidgetRef ref) {
    if (ref.watch(getUsbSerialProvider()).isConnected &&
        ref.watch(boardFileItemsProvider).isNotEmpty) {
      final usb = ref.watch(getUsbSerialProvider());
      final selectionMode = ref.watch(boardFileSelectionModeProvider);
      return Column(
        children: [
          buildBoardHeader(context, ref, usb.selectedPortName),
          // buildBoardActionStrip(context, ref),
          Expanded(
            child: SuperTreeView<FileSystemItem>(
              logic: TreeViewConfig(
                expansionTrigger: selectionMode
                    ? ExpansionTrigger.iconTap
                    : ExpansionTrigger.tap,
                ignorePrimaryPointerDown: (node, event) => _isDragHandlePointer(
                  _FileDragSource.board,
                  node.id,
                  event.position,
                ),
                rowWrapperBuilder: (context, node, child) =>
                    PyriteContextMenuWidget(
                      menuProvider: (_) =>
                          _buildBoardNodeMenu(context, ref, node),
                      child: _wrapFileDragSource(
                        ref: ref,
                        node: node,
                        source: _FileDragSource.board,
                        child: child,
                      ),
                    ),
                dragAndDrop: TreeDragAndDropConfig<FileSystemItem>(
                  onMoveNodes: (draggedNodes, targetNode, position) =>
                      _moveBoardNodesToFolder(
                        context,
                        ref,
                        draggedNodes,
                        targetNode,
                        position,
                      ),
                ),
                enableDragAndDrop: ref.watch(boardEnableDragAndDrop),
                selectionMode: selectionMode
                    ? SelectionMode.none
                    : SelectionMode.multiple,
                onNodeDoubleTap: selectionMode
                    ? null
                    : (id) => ref
                          .read(boardProvider.notifier)
                          .openFile(context, id),
                namingStrategy: TreeNamingStrategy.always,
              ),
              style: SuperTreeThemes.material().treeStyle.copyWith(
                selectedColor: Theme.of(context).colorScheme.secondaryContainer,
              ),
              controller: ref.watch(boardFileTreeViewControllerProvider),
              scrollController: ref.watch(boardFileScrollControllerProvider),
              prefixBuilder:
                  (BuildContext context, TreeNode<FileSystemItem> node) {
                    return SuperTreeThemes.material().fileSystemIconProvider!
                        .getIcon(node);
                  },
              contentBuilder:
                  (
                    BuildContext context,
                    TreeNode<FileSystemItem> node,
                    Widget? renameField,
                  ) {
                    if (renameField != null) {
                      return renameField;
                    }
                    final boardController = ref.watch(
                      boardFileTreeViewControllerProvider,
                    );
                    final isSelected = boardController.selectedNodeIds.contains(
                      node.id,
                    );
                    final label = Text(node.data.name);
                    final row = Row(
                      children: [
                        if (selectionMode)
                          SizedBox.square(
                            dimension: 28,
                            child: IgnorePointer(
                              child: Checkbox(
                                value: isSelected,
                                onChanged: (_) {},
                              ),
                            ),
                          ),
                        _buildDragHandle(_FileDragSource.board, node.id),
                        const SizedBox(width: 4),
                        Expanded(child: label),
                      ],
                    );
                    return selectionMode
                        ? GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () =>
                                boardController.toggleSelection(node.id),
                            child: row,
                          )
                        : row;
                  },
            ),
          ),
        ],
      );
    } else if (ref.watch(getUsbSerialProvider()).isConnected) {
      return WorkspaceEmptyState(
        icon: Icons.developer_board_outlined,
        title: "点击刷新按钮以获取设备文件列表",
        message: "这里会显示板端文件，可以和本地项目互相同步。",
        actionLabel: "刷新",
        onAction: () =>
            ref.watch(boardFileItemsProvider.notifier).buildRootFileListItems(),
      );
    } else {
      return WorkspaceEmptyState(
        icon: Icons.developer_board_outlined,
        title: "连接 MicroPython 设备",
        message: "连接后这里会显示板端文件，可以和本地项目互相同步。",
        actionLabel: "打开设备管理",
        onAction: () => context.go("/tools"),
      );
    }
  }
}
