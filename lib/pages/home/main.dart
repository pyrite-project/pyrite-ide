import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/app/routes.dart';
import 'package:pyrite_ide/pages/home/project_card.dart';
import 'package:pyrite_ide/shared/studio_text.dart';

class Home extends StatelessWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: <Widget>[
          SliverAppBar.large(
            title: Row(
              children: [
                RichText(
                  text: TextSpan(
                    text: "Pyrite",
                    style: Theme.of(context).textTheme.headlineMedium!.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    children: [
                      TextSpan(
                        text: "IDE",
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 10),
                Badge(label: Text("debug")),
                SizedBox(width: 10),
                Badge(label: Text("developing")),
              ],
            ),
          ),
          SliverPadding(
            padding: EdgeInsetsGeometry.only(left: 15, right: 15),
            sliver: SliverList.builder(
              itemCount: 10,
              itemBuilder: (context, index) {
                return ProjectCard();
              },
            ),
          ),
        ],
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          context.go(new_project);
        },
        icon: Icon(Icons.add),
        label: UseText("新建项目"),
      ),
    );
  }
}
