import 'package:flutter/material.dart';
import 'package:pyrite_ide/app/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/pylsp/main.dart';
import 'package:pyrite_ide/features/window.dart';

// PyriteIDE: Hello World.
void main() async {
  container = ProviderContainer();
  UseWindow().init();

  runApp(
    UncontrolledProviderScope(container: container, child: const PyriteIDE()),
  );
  container.read(lspClientProvider);
}
