class ReplInputEncoder {
  static String encode(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      if (rune < 0x80) {
        buffer.writeCharCode(rune);
      } else if (rune <= 0xFFFF) {
        buffer.write('\\u${rune.toRadixString(16).padLeft(4, '0')}');
      } else {
        buffer.write('\\U${rune.toRadixString(16).padLeft(8, '0')}');
      }
    }
    return buffer.toString();
  }
}
