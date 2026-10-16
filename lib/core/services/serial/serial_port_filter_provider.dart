import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/models/serial_port_filter.dart';

/// The device list's search and filter state.
///
/// Kept in memory only: it survives switching pages but resets on restart.
final serialPortFilterProvider = StateProvider<SerialPortFilter>(
  (ref) => const SerialPortFilter(),
);
