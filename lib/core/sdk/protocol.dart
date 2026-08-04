class PluginProtocolException implements Exception {
  const PluginProtocolException(this.message);

  final String message;

  @override
  String toString() => 'PluginProtocolException: $message';
}

abstract final class PluginProtocol {
  static const int version = 1;

  static Map<String, dynamic> validateIncoming(
    Map<String, dynamic> envelope, {
    int? lastSequence,
  }) {
    if (envelope['protocolVersion'] != version) {
      throw PluginProtocolException(
        'Unsupported protocolVersion: ${envelope['protocolVersion']}',
      );
    }
    for (final key in ['pluginId', 'sessionId', 'requestId', 'type']) {
      if (envelope[key] is! String || (envelope[key] as String).isEmpty) {
        throw PluginProtocolException('Missing or invalid $key');
      }
    }
    if (envelope['generation'] is! int || (envelope['generation'] as int) < 1) {
      throw const PluginProtocolException('Invalid generation');
    }
    if (envelope['sequence'] is! int || (envelope['sequence'] as int) < 1) {
      throw const PluginProtocolException('Invalid sequence');
    }
    if (lastSequence != null && envelope['sequence'] as int <= lastSequence) {
      throw PluginProtocolException(
        'Duplicate or out-of-order sequence: ${envelope['sequence']}',
      );
    }
    if (envelope['payload'] is! Map) {
      throw const PluginProtocolException('Payload must be an object');
    }
    final deadline = envelope['deadline'];
    if (deadline != null && (deadline is! int || deadline < 0)) {
      throw const PluginProtocolException('Invalid deadline');
    }
    return envelope;
  }
}
