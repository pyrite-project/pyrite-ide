import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/models/board_manager.dart';

class SerialDataCallbacksNotifier
    extends StateNotifier<List<SerialDataCallback>> {
  final Ref ref;

  SerialDataCallbacksNotifier(this.ref) : super([]);

  void add(SerialDataCallback callback) {
    state = [...state, callback];
  }

  void remove(SerialDataCallback callback) {
    state = state.where((cb) => cb != callback).toList();
  }
}

final StateNotifierProvider<
  SerialDataCallbacksNotifier,
  List<SerialDataCallback>
>
serialDataCallbacksProvider = StateNotifierProvider(
  (ref) => SerialDataCallbacksNotifier(ref),
);
