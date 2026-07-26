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
    state = [
      for (final c in state)
        if (c != callback) c,
    ];
  }
}

final StateNotifierProvider<
  SerialDataCallbacksNotifier,
  List<SerialDataCallback>
>
serialDataCallbacksProvider = StateNotifierProvider(
  (ref) => SerialDataCallbacksNotifier(ref),
);
