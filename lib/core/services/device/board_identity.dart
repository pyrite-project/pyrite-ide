import 'package:pyrite_ide/core/services/serial/hardware_reset_provider.dart';

/// MicroPython chip family behind a USB serial port.
///
/// The family is what the IDE actually needs: it selects the default baud rate
/// and the reset strategy. A concrete board label is presentation only.
enum BoardFamily {
  esp32,
  esp32s2,
  esp32s3,
  esp32c3,
  esp32c6,
  esp8266,
  rp2040,
  stm32,
  k230,
  unknown,
}

/// How the host should reset the board into / out of the REPL.
///
/// Wraps [HardwareResetStrategy] so identification can express "this family has
/// no host-controllable reset" without inventing a new serial sequence.
enum BoardResetStrategy {
  /// No host-side reset; the user presses the board's own reset button.
  none,

  /// Pulse DTR only (classic CP210x/CH340 wired to EN only).
  dtrPulse,

  /// Pulse RTS only.
  rtsPulse,

  /// ESP32 auto-reset: RTS -> EN, DTR -> GPIO0.
  esp32,

  /// The port reappears after a reset without control-line support (native
  /// USB CDC); the host only needs to reopen the handle.
  reopenPort,
}

/// Immutable identification result for one USB serial port.
class BoardIdentity {
  const BoardIdentity({
    required this.family,
    required this.label,
    required this.likelyBaud,
    required this.resetStrategy,
    this.vid,
    this.pid,
    this.confidence = BoardIdentityConfidence.exact,
  });

  /// Chip family used for defaults.
  final BoardFamily family;

  /// Human readable board/chip label, e.g. `ESP32-S3 (native USB)`.
  final String label;

  /// Baud rate the IDE should connect with by default.
  final int likelyBaud;

  /// Reset approach recommended for this family.
  final BoardResetStrategy resetStrategy;

  /// USB vendor id the match was based on, when known.
  final int? vid;

  /// USB product id the match was based on, when known.
  final int? pid;

  /// How the identity was derived.
  final BoardIdentityConfidence confidence;

  bool get isKnown => family != BoardFamily.unknown;

  /// The matching [HardwareResetStrategy] for this board.
  ///
  /// [BoardResetStrategy.reopenPort] maps to [HardwareResetStrategy.disabled]
  /// because toggling DTR/RTS on a native USB CDC port would drop the
  /// connection instead of resetting the chip; the port is reopened instead.
  HardwareResetStrategy get hardwareResetStrategy {
    switch (resetStrategy) {
      case BoardResetStrategy.none:
      case BoardResetStrategy.reopenPort:
        return HardwareResetStrategy.disabled;
      case BoardResetStrategy.dtrPulse:
        return HardwareResetStrategy.dtrPulse;
      case BoardResetStrategy.rtsPulse:
        return HardwareResetStrategy.rtsPulse;
      case BoardResetStrategy.esp32:
        return HardwareResetStrategy.esp32;
    }
  }

  /// Unknown-board placeholder used when neither USB ids nor the description
  /// give a confident answer.
  static const BoardIdentity unknown = BoardIdentity(
    family: BoardFamily.unknown,
    label: 'Unknown board',
    likelyBaud: 115200,
    resetStrategy: BoardResetStrategy.none,
    confidence: BoardIdentityConfidence.unknown,
  );

  @override
  String toString() =>
      'BoardIdentity(${family.name}, $label, ${confidence.name}, '
      'baud=$likelyBaud, reset=${resetStrategy.name})';
}

/// How confident the identification is.
enum BoardIdentityConfidence {
  /// Matched a known VID/PID pair (or a well-known chip family by name).
  exact,

  /// Matched only through the port description text.
  description,

  /// Matched a generic USB bridge chip, so only the transport is known.
  transportOnly,

  /// Nothing matched.
  unknown,
}

/// One row of the board table.
class BoardDefinition {
  const BoardDefinition({
    required this.family,
    required this.label,
    required this.likelyBaud,
    required this.resetStrategy,
    this.vid,
    this.pid,
    this.descriptionKeywords = const [],
  });

  final BoardFamily family;
  final String label;
  final int likelyBaud;
  final BoardResetStrategy resetStrategy;

  /// USB vendor id this row matches, when the row is VID/PID specific.
  final int? vid;

  /// USB product id this row matches, when the row is VID/PID specific.
  final int? pid;

  /// Case-insensitive substrings matched against the port description.
  final List<String> descriptionKeywords;
}

// ---------------------------------------------------------------------------
// Known USB ids
//
// Sources (checked while writing this table):
//  * Espressif: esptool `--port-filter` docs and the Espressif USB PID repo.
//    0x303A:0x1001 is the shared USB-Serial/JTAG unit (S3/C3/C6/S2),
//    0x303A:0x0002 is ESP32-S2 USB-OTG.
//  * Raspberry Pi: https://github.com/raspberrypi/usb-pid
//    0x2E8A:0x0005 = Pico MicroPython CDC, 0x0003 = RP2040 BOOTSEL,
//    0x000F = RP2350 BOOTSEL.
//  * MicroPython STM32 default: VID 0xF055, PIDs 0x9800 (CDC) /
//    0x9801 (CDC+MSC) / 0x9802 (CDC+HID) / 0x9803 (CDC+MSC+HID).
// ---------------------------------------------------------------------------

/// Vendor id used by boards that ship the stock MicroPython STM32 USB stack.
const int micropythonStmVid = 0xF055;

/// Vendor id of Espressif's native USB peripherals.
const int espressifVid = 0x303A;

/// Vendor id allocated to the RP2040 silicon (sub-licensed by Raspberry Pi).
const int raspberryPiVid = 0x2E8A;

/// The board table. Rows are ordered from most to least specific; the first
/// row that matches wins, so VID/PID rows precede description-only rows.
const List<BoardDefinition> boardTable = [
  // -- ESP32-S3 native USB ------------------------------------------------
  BoardDefinition(
    family: BoardFamily.esp32s3,
    label: 'ESP32-S3 (native USB)',
    likelyBaud: 115200,
    resetStrategy: BoardResetStrategy.reopenPort,
    vid: espressifVid,
    pid: 0x1001,
    descriptionKeywords: ['esp32-s3', 'esp32s3'],
  ),
  // -- ESP32-S2 USB-OTG ---------------------------------------------------
  BoardDefinition(
    family: BoardFamily.esp32s2,
    label: 'ESP32-S2 (USB OTG)',
    likelyBaud: 115200,
    resetStrategy: BoardResetStrategy.reopenPort,
    vid: espressifVid,
    pid: 0x0002,
    descriptionKeywords: ['esp32-s2', 'esp32s2'],
  ),
  // -- Other Espressif native-USB PIDs (C3/C6/H2 and future parts) --------
  //
  // Espressif allocates a PID per chip; only the two above are stable enough
  // to name. Everything else on the Espressif VID is tagged as ESP32-family
  // with the native-USB reopen behaviour so the user still gets sane defaults.
  BoardDefinition(
    family: BoardFamily.esp32,
    label: 'Espressif USB device',
    likelyBaud: 115200,
    resetStrategy: BoardResetStrategy.reopenPort,
    vid: espressifVid,
    descriptionKeywords: ['esp32'],
  ),
  // -- ESP32-C3 / C6 via a USB-UART bridge --------------------------------
  BoardDefinition(
    family: BoardFamily.esp32c3,
    label: 'ESP32-C3',
    likelyBaud: 115200,
    resetStrategy: BoardResetStrategy.esp32,
    descriptionKeywords: ['esp32-c3', 'esp32c3'],
  ),
  BoardDefinition(
    family: BoardFamily.esp32c6,
    label: 'ESP32-C6',
    likelyBaud: 115200,
    resetStrategy: BoardResetStrategy.esp32,
    descriptionKeywords: ['esp32-c6', 'esp32c6'],
  ),
  // -- ESP8266 (always through a USB-UART bridge) -------------------------
  BoardDefinition(
    family: BoardFamily.esp8266,
    label: 'ESP8266',
    likelyBaud: 115200,
    resetStrategy: BoardResetStrategy.rtsPulse,
    descriptionKeywords: ['esp8266', 'nodemcu', 'wemos'],
  ),
  // -- RP2040 / Pico ------------------------------------------------------
  BoardDefinition(
    family: BoardFamily.rp2040,
    label: 'Raspberry Pi Pico (MicroPython)',
    likelyBaud: 115200,
    resetStrategy: BoardResetStrategy.reopenPort,
    vid: raspberryPiVid,
    pid: 0x0005,
    descriptionKeywords: ['pico', 'rp2040', 'rp2350'],
  ),
  BoardDefinition(
    family: BoardFamily.rp2040,
    label: 'Raspberry Pi RP2040 (BOOTSEL)',
    likelyBaud: 115200,
    resetStrategy: BoardResetStrategy.none,
    vid: raspberryPiVid,
    pid: 0x0003,
  ),
  BoardDefinition(
    family: BoardFamily.rp2040,
    label: 'Raspberry Pi RP2350 (BOOTSEL)',
    likelyBaud: 115200,
    resetStrategy: BoardResetStrategy.none,
    vid: raspberryPiVid,
    pid: 0x000F,
  ),
  BoardDefinition(
    family: BoardFamily.rp2040,
    label: 'Raspberry Pi Pico SDK CDC UART',
    likelyBaud: 115200,
    resetStrategy: BoardResetStrategy.reopenPort,
    vid: raspberryPiVid,
    pid: 0x0009,
  ),
  // -- STM32 / pyboard ----------------------------------------------------
  BoardDefinition(
    family: BoardFamily.stm32,
    label: 'MicroPython STM32 (pyboard)',
    likelyBaud: 115200,
    resetStrategy: BoardResetStrategy.dtrPulse,
    vid: micropythonStmVid,
    pid: 0x9800,
    descriptionKeywords: ['pyboard', 'stm32'],
  ),
  BoardDefinition(
    family: BoardFamily.stm32,
    label: 'MicroPython STM32 (CDC+MSC)',
    likelyBaud: 115200,
    resetStrategy: BoardResetStrategy.dtrPulse,
    vid: micropythonStmVid,
    pid: 0x9801,
  ),
  BoardDefinition(
    family: BoardFamily.stm32,
    label: 'MicroPython STM32 (CDC+HID)',
    likelyBaud: 115200,
    resetStrategy: BoardResetStrategy.dtrPulse,
    vid: micropythonStmVid,
    pid: 0x9802,
  ),
  BoardDefinition(
    family: BoardFamily.stm32,
    label: 'MicroPython STM32 (CDC+MSC+HID)',
    likelyBaud: 115200,
    resetStrategy: BoardResetStrategy.dtrPulse,
    vid: micropythonStmVid,
    pid: 0x9803,
  ),
  // -- K230 CanMV ---------------------------------------------------------
  //
  // The K230's REPL runs on a USB-UART bridge whose ids differ between the
  // CanMV revisions we could inspect, so this row is description-only rather
  // than carrying a guessed VID/PID.
  BoardDefinition(
    family: BoardFamily.k230,
    label: 'K230 CanMV',
    likelyBaud: 115200,
    resetStrategy: BoardResetStrategy.none,
    descriptionKeywords: ['k230', 'canmv', 'kendryte'],
  ),
  // -- Generic USB-UART bridges ------------------------------------------
  //
  // These appear on many boards, so only the transport is known: the row maps
  // to an unknown family but keeps the ESP32 auto-reset defaults, which is the
  // most common wiring for MicroPython boards sold with such a bridge.
  BoardDefinition(
    family: BoardFamily.unknown,
    label: 'USB-UART bridge (FTDI)',
    likelyBaud: 115200,
    resetStrategy: BoardResetStrategy.esp32,
    vid: 0x0403,
  ),
  BoardDefinition(
    family: BoardFamily.unknown,
    label: 'USB-UART bridge (Silicon Labs CP210x)',
    likelyBaud: 115200,
    resetStrategy: BoardResetStrategy.esp32,
    vid: 0x10C4,
  ),
  BoardDefinition(
    family: BoardFamily.unknown,
    label: 'USB-UART bridge (WCH CH34x)',
    likelyBaud: 115200,
    resetStrategy: BoardResetStrategy.esp32,
    vid: 0x1A86,
  ),
  BoardDefinition(
    family: BoardFamily.unknown,
    label: 'USB-UART bridge (Prolific PL2303)',
    likelyBaud: 115200,
    resetStrategy: BoardResetStrategy.esp32,
    vid: 0x067B,
  ),
  BoardDefinition(
    family: BoardFamily.unknown,
    label: 'USB STM32 virtual COM port',
    likelyBaud: 115200,
    resetStrategy: BoardResetStrategy.reopenPort,
    vid: 0x0483,
  ),
];

/// Baud rate used when the board is not recognised at all.
const int defaultBoardBaud = 115200;

/// Identifies a MicroPython board from its USB ids and port description.
///
/// All inputs are nullable because none of the desktop platforms guarantee
/// them. The function is pure and deterministic so it can be unit tested and
/// reused by both the device tools page and the connection path.
///
/// Resolution order:
/// 1. exact VID+PID row;
/// 2. description keyword row;
/// 3. VID-only row (transport known, family usually not);
/// 4. [BoardIdentity.unknown].
BoardIdentity identifyBoard(int? vid, int? pid, String? description) {
  final normalizedDescription = (description ?? '').toLowerCase();

  if (vid != null && pid != null) {
    final exact = _matchExactVidPid(vid, pid);
    if (exact != null) {
      return _identityFromDefinition(
        exact,
        vid: vid,
        pid: pid,
        confidence: exact.family == BoardFamily.unknown
            ? BoardIdentityConfidence.transportOnly
            : BoardIdentityConfidence.exact,
      );
    }
  }

  final descriptionMatch = _matchDescription(normalizedDescription);
  if (descriptionMatch != null) {
    return _identityFromDefinition(
      descriptionMatch,
      vid: vid,
      pid: pid,
      confidence: BoardIdentityConfidence.description,
    );
  }

  if (vid != null) {
    final vidRow = boardTable
        .where((row) => row.vid == vid && row.pid == null)
        .firstOrNull;
    if (vidRow != null) {
      return _identityFromDefinition(
        vidRow,
        vid: vid,
        pid: pid,
        confidence: BoardIdentityConfidence.transportOnly,
      );
    }
  }

  return BoardIdentity(
    family: BoardFamily.unknown,
    label: 'Unknown board',
    likelyBaud: defaultBoardBaud,
    resetStrategy: BoardResetStrategy.none,
    vid: vid,
    pid: pid,
    confidence: BoardIdentityConfidence.unknown,
  );
}

BoardDefinition? _matchExactVidPid(int vid, int pid) {
  for (final row in boardTable) {
    if (row.vid == vid && row.pid == pid) return row;
  }
  return null;
}

BoardDefinition? _matchDescription(String description) {
  if (description.isEmpty) return null;
  BoardDefinition? best;
  var bestLength = -1;
  for (final row in boardTable) {
    for (final keyword in row.descriptionKeywords) {
      if (!description.contains(keyword)) continue;
      // Prefer the longest keyword so "esp32-s3" beats "esp32".
      if (keyword.length > bestLength) {
        best = row;
        bestLength = keyword.length;
      }
    }
  }
  return best;
}

BoardIdentity _identityFromDefinition(
  BoardDefinition definition, {
  required int? vid,
  required int? pid,
  required BoardIdentityConfidence confidence,
}) {
  return BoardIdentity(
    family: definition.family,
    label: definition.label,
    likelyBaud: definition.likelyBaud,
    resetStrategy: definition.resetStrategy,
    vid: vid,
    pid: pid,
    confidence: confidence,
  );
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
