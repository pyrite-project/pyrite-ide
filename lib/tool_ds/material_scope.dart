import 'package:flutter/material.dart';

class MaterialScope extends StatelessWidget {
  const MaterialScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(child: child);
  }
}

