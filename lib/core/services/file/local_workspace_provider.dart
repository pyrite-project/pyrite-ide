import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LocalWorkspaceNotifier extends StateNotifier<Directory?> {
  final Ref ref;
  LocalWorkspaceNotifier(this.ref) : super(null);

  Future<Directory?> getDirectory() async {
    final String? path = await getDirectoryPath();
    final Directory? dir;
    if (path != null) {
      dir = Directory(path);
      state = dir;
      return dir;
    } else {
      return null;
    }
  }

  Future<Stream<FileSystemEntity>> getFilesList({String? path}) async {
    Stream<FileSystemEntity> datas;
    if (state != null && (path == null || path == state!.path)) {
      datas = state!.list();
    } else {
      if (path != null) {
        datas = Directory(path).list();
      } else {
        datas = Stream.empty();
      }
    }
    return datas;
  }
}

final StateNotifierProvider<LocalWorkspaceNotifier, Directory?>
localWorkspaceProvider = StateNotifierProvider(
  (ref) => LocalWorkspaceNotifier(ref),
);
