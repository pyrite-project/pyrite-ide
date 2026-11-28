import 'dart:io';

/// CRC-32 (IEEE 802.3, reflected, poly 0xEDB88320) of [bytes].
///
/// This is the checksum the device side computes with `ubinascii.crc32`, so
/// both sides compare without shipping file content over the serial line.
/// CRC-32 is not collision-proof; it is only used to decide whether a
/// transfer can be skipped, never for integrity guarantees.
int crc32OfBytes(List<int> bytes) {
  var value = 0xFFFFFFFF;
  for (final byte in bytes) {
    value = _crc32Table[(value ^ byte) & 0xFF] ^ (value >> 8);
  }
  return (~value) & 0xFFFFFFFF;
}

/// CRC-32 of a local file's bytes, or `null` when it cannot be read.
///
/// `null` is a normal outcome (file deleted mid-sync, permission error, ...)
/// and callers must treat it as "cannot compare, transfer anyway".
Future<int?> crc32OfFile(String filePath) async {
  try {
    final bytes = await File(filePath).readAsBytes();
    return crc32OfBytes(bytes);
  } on FileSystemException {
    return null;
  }
}

/// Whether two in-memory copies hold exactly the same bytes.
bool bytesIdentical(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

final List<int> _crc32Table = _buildCrc32Table();

List<int> _buildCrc32Table() {
  final table = List<int>.filled(256, 0);
  for (var i = 0; i < 256; i++) {
    var value = i;
    for (var bit = 0; bit < 8; bit++) {
      value = (value & 1) != 0 ? 0xEDB88320 ^ (value >> 1) : value >> 1;
    }
    table[i] = value;
  }
  return table;
}
