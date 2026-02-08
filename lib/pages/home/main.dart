import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/app/routes.dart';
import 'package:pyrite_ide/core/services/android_env_deployer/core.dart';
import 'package:pyrite_ide/core/services/pylsp/main.dart';
import 'package:pyrite_ide/pages/home/project_card.dart';
import 'package:pyrite_ide/shared/studio_text.dart';
import 'package:responsive_framework/responsive_framework.dart';

class Home extends ConsumerWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: LayoutBuilder(
          builder: (context, constraints) {
            if (ResponsiveBreakpoints.of(context).isDesktop) {
              return Text("快捷控制");
            } else {
              return AppBarTextLogo();
            }
          },
        ),
      ),
      body: Padding(
        padding: EdgeInsetsGeometry.only(left: 15, right: 15),
        child: ListView.builder(
          itemCount: 1,
          itemBuilder: (context, index) {
            return ProjectCard();
          },
        ),
      ),
    );
  }
}
