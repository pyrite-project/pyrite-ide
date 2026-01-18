import 'package:flutter/material.dart';
import 'package:pyrite_ide/shared/studio_text.dart';

class About extends StatelessWidget {
  const About({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: UseText("关于")));
  }
}
