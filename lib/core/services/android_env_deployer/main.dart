import 'package:flutter_riverpod/flutter_riverpod.dart';

StateProvider<double> progress = StateProvider<double>((ref) => 0.0);
StateProvider<String> message = StateProvider<String>((ref) => "（输出内容）");
StateProvider<bool> state = StateProvider<bool>((ref) => true);
