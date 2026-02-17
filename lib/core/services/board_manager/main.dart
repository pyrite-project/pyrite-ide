import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'android.dart' as android;
import 'desktop.dart' as desktop;

StateProvider<bool> connectState = StateProvider<bool>((ref) => false);

void sendCommand(WidgetRef ref, String command) {
  if (Platform.isAndroid) {
    android.sendCommand(ref, command);
  } else {
    desktop.sendCommand(ref, command);
  }
}
