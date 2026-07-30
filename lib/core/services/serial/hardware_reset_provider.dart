import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Explicit hardware reset sequences. No sequence is selected by default.
enum HardwareResetStrategy { disabled, dtrPulse, rtsPulse, esp32 }

typedef SetHardwareControlLine = Future<void> Function(bool active);
typedef HardwareResetDelay = Future<void> Function(Duration duration);

/// Applies only the control-line portion of a hardware reset.
///
/// ESP32 boards commonly route active DTR to GPIO0 and active RTS to EN. A
/// normal boot therefore keeps DTR inactive for the complete EN pulse. Driving
/// DTR active while EN is released would select the ROM downloader instead.
Future<void> applyHardwareResetSequence(
  HardwareResetStrategy strategy, {
  required SetHardwareControlLine setDtr,
  required SetHardwareControlLine setRts,
  HardwareResetDelay delay = Future<void>.delayed,
}) async {
  switch (strategy) {
    case HardwareResetStrategy.disabled:
      return;
    case HardwareResetStrategy.dtrPulse:
      await setDtr(false);
      await delay(const Duration(milliseconds: 50));
      await setDtr(true);
      await delay(const Duration(milliseconds: 120));
      await setDtr(false);
    case HardwareResetStrategy.rtsPulse:
      await setRts(false);
      await delay(const Duration(milliseconds: 50));
      await setRts(true);
      await delay(const Duration(milliseconds: 120));
      await setRts(false);
    case HardwareResetStrategy.esp32:
      await setDtr(false);
      await setRts(false);
      await delay(const Duration(milliseconds: 50));
      await setRts(true);
      await delay(const Duration(milliseconds: 150));
      await setRts(false);
  }
}

final hardwareResetStrategyProvider = StateProvider<HardwareResetStrategy>(
  (ref) => HardwareResetStrategy.disabled,
);
