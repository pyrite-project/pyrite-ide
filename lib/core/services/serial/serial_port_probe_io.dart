import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

final DynamicLibrary? _kernel32 = Platform.isWindows
    ? DynamicLibrary.open('kernel32.dll')
    : null;

final _createFileW = _kernel32
    ?.lookupFunction<
      IntPtr Function(
        Pointer<Utf16>,
        Uint32,
        Uint32,
        Pointer,
        Uint32,
        Uint32,
        IntPtr,
      ),
      int Function(Pointer<Utf16>, int, int, Pointer, int, int, int)
    >('CreateFileW');

final _closeHandle = _kernel32
    ?.lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');

final _getLastError = _kernel32
    ?.lookupFunction<Uint32 Function(), int Function()>('GetLastError');

/// Best-effort probe that a COM port still exists by opening its device path
/// with zero access. Errors other than "not found" / "device not connected"
/// count as present to avoid spurious disconnects.
Future<bool> serialPortExistsOnSystem(String portName) async {
  final createFileW = _createFileW;
  final closeHandle = _closeHandle;
  final getLastError = _getLastError;
  if (createFileW == null || closeHandle == null || getLastError == null) {
    return true;
  }

  final wide = '\\.\$portName'.toNativeUtf16();
  try {
    final handle = createFileW(wide, 0, 3, nullptr, 3, 0x80, 0);
    if (handle == -1 || handle == 0) {
      final error = getLastError();
      // 2 = ERROR_FILE_NOT_FOUND, 1617 = ERROR_DEVICE_NOT_CONNECTED.
      return error != 2 && error != 1617;
    }
    closeHandle(handle);
    return true;
  } catch (_) {
    return true;
  } finally {
    malloc.free(wide);
  }
}
