class DeviceStatus {
  const DeviceStatus({
    required this.ramUsed,
    required this.ramTotal,
    required this.flashUsed,
    required this.flashTotal,
    required this.firmwareVersion,
    required this.platformModel,
  });

  final int ramUsed;
  final int ramTotal;
  final int flashUsed;
  final int flashTotal;
  final String firmwareVersion;
  final String platformModel;

  int get ramFree => ramTotal - ramUsed;
  int get flashFree => flashTotal - flashUsed;

  double get ramUsage => ramTotal > 0 ? ramUsed / ramTotal : 0;
  double get flashUsage => flashTotal > 0 ? flashUsed / flashTotal : 0;

  String get ramUsedDisplay => _formatBytes(ramUsed);
  String get ramTotalDisplay => _formatBytes(ramTotal);
  String get flashUsedDisplay => _formatBytes(flashUsed);
  String get flashTotalDisplay => _formatBytes(flashTotal);

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  String toString() =>
      'DeviceStatus(ram: $ramUsedDisplay/$ramTotalDisplay, '
      'flash: $flashUsedDisplay/$flashTotalDisplay, '
      'fw: $firmwareVersion, platform: $platformModel)';
}
