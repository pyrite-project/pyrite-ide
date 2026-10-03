import 'package:pyrite_ide/core/platform/web/web_fs_backend.dart';
import 'package:pyrite_ide/core/platform/pyrite_io_web.dart';

/// Root of the OPFS-backed app-support mount on the web.
const String kWebAppSupportPath = '/.pyrite_ide';

/// OPFS-backed temporary directory on the web.
const String kWebTempPath = '/.pyrite_ide/tmp';

Future<Directory> getApplicationSupportDirectory() async {
  await WebFs.instance.ensureAppSupportMounted();
  return Directory(kWebAppSupportPath);
}

Future<Directory> getTemporaryDirectory() async {
  final temp = Directory(kWebTempPath);
  if (!await temp.exists()) {
    await temp.create(recursive: true);
  }
  return temp;
}

Future<Directory> getApplicationCacheDirectory() async {
  final cache = Directory('$kWebAppSupportPath/cache');
  if (!await cache.exists()) {
    await cache.create(recursive: true);
  }
  return cache;
}
