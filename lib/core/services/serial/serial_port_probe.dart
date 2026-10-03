/// Platform probe for whether a serial port name still exists on the system.
///
/// The web build has no OS port registry, so the probe always reports the
/// port as present (the browser owns the connection lifecycle).
export 'serial_port_probe_web.dart'
    if (dart.library.io) 'serial_port_probe_io.dart';
