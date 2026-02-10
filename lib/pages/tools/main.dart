import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/tools/board_manager.dart';
import 'package:pyrite_ide/shared/studio_text.dart';
import 'package:pyrite_ide/src/rust/api/main.dart';

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
    updatePortList(ref);
    return CustomScrollView(
      slivers: [
        SliverList.builder(
          itemCount: ref.watch(portList).length,
          itemBuilder: (context, index) {
            return ListTile(
              title: Text(ref.watch(portList)[index].portName),
              subtitle: Text("点击以尝试连接"),
              onTap: () {
                ref.read(selectedPort.notifier).state = ref.read(
                  portList,
                )[index];

                connectPort(portName: ref.read(selectedPort)!.portName);
              },
            );
          },
        ),
      ],
    );
  }
}
