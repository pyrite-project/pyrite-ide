import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flserial/serial_scanner.dart';
import 'package:pyrite_ide/core/services/device/board_identity.dart';
import 'package:pyrite_ide/core/services/serial/hardware_reset_provider.dart';
import 'package:pyrite_ide/core/services/serial/serial_provider.dart';
import 'package:pyrite_ide/core/services/settings.dart';

/// Identifies the board behind one [SerialPortInfo].
BoardIdentity identifyPort(SerialPortInfo port) =>
    identifyBoard(port.vid, port.pid, port.description);

/// Identity of every discovered port, keyed by port path.
///
/// Derived from [serialProvider]'s port list so the device tools page and the
/// connection path share one interpretation of the same data.
final portBoardIdentitiesProvider = Provider<Map<String, BoardIdentity>>((ref) {
  final ports = ref.watch(serialProvider).portInfos;
  return {for (final port in ports) port.path: identifyPort(port)};
});

/// Identity of the currently selected port, or `null` when disconnected.
final activeBoardIdentityProvider = Provider<BoardIdentity?>((ref) {
  final state = ref.watch(serialProvider);
  final portName = state.selectedPortName;
  if (portName == null) return null;
  for (final port in state.portInfos) {
    if (port.path == portName) return identifyPort(port);
  }
  return null;
});

/// Whether a baud rate should be applied automatically.
///
/// The user's explicit choice always wins: if the persisted default differs
/// from the per-family default, the persisted value is kept. Only the untouched
/// factory default (115200) is replaced by the identified board's suggestion,
/// and even then only when the suggestion actually differs.
bool shouldAdoptIdentifiedBaud({
  required int currentBaud,
  required int identifiedBaud,
  required int persistedDefaultBaud,
}) {
  if (currentBaud != persistedDefaultBaud) return false;
  return identifiedBaud != currentBaud;
}

/// Applies identification defaults before opening [path].
///
/// Called from `SerialNotifier.connectPort` so a Pico/ESP32-S3 connects with
/// the baud and reset strategy the board table suggests. Explicit user settings
/// (persisted baud, non-disabled reset strategy) are never overwritten.
BoardIdentity? applyBoardDefaultsOnConnect(Ref ref, {required String path}) {
  BoardIdentity? identity;
  for (final port in ref.read(serialProvider).portInfos) {
    if (port.path == path) {
      identity = identifyPort(port);
      break;
    }
  }
  if (identity == null || !identity.isKnown) return identity;

  // `serialDefaultBaudRate` is the persisted user choice. A different live
  // value means the user (or a previous connection) already set the port
  // explicitly, and _that_ must win over the board table suggestion.
  final persistedDefault = ref.read(serialDefaultBaudRate);
  final current = ref.read(serialProvider).baudRate;
  if (shouldAdoptIdentifiedBaud(
    currentBaud: current,
    identifiedBaud: identity.likelyBaud,
    persistedDefaultBaud: persistedDefault,
  )) {
    ref.read(serialProvider.notifier).setBaudRate(identity.likelyBaud);
  }

  // Only fill the reset strategy when the user has not chosen one: `disabled`
  // is the documented "no sequence selected by default" state.
  final reset = ref.read(hardwareResetStrategyProvider);
  if (reset == HardwareResetStrategy.disabled &&
      identity.hardwareResetStrategy != HardwareResetStrategy.disabled) {
    ref.read(hardwareResetStrategyProvider.notifier).state =
        identity.hardwareResetStrategy;
  }
  return identity;
}
