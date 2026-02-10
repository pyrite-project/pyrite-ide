import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pyrite_ide/app/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/pylsp/main.dart';
import 'package:pyrite_ide/features/window.dart';
import 'package:pyrite_ide/core/services/android_env_deployer/core.dart';
import 'package:pyrite_ide/src/rust/api/main.dart';
import 'package:pyrite_ide/src/rust/frb_generated.dart';

// PyriteIDE: Hello World.
void main() async {
  container = ProviderContainer();
  UseWindow().init();

  await RustLib.init();
  var t = await getPortList();
  print(t[0].portName);

  runApp(
    UncontrolledProviderScope(container: container, child: const PyriteIDE()),
  );
  container.read(lspClientProvider);
}

/*
import 'package:flutter/material.dart';
import 'package:pyrite_ide/src/rust/api/simple.dart';
import 'package:pyrite_ide/src/rust/frb_generated.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('flutter_rust_bridge quickstart')),
        body: Center(
          child: Text(
            'Action: Call Rust `greet("Tom")`\nResult: `${greet(name: "Tom")}`',
          ),
        ),
      ),
    );
  }
}

*/
