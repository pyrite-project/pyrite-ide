import 'package:flutter/foundation.dart';
import 'package:pyrite_ide/core/models/search_options.dart';
import 'package:pyrite_ide/core/models/serial_port_descriptor.dart';

/// [SerialPortFilter.apply] output. `total` counts the ports that are listable
/// before the query and toggles apply; `regexError` is set when the query is
/// an invalid regular expression.
typedef SerialPortFilterResult = ({
  List<SerialPortDescriptor> visible,
  int total,
  String? regexError,
});

/// What the device list shows out of the scanned ports.
///
/// With every toggle off it lists what `pyrcli scan --all` would; [usbOnly]
/// narrows that to plain `pyrcli scan`, which drops ports without a USB VID.
@immutable
class SerialPortFilter {
  const SerialPortFilter({
    this.query = '',
    this.options = const SearchOptions(),
    this.usbOnly = false,
  });

  final String query;
  final SearchOptions options;
  final bool usbOnly;

  bool get isActive => query.isNotEmpty || usbOnly;

  SerialPortFilterResult apply(List<SerialPortDescriptor> ports) {
    final listable = [
      for (final port in ports)
        if (!port.hiddenInternal) port,
    ];
    RegExp? pattern;
    try {
      pattern = options.patternFor(query);
    } on FormatException catch (error) {
      return (
        visible: const [],
        total: listable.length,
        regexError: error.message,
      );
    }
    final visible = [
      for (final port in listable)
        if ((!usbOnly || port.isUsb) &&
            (pattern == null || _matches(port, pattern)))
          port,
    ]..sort(_compareForDisplay);
    return (visible: visible, total: listable.length, regexError: null);
  }

  /// Fields are matched one at a time so a whole-word match cannot straddle
  /// two of them. The hwid carries `VID:PID=303A:1001`, so typing the hex IDs
  /// covers pyrcli's `--vid` / `--pid` too.
  static bool _matches(SerialPortDescriptor port, RegExp pattern) {
    return [
      port.path,
      port.description,
      port.hwid,
      port.manufacturer,
      port.product,
      port.interface,
      port.serialNumber,
    ].any((field) => field != null && pattern.hasMatch(field));
  }

  /// USB ports first, then device paths in natural order (`ttyS2` before
  /// `ttyS10`).
  static int _compareForDisplay(
    SerialPortDescriptor a,
    SerialPortDescriptor b,
  ) {
    if (a.isUsb != b.isUsb) return a.isUsb ? -1 : 1;
    return compareNatural(a.path, b.path);
  }

  SerialPortFilter copyWith({
    String? query,
    SearchOptions? options,
    bool? usbOnly,
  }) {
    return SerialPortFilter(
      query: query ?? this.query,
      options: options ?? this.options,
      usbOnly: usbOnly ?? this.usbOnly,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SerialPortFilter &&
      other.query == query &&
      other.options == options &&
      other.usbOnly == usbOnly;

  @override
  int get hashCode => Object.hash(query, options, usbOnly);
}

final _digitRun = RegExp(r'\d+|\D+');

/// Compares strings so embedded numbers sort by value.
int compareNatural(String a, String b) {
  final left = _digitRun.allMatches(a).map((m) => m[0]!).toList();
  final right = _digitRun.allMatches(b).map((m) => m[0]!).toList();
  for (var i = 0; i < left.length && i < right.length; i++) {
    final x = left[i];
    final y = right[i];
    final xNumber = int.tryParse(x);
    final yNumber = int.tryParse(y);
    final result = xNumber != null && yNumber != null
        ? xNumber.compareTo(yNumber)
        : x.compareTo(y);
    if (result != 0) return result;
  }
  final byLength = left.length.compareTo(right.length);
  return byLength != 0 ? byLength : a.compareTo(b);
}
