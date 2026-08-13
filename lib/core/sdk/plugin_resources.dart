import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_package_paths.dart';

const pluginResourceScheme = 'plugin-resource';

String? pluginResourcePath(String source) {
  final uri = Uri.tryParse(source);
  if (uri == null ||
      uri.scheme != pluginResourceScheme ||
      !uri.hasAuthority ||
      uri.host.isNotEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      uri.query.isNotEmpty ||
      uri.fragment.isNotEmpty) {
    return null;
  }
  final value = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
  return isValidPluginAssetPath(value) ? value : null;
}

bool isValidPluginAssetPath(String value) {
  final normalized = value.replaceAll('\\', '/');
  return value.isNotEmpty &&
      value == normalized &&
      normalized.startsWith('assets/') &&
      !normalized.startsWith('/') &&
      !normalized.contains(RegExp(r'(^|/)\.\.(/|$)')) &&
      !normalized.contains('\u0000') &&
      !RegExp(r'^[A-Za-z]:').hasMatch(normalized);
}

File? resolvePluginAssetFile(String pluginRoot, String assetPath) {
  if (!isValidPluginAssetPath(assetPath)) return null;
  final root = path.normalize(path.absolute(pluginRoot));
  final candidate = path.normalize(path.absolute(path.join(root, assetPath)));
  final relative = path.relative(candidate, from: root);
  if (relative == '..' ||
      relative.startsWith('..${path.separator}') ||
      path.isAbsolute(relative) ||
      FileSystemEntity.typeSync(candidate, followLinks: false) !=
          FileSystemEntityType.file) {
    return null;
  }
  return File(candidate);
}

Future<File?> resolveInstalledPluginAsset(
  String pluginId,
  String assetPath,
) async {
  if (pluginId.isEmpty || path.basename(pluginId) != pluginId) return null;
  final support = await getApplicationSupportDirectory();
  final pluginDirectory = await resolvePluginPackageDirectory(
    support,
    pluginId,
  );
  return resolvePluginAssetFile(pluginDirectory.path, assetPath);
}

class PluginAssetImage extends StatefulWidget {
  const PluginAssetImage({
    super.key,
    required this.pluginId,
    required this.assetPath,
    this.revision,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.color,
    this.monochrome = false,
    this.fallback,
  });

  final String pluginId;
  final String assetPath;
  final Object? revision;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Color? color;
  final bool monochrome;
  final Widget? fallback;

  @override
  State<PluginAssetImage> createState() => _PluginAssetImageState();
}

class _PluginAssetImageState extends State<PluginAssetImage> {
  late Future<File?> _file = _resolve();

  Future<File?> _resolve() =>
      resolveInstalledPluginAsset(widget.pluginId, widget.assetPath);

  @override
  void didUpdateWidget(covariant PluginAssetImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pluginId != widget.pluginId ||
        oldWidget.assetPath != widget.assetPath ||
        oldWidget.revision != widget.revision) {
      _file = _resolve();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<File?>(
    future: _file,
    builder: (context, snapshot) {
      final file = snapshot.data;
      if (file == null) {
        return widget.fallback ?? const SizedBox.shrink();
      }
      return Image.file(
        file,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        color:
            widget.color ??
            (widget.monochrome ? IconTheme.of(context).color : null),
        colorBlendMode: widget.color == null && !widget.monochrome
            ? null
            : BlendMode.srcIn,
        errorBuilder: (context, error, stackTrace) =>
            widget.fallback ?? const SizedBox.shrink(),
      );
    },
  );
}
