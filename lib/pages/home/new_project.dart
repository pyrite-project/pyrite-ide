import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/app/routes.dart';
import 'package:pyrite_ide/shared/studio_text.dart';

class NewProject extends StatelessWidget {
  const NewProject({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("新建项目")),
      floatingActionButton: FloatingActionButton(
        child: Icon(Icons.navigate_next),
        onPressed: () {
          context.go(file);
        },
      ),
      body: Padding(
        padding: EdgeInsetsGeometry.all(15),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.only(
                  top: 20,
                  bottom: 20,
                  left: 15,
                  right: 15,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextTitleMedium("基本信息"),
                    SizedBox(height: 20),
                    TextField(
                      decoration: InputDecoration(
                        icon: Icon(Icons.class_outlined),
                        border: OutlineInputBorder(),
                        labelText: "项目名称",
                      ),
                    ),
                    SizedBox(height: 15),
                    TextField(
                      decoration: InputDecoration(
                        icon: Icon(Icons.perm_identity_outlined),
                        border: OutlineInputBorder(),
                        labelText: "标识符",
                      ),
                    ),
                    SizedBox(height: 15),
                    TextField(
                      decoration: InputDecoration(
                        icon: Icon(Icons.folder_outlined),
                        border: OutlineInputBorder(),
                        labelText: "本地路径",
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
