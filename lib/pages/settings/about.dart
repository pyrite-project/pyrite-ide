import 'package:flutter/material.dart';
import 'package:pyrite_ide/core/constants/basic.dart';
import 'package:pyrite_ide/shared/md3_widgets.dart';
import 'package:pyrite_ide/shared/studio_text.dart';

class About extends StatelessWidget {
  const About({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final body = ListView(
      padding: EdgeInsets.all(12),
      children: [
        SettingsSection(
          title: "Pyrite IDE",
          description: "跨平台 MicroPython IDE",
          children: [
            ListTile(
              leading: Image.asset(
                "assets/icons/app_icon_appbar.png",
                color: Theme.of(context).colorScheme.primary,
                width: 36,
                height: 36,
              ),
              title: const TextLogo(),
              subtitle: const Text("一个更轻量、清晰的 MicroPython 工作台"),
              trailing: PillBadge(
                label: "早期阶段",
                containerColor: scheme.tertiaryContainer,
                foregroundColor: scheme.onTertiaryContainer,
              ),
            ),
            const SectionDivider(),
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: UseText(appName),
              subtitle: UseText("面向本地编辑、板端文件同步和 REPL 交互"),
            ),
          ],
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const UseText("关于")),
      body: body,
    );
  }
}
