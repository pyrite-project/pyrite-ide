import 'package:flutter/material.dart';
import 'package:pyrite_ide/app/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// PyriteIDE: Hello World.
void main() {
  runApp(const ProviderScope(child: PyriteIDE()));
}
