import 'package:flutter/material.dart';
import 'package:pyrite_ide/shared/studio_text.dart';

class ProjectCard extends StatelessWidget {
  const ProjectCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text("Title"),
        subtitle: Text("com.test\nE:\\\\Can1425"),
        trailing: Icon(Icons.more_vert),
      ),
    );
  }
}
