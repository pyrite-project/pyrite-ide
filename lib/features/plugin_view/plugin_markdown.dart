import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown_widget/markdown_widget.dart' as md;
import 'package:pyrite_ide/core/sdk/plugin_resources.dart';

/// Renders a plugin's markdown source with the same configuration the IDE's own
/// markdown views use, so plugin docs and IDE docs look identical.
///
/// Non-scrolling by design: the block composes inside whatever layout the plugin
/// built (a Column, a SplitView pane, a Flex child), and the surrounding scroll
/// view — if any — belongs to the plugin's tree, not to us.
class PluginMarkdown extends StatefulWidget {
  const PluginMarkdown({
    super.key,
    required this.data,
    this.selectable = true,
    this.onTapLink,
    this.pluginRootPath,
  });

  final String data;
  final bool selectable;

  /// Called with the raw href when the user taps a link. Nothing is opened by
  /// the host: navigation is the plugin's decision, since a link may address
  /// plugin-internal content rather than the web.
  final ValueChanged<String>? onTapLink;
  final String? pluginRootPath;

  @override
  State<PluginMarkdown> createState() => PluginMarkdownState();
}

class PluginMarkdownState extends State<PluginMarkdown> {
  final md.TocController tocController = md.TocController();

  Map<String, int> get _anchors {
    final result = <String, int>{};
    var heading = 0;
    for (final line in widget.data.split('\n')) {
      final match = RegExp(r'^#{1,6}\s+(.+?)\s*#*$').firstMatch(line.trim());
      if (match == null) continue;
      final title = match.group(1)!.trim();
      final slug = title
          .toLowerCase()
          .replaceAll(RegExp(r'[^\w\s-]'), '')
          .replaceAll(RegExp(r'[\s_]+'), '-');
      result[slug] = heading++;
    }
    return result;
  }

  bool scrollToAnchor(String anchor) {
    final ordinal = _anchors[anchor.replaceFirst('#', '')];
    final toc = ordinal == null || ordinal >= tocController.tocList.length
        ? null
        : tocController.tocList[ordinal];
    if (toc == null) return false;
    tocController.jumpToIndex(toc.widgetIndex);
    return true;
  }

  int? anchorOffset(String anchor) {
    final ordinal = _anchors[anchor.replaceFirst('#', '')];
    if (ordinal == null || ordinal >= tocController.tocList.length) return null;
    return tocController.tocList[ordinal].widgetIndex;
  }

  int selectAll() => widget.data.length;
  Future<void> copySelection() =>
      Clipboard.setData(ClipboardData(text: widget.data));

  @override
  Widget build(BuildContext context) {
    return md.MarkdownWidget(
      data: widget.data,
      selectable: widget.selectable,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      tocController: tocController,
      config: markdownConfigFor(
        context,
        onTapLink: widget.onTapLink,
        pluginRootPath: widget.pluginRootPath,
      ),
    );
  }

  @override
  void dispose() {
    tocController.dispose();
    super.dispose();
  }
}

/// Builds the markdown config for the theme currently in scope.
///
/// The package ships light defaults, so dark mode has to be selected explicitly;
/// the code-block theme comes from the package's own dark palette rather than a
/// hand-rolled one to keep highlighting legible.
md.MarkdownConfig markdownConfigFor(
  BuildContext context, {
  ValueChanged<String>? onTapLink,
  String? pluginRootPath,
}) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final dark = theme.brightness == Brightness.dark;
  final base = dark
      ? md.MarkdownConfig.darkConfig
      : md.MarkdownConfig.defaultConfig;
  final body = theme.textTheme.bodyMedium ?? const TextStyle(fontSize: 14);

  return base.copy(
    configs: [
      md.PConfig(textStyle: body),
      md.LinkConfig(
        style: body.copyWith(
          color: scheme.primary,
          decoration: TextDecoration.underline,
          decorationColor: scheme.primary,
        ),
        onTap: onTapLink,
      ),
      md.ImgConfig(
        builder: (url, attributes) {
          final assetPath = pluginResourcePath(url);
          final file = assetPath == null || pluginRootPath == null
              ? null
              : resolvePluginAssetFile(pluginRootPath, assetPath);
          if (file == null) {
            return const Icon(Icons.broken_image_outlined);
          }
          return Image.file(
            file,
            width: double.tryParse(attributes['width'] ?? ''),
            height: double.tryParse(attributes['height'] ?? ''),
            fit: BoxFit.contain,
          );
        },
      ),
      md.CodeConfig(
        style: base.code.style.copyWith(
          fontFamily: 'monospace',
          backgroundColor: scheme.surfaceContainerHighest,
          color: scheme.onSurface,
        ),
      ),
    ],
  );
}
