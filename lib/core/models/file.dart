import 'package:flutter/widgets.dart';

class LocalFileTreeItem {
  final String name;
  final IconData icon;
  final bool isDicrectory;

  const LocalFileTreeItem({
    required this.name,
    required this.icon,
    this.isDicrectory = false,
  });
}

class BoardFileTreeItem {
  final String name;
  final IconData icon;
  final bool isDicrectory;

  const BoardFileTreeItem({
    required this.name,
    required this.icon,
    this.isDicrectory = false,
  });
}
