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
    this.encoding,
    this.byteOrderMark = false,
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

  /// Character set the file's bytes were decoded with when the tab was opened,
  /// or null when the editor writes plain UTF-8.
  ///
  /// Saving has to reproduce this: writing a GBK buffer as UTF-8 silently
  /// transcodes the file, and UTF-16 content loses its byte order mark, so
  /// every non-ASCII character round-trips wrong.
  final String? encoding;

  /// Whether the file on disk started with a byte order mark for [encoding].
  final bool byteOrderMark;

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
