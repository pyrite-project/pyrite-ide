import 'package:flutter/material.dart';
import 'package:pyrite_ide/core/sdk/material_icons.g.dart';

/// Resolves stable plugin icon tokens without exposing Flutter IconData values
/// across the process boundary.
IconData pluginIcon(String? reference) {
  const prefix = 'material:';
  if (reference == null || !reference.startsWith(prefix)) {
    return Icons.help_outline;
  }
  return materialIcon(reference.substring(prefix.length)) ?? Icons.help_outline;
}
