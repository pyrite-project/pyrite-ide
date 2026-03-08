import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pyrite_ide/app/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/features/window.dart';
import 'package:serious_python/serious_python.dart';

String? getPythonPath() {
  if (Platform.isAndroid) return "assets/android/python.zip";
  if (Platform.isWindows) return "assets/windows/python.zip";
  if (Platform.isLinux) return "assets/linux/python.zip";
  if (Platform.isMacOS) return "assets/macos/python.zip";
  return null;
}

// PyriteIDE: Hello World.
void main() {
  container = ProviderContainer();
  UseWindow().init();

  SeriousPython.run(getPythonPath()!);
  // container.read(lspClientProvider);

  runApp(
    UncontrolledProviderScope(container: container, child: const PyriteIDE()),
  );
}
