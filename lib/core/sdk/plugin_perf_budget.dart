/// Performance budgets for the plugin protocol (T21).
///
/// Values are starting points from the refactor plan; adjust from benchmarks.
abstract class PluginPerfBudget {
  /// Default timeout for ordinary IDE↔plugin RPC.
  static const Duration rpcTimeout = Duration(seconds: 5);

  /// Timeout for UI-interactive RPC (command execute, view open, etc.).
  static const Duration uiRpcTimeout = Duration(seconds: 2);

  /// Per-plugin inbound control-message queue capacity.
  static const int controlQueueCapacity = 256;

  /// Per-plugin inbound view-patch queue capacity (drops oldest on overflow).
  static const int viewPatchQueueCapacity = 32;

  /// Messages processed before yielding back to the Flutter event loop.
  static const int inboundDrainBatchSize = 32;

  /// Event-bus subscription queue high-water mark before degrade metrics fire.
  static const int eventQueueHighWater = 192;

  /// Default document.changed debounce.
  static const Duration documentChangedDebounce = Duration(milliseconds: 100);

  /// Default selection.changed throttle window.
  static const Duration selectionChangedThrottle = Duration(milliseconds: 50);

  /// Default serial.data.received batch window.
  static const Duration serialDataBatch = Duration(milliseconds: 32);

  /// Maximum JSON string length decoded on the UI isolate without deferral.
  static const int maxInlineJsonBytes = 256 * 1024;

  /// Absolute transport-envelope limit. Larger data belongs on a future data
  /// channel rather than the latency-sensitive control channel.
  static const int maxMessageBytes = 8 * 1024 * 1024;

  /// Maximum nodes allowed in one view snapshot.
  static const int maxSnapshotNodes = 20_000;

  /// Maximum operations in one view patch transaction.
  static const int maxPatchOps = 2_000;

  /// Maximum UTF-8 size of a single view snapshot/patch payload.
  static const int maxViewPayloadBytes = 2 * 1024 * 1024;

  /// Maximum text accepted in one output append operation.
  static const int maxLogBatchBytes = 64 * 1024;

  /// Recently cancelled request IDs retained to discard late responses.
  static const int cancelledRequestHistory = 256;

  /// Consecutive handler failures before pausing a plugin's event delivery.
  static const int consecutiveFailureLimit = 8;

  /// Base delay for plugin auto-restart backoff.
  static const Duration restartBackoffBase = Duration(seconds: 1);

  /// Cap for plugin auto-restart backoff.
  static const Duration restartBackoffMax = Duration(seconds: 60);
}
