import 'package:flutter/material.dart';
import 'package:pyrite_ide/shared/studio_text.dart';

class Welcome extends StatelessWidget {
  const Welcome({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image.asset(
          "assets/icons/app_icon.png",
          width: 80,
          height: 80,
          color: Theme.of(context).colorScheme.secondary,
        ),
        SizedBox(height: 30),
        TextBodyMedium(
          "欢迎来到 PyriteIDE",
          color: Theme.of(context).colorScheme.secondary,
        ),
        TextBodyMedium(
          "若已打开项目，请前往“文件”打开一个项目中的文件",
          color: Theme.of(context).colorScheme.secondary,
        ),
      ],
    );
  }
}
