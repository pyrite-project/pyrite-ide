import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pyrite_ide/app/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/periodic_task/main.dart';
import 'package:pyrite_ide/features/window.dart';
import 'package:serious_python/serious_python.dart';

// PyriteIDE: Hello World.
void main() {
  container = ProviderContainer();
  UseWindow().init();

  SeriousPython.run("assets/python_runtime_boot.zip", appFileName: "boot.py");
  // container.read(lspClientProvider);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: PeriodicTaskLifecycleObserver(child: const PyriteIDE()),
    ),
  );
}
