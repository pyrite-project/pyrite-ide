import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

const _fileName = 'trusted_plugin_origins.json';

/// Registry sites the user has chosen to install plugins from.
///
/// Kept apart from the general settings pipeline: it is read only when an
/// install tab opens, and a corrupt file must never block the IDE from starting.
class TrustedPluginOrigins {
  TrustedPluginOrigins({Future<Directory> Function()? supportDirectory})
    : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _supportDirectory;

  Future<File> _file() async =>
      File(path.join((await _supportDirectory()).path, _fileName));

  Future<Set<String>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return {};
      final json = jsonDecode(await file.readAsString());
      return json is List ? json.whereType<String>().toSet() : {};
    } on FormatException {
      return {};
    } on FileSystemException catch (error) {
      debugPrint('TrustedPluginOrigins: cannot read $_fileName: $error');
      return {};
    }
  }

  Future<void> trust(String origin) async {
    final origins = await load()
      ..add(origin);
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(origins.toList()..sort()));
  }
}
