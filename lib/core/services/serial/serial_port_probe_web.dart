/// Web probe: the browser owns the Web Serial connection, so a selected port
/// is always considered present until the browser reports an error.
Future<bool> serialPortExistsOnSystem(String portName) async => true;
