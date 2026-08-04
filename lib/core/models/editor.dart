import 'dart:io';
import 'package:code_forge/code_forge.dart';

class TabDataValue {
  TabDataValue({
    required this.type,
    required this.filePath,
    this.file,
    this.editorController,
    this.undoRedoController,
    this.isBoardFile,
    this.boardFilePath,
    this.isSaved = true,
    this.pluginId,
    this.viewId,
    this.viewInstanceId,
    this.renderer,
  });
  final String type;

  /// Identifies the tab. For plugin views this is a synthetic
  /// `plugin://<pluginId>/<viewId>#<instanceId>` URI so the many places that
  /// look tabs up by path keep working without a special case.
  final String filePath;
  final File? file;
  final CodeForgeController? editorController;
  final UndoRedoController? undoRedoController;
  final bool? isBoardFile;
  final String? boardFilePath;
  bool isSaved;

  /// Set only when [type] is [pluginViewType]; together they address the one
  /// view instance this tab hosts.
  final String? pluginId;
  final String? viewId;
  final String? viewInstanceId;

  /// Renderer token from the view contribution, e.g. `native.outline`.
  final String? renderer;

  /// Discriminator for tabs whose content is a plugin view surface.
  static const String pluginViewType = 'plugin_view';

  bool get isPluginView => type == pluginViewType;

  static String pluginViewPath({
    required String pluginId,
    required String viewId,
    required String instanceId,
  }) => 'plugin://$pluginId/$viewId#$instanceId';
}
