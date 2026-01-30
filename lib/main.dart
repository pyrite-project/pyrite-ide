import 'package:flutter/material.dart';
import 'package:pyrite_ide/app/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/features/window.dart';

// PyriteIDE: Hello World.
void main() {
  UseWindow().init();
  runApp(const ProviderScope(child: PyriteIDE()));
}
