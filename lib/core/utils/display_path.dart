/// Trims a path down to what a one-line message should show.
///
/// Snackbars, progress rows and confirmations already say what happened
/// ("已上传到设备"), so a leading `E:\projects\alpha\` only pushes the part the
/// user cares about out of view. These surfaces therefore show the last path
/// segment and nothing more.
///
/// Surfaces that exist *to* show a path — settings, the plugin manager, "在文件
/// 资源管理器中打开", tab tooltips, error details copied out for a bug report —
/// keep the full string and must not call this.
String displayPathName(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return trimmed;

  final segments = <String>[];
  for (final segment in trimmed.replaceAll('\\', '/').split('/')) {
    if (segment.isNotEmpty) segments.add(segment);
  }
  if (segments.isEmpty) return trimmed;

  final last = segments.last;
  // A drive root normalizes to its bare `C:`; the raw input reads better.
  return last.endsWith(':') ? trimmed : last;
}
