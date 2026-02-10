import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/src/rust/api/main.dart';

StateProvider<List<PortInfo>> portList = StateProvider<List<PortInfo>>(
  (ref) => [],
);
StateProvider<PortInfo?> selectedPort = StateProvider<PortInfo?>((ref) => null);

void updatePortList(WidgetRef ref) async {
  ref.read(portList.notifier).state = await getPortList();
}
