import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:palette_generator_master/palette_generator_master.dart';
import 'package:pyrite_ide/shared/studio_text.dart';
import 'package:vertical_card_pager/vertical_card_pager.dart';

class About extends StatelessWidget {
  const About({super.key});

  @override
  Widget build(BuildContext context) {
    final List<String> titles = ["", "现代化", "强大", "跨平台", "关于 Pyrite Project"];

    final List<Widget> images = [
      Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 15.0),
            child: Center(
              child: Hero(
                tag: 'app_icon',
                child: Image.asset(
                  width: 200,
                  height: 200,
                  "assets/icons/app_icon.png",
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          Hero(tag: "app_name", child: TextDisplayMedium("PyriteIDE")),
        ],
      ),
      Hero(
        tag: "feature_modern_image",
        child: ClipRRect(
          borderRadius: BorderRadiusGeometry.circular(10),
          child: Image.asset("assets/about/1.webp", fit: BoxFit.cover),
        ),
      ),

      Hero(
        tag: "feature_powerful_image",
        child: ClipRRect(
          borderRadius: BorderRadiusGeometry.circular(10),
          child: Image.asset("assets/about/2.webp", fit: BoxFit.cover),
        ),
      ),
      Hero(
        tag: "feature_cross_platform_image",
        child: ClipRRect(
          borderRadius: BorderRadiusGeometry.circular(10),
          child: Image.asset("assets/about/3.webp", fit: BoxFit.cover),
        ),
      ),
      Hero(
        tag: "about_project_image",
        child: ClipRRect(
          borderRadius: BorderRadiusGeometry.circular(10),
          child: Image.asset("assets/about/4.webp", fit: BoxFit.cover),
        ),
      ),
    ];

    final details = [
      "app_details",
      "feature/modern",
      "feature/powerful",
      "feature/cross_platform",
      "project",
    ];

    final body = Column(
      children: <Widget>[
        Expanded(
          child: Container(
            child: VerticalCardPager(
              titles: titles, // required
              images: images, // required
              textStyle: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ), // optional
              onPageChanged: (page) {
                // optional
              },
              onSelectedItem: (index) {
                context.go("/settings/about/${details[index]}");
              },
              initialPage: 0, // optional
              align: ALIGN.CENTER, // optional
              physics: ClampingScrollPhysics(), // optional
            ),
          ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const UseText("关于")),
      body: body,
    );
  }
}

class AppDetails extends StatelessWidget {
  const AppDetails({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("应用与设备信息")),
      body: Column(
        children: [
          SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Hero(
                tag: 'app_icon',
                child: Image.asset(
                  width: 80,
                  height: 80,
                  "assets/icons/app_icon.png",
                  fit: BoxFit.cover,
                ),
              ),
              SizedBox(width: 20),
              Hero(tag: "app_name", child: TextDisplayMedium("PyriteIDE")),
            ],
          ),
        ],
      ),
    );
  }
}

class FeatureModern extends StatelessWidget {
  const FeatureModern({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Hero(
              tag: "feature_modern_image",
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  image: DecorationImage(
                    image: AssetImage("assets/about/1.webp"),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            SizedBox(width: 10),
            Text("现代化的 PyriteIDE"),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(children: [
            
          ],
        ),
      ),
    );
  }
}

class FeaturePowerful extends StatelessWidget {
  const FeaturePowerful({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Hero(
              tag: "feature_powerful_image",
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  image: DecorationImage(
                    image: AssetImage("assets/about/2.webp"),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            SizedBox(width: 10),
            Text("强大的 PyriteIDE"),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(children: [
            
          ],
        ),
      ),
    );
  }
}

class FeatureCrossPlatform extends StatelessWidget {
  const FeatureCrossPlatform({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Hero(
              tag: "feature_cross_platform_image",
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  image: DecorationImage(
                    image: AssetImage("assets/about/3.webp"),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            SizedBox(width: 10),
            Text("跨平台的 PyriteIDE"),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(children: [
            
          ],
        ),
      ),
    );
  }
}

class AboutProject extends StatelessWidget {
  const AboutProject({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Hero(
              tag: "about_project_image",
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  image: DecorationImage(
                    image: AssetImage("assets/about/4.webp"),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            SizedBox(width: 10),
            Text("关于 Pyrite Project"),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(children: [
            
          ],
        ),
      ),
    );
  }
}
