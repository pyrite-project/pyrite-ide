import 'dart:io';
import 'package:code_forge/code_forge.dart';

class TabDataValue {
  TabDataValue({
    required this.type,
    required this.filePath,
    String? tabId,
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
  }) : tabId = tabId ?? filePath;
  final String type;

  /// Resource associated with the tab. For plugin views this is a synthetic
  /// URI kept for internal rendering and persistence; SDK callers use [tabId]
  /// instead.
  final String filePath;

  /// Stable host identity used by editor-tab SDK operations.
  final String tabId;
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
