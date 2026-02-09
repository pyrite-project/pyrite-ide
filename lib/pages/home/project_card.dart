import 'package:flutter/material.dart';

class ProjectCard extends StatelessWidget {
  const ProjectCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: ListTile(
        title: Text("Title"),
        subtitle: Text("com.test\nE:\\\\Can1425"),
        trailing: Icon(Icons.more_vert),
      ),
    );
  }
}
