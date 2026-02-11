import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/tools/board_manager.dart';
import 'package:pyrite_ide/shared/studio_text.dart';

class Tools extends ConsumerWidget {
  const Tools({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text("工具")),
      body: DefaultTabController(
        length: 1,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TabBar(
                    tabAlignment: TabAlignment.start,
                    tabs: [Tab(text: "设备管理", height: 30)],
                    isScrollable: true,
                  ),
                ),
              ],
            ),

            Expanded(child: TabBarView(children: [buildBoardManager(ref)])),
          ],
        ),
      ),
    );
  }

  Widget buildBoardManager(WidgetRef ref) {
    // updatePortList(ref);
    return CustomScrollView(slivers: [
        
      ],
    );
  }
}
