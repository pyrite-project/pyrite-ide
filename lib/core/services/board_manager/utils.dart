import 'dart:io';

import 'android_usb_serial_provider.dart';
import 'desktop_usb_serial_provider.dart';

dynamic getUsbSerialProvider() {
  if (Platform.isAndroid) {
    return androidUsbSerialProvider;
  } else {
    return desktopUsbSerialProvider;
  }
}
