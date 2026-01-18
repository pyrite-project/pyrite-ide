import 'package:flutter/material.dart';
import 'package:pyrite_ide/shared/studio_text.dart';

AppBar editAppBar() {
  return AppBar(
    toolbarHeight: 40,
    actions: [
      TextButton.icon(
        onPressed: () {},
        label: const UseText("下载到设备"),
        icon: const Icon(Icons.download),
      ),
      TextButton.icon(
        onPressed: () {},
        label: const UseText("运行"),
        icon: const Icon(Icons.arrow_downward),
      ),
      IconButton(onPressed: () {}, icon: const Icon(Icons.more_horiz)),
    ],
  );
}
