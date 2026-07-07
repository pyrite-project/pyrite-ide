import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/serial/device_executor.dart';

const _ensureFilesystemMountedScript = r'''
import os

def _fs_ready():
  try:
    s = os.statvfs('/')
    return bool(s[0] and s[2])
  except Exception:
    return False

def _mount_flashbdev():
  try:
    import flashbdev
    b = flashbdev.bdev
    if isinstance(b, (list, tuple)):
      b = b[0]
  except Exception:
    return

  candidates = [b]
  try:
    candidates.append(os.VfsLfs2(b))
  except Exception:
    pass

  for candidate in candidates:
    try:
      os.mount(candidate, '/')
      return
    except Exception:
      pass

if not _fs_ready():
  _mount_flashbdev()
print('FS_READY' if _fs_ready() else 'FS_NOT_READY')
''';

Future<void> ensureBoardFilesystemMountedOnce(Ref ref) async {
  try {
    final output = await runPythonOnDevice(
      ref,
      _ensureFilesystemMountedScript,
      timeout: const Duration(seconds: 5),
    );
    if (output.contains('FS_NOT_READY')) {
      debugPrint('Board filesystem is not ready after mount attempt.');
    }
  } catch (error) {
    debugPrint('Board filesystem mount check failed: $error');
  }
}
