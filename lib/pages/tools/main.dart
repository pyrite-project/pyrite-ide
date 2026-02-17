import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/board_manager/desktop.dart' as desktop;
import 'package:pyrite_ide/core/services/board_manager/android.dart' as android;
import 'package:pyrite_ide/core/services/board_manager/main.dart';

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
    if (Platform.isAndroid) {
      android.update(ref);
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(left: 15, right: 15, top: 10),
              child: Text(
                (ref.watch(connectState))
                    ? "已连接：${ref.watch(android.selectedPortName)!}"
                    : "暂未连接",
              ),
            ),
          ),
          SliverList.builder(
            itemCount: ref.watch(android.devices).length,
            itemBuilder: (context, index) {
              final port = ref.watch(android.devices)[index];
              return ExpansionTile(
                childrenPadding: EdgeInsets.only(left: 15, right: 15),
                title: Text(ref.watch(android.devices)[index].deviceName),
                children: [
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(5),
                    child: FilledButton(
                      onPressed: () {
                        android.connectPort(
                          ref,
                          ref.watch(android.devices)[index],
                        );
                        // startReplLinster(ref);
                      },
                      child: Text("尝试连接"),
                    ),
                  ),
                  buildCardListTile(
                    context,
                    'USB Device',
                    port.deviceId.toString(),
                  ),
                  buildCardListTile(context, 'Vendor ID', port.vid?.toString()),
                  buildCardListTile(
                    context,
                    'Product ID',
                    port.pid?.toString(),
                  ),
                  buildCardListTile(
                    context,
                    'Manufacturer',
                    port.manufacturerName,
                  ),
                  buildCardListTile(context, 'Product Name', port.productName),
                  buildCardListTile(context, 'MAC Address', port.serial),
                ],
              );
            },
          ),
        ],
      );
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        desktop.update(ref);
      });
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(left: 15, right: 15, top: 10),
              child: Text(
                (ref.watch(connectState))
                    ? "已连接：${ref.watch(desktop.selectedPortName)!}"
                    : "暂未连接",
              ),
            ),
          ),
          SliverToBoxAdapter(child: Divider()),
          SliverList.builder(
            itemCount: ref.watch(desktop.ports).length,
            itemBuilder: (context, index) {
              final port = SerialPort(ref.watch(desktop.ports)[index]);
              return ExpansionTile(
                childrenPadding: EdgeInsets.only(left: 15, right: 15),
                title: Text(ref.watch(desktop.ports)[index]),
                children: [
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(5),
                    child: FilledButton(
                      onPressed: () {
                        desktop.connectPort(
                          ref,
                          ref.watch(desktop.ports)[index],
                        );
                        // startReplLinster(ref);
                      },
                      child: Text("尝试连接"),
                    ),
                  ),

                  buildCardListTile(context, 'Description', port.description),
                  buildCardListTile(
                    context,
                    'Transport',
                    port.transport.toString(),
                  ),
                  buildCardListTile(
                    context,
                    'USB Bus',
                    port.busNumber?.toString(),
                  ),
                  buildCardListTile(
                    context,
                    'USB Device',
                    port.deviceNumber?.toString(),
                  ),
                  buildCardListTile(
                    context,
                    'Vendor ID',
                    port.vendorId?.toString(),
                  ),
                  buildCardListTile(
                    context,
                    'Product ID',
                    port.productId?.toString(),
                  ),
                  buildCardListTile(context, 'Manufacturer', port.manufacturer),
                  buildCardListTile(context, 'Product Name', port.productName),
                  buildCardListTile(
                    context,
                    'Serial Number',
                    port.serialNumber,
                  ),
                  buildCardListTile(context, 'MAC Address', port.macAddress),
                ],
              );
            },
          ),
        ],
      );
    }
  }

  Widget buildCardListTile(BuildContext context, String name, String? value) {
    return Card(
      child: ListTile(title: Text(value ?? 'N/A'), subtitle: Text(name)),
    );
  }
}
