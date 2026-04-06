import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_manager_provider.dart';

Future<void> install(Plugin plugin, String packagePath) async {
  Directory root = await getApplicationDocumentsDirectory();
  Directory target = Directory(path.join(root.path, plugin.id));

  final InputFileStream stream = InputFileStream(packagePath);
  final Archive archive = ZipDecoder().decodeStream(stream);

  await extractArchiveToDisk(archive, target.path);
}
