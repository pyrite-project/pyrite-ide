import 'dart:collection';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/sdk/plugin_perf_budget.dart';

/// Live counters for one plugin session (T21/T22).
class PluginSessionMetrics {
  PluginSessionMetrics({
    required this.pluginId,
    required this.sessionId,
    required this.generation,
    void Function()? onChanged,
  }) : startedAt = DateTime.now(),
       _onChanged = onChanged;

  final String pluginId;
  final String sessionId;
  final int generation;
  final DateTime startedAt;
  final void Function()? _onChanged;

  int messagesSent = 0;
  int messagesReceived = 0;
  int bytesSent = 0;
  int bytesReceived = 0;
  int eventQueueDepth = 0;
  int eventQueueHighWater = 0;
  int controlQueueDepth = 0;
  int controlQueueHighWater = 0;
  int patchQueueDepth = 0;
  int patchQueueHighWater = 0;
  int timeouts = 0;
  int cancellations = 0;
  int drops = 0;
  int errors = 0;
  int viewResyncs = 0;
  int viewPatches = 0;
  int consecutiveFailures = 0;
  bool eventDeliveryPaused = false;
  String state = 'starting';
  DateTime? activationCompletedAt;
  DateTime? stoppedAt;
  DateTime? lastHealthAt;
  int? lastHealthLatencyMs;
  bool healthOk = false;
  bool stopTimedOut = false;
  String? lastError;
  String? lastTraceback;

  final ListQueue<int> _rpcLatenciesMs = ListQueue();
  static const int _latencyWindow = 64;

  Duration? get activationDuration {
    final done = activationCompletedAt;
    if (done == null) return null;
    return done.difference(startedAt);
  }

  void recordSent(int bytes) {
    messagesSent += 1;
    bytesSent += bytes;
    _changed();
  }

  void recordReceived(int bytes) {
    messagesReceived += 1;
    bytesReceived += bytes;
    _changed();
  }

  void recordRpcLatency(Duration latency) {
    _rpcLatenciesMs.addLast(latency.inMilliseconds);
    while (_rpcLatenciesMs.length > _latencyWindow) {
      _rpcLatenciesMs.removeFirst();
    }
    _changed();
  }

  void recordEventQueueDepth(int depth) {
    eventQueueDepth = depth;
    if (depth > eventQueueHighWater) eventQueueHighWater = depth;
    _changed();
  }

  void recordControlQueueDepth(int depth) {
    controlQueueDepth = depth;
    if (depth > controlQueueHighWater) controlQueueHighWater = depth;
    _changed();
  }

  void recordPatchQueueDepth(int depth) {
    patchQueueDepth = depth;
    if (depth > patchQueueHighWater) patchQueueHighWater = depth;
    _changed();
  }

  void recordError(String message, {String? traceback}) {
    errors += 1;
    consecutiveFailures += 1;
    lastError = message;
    if (traceback != null && traceback.isNotEmpty) lastTraceback = traceback;
    if (consecutiveFailures >= PluginPerfBudget.consecutiveFailureLimit) {
      eventDeliveryPaused = true;
    }
    _changed();
  }

  void recordSuccess() {
    consecutiveFailures = 0;
    _changed();
  }

  void recordTimeout() {
    timeouts += 1;
    _changed();
  }

  void recordCancellation() {
    cancellations += 1;
    _changed();
  }

  void recordDrop() {
    drops += 1;
    _changed();
  }

  void recordViewPatch() {
    viewPatches += 1;
    _changed();
  }

  void recordViewResync() {
    viewResyncs += 1;
    _changed();
  }

  void markActivated() {
    activationCompletedAt ??= DateTime.now();
    state = 'ready';
    _changed();
  }

  void markStopping() {
    state = 'stopping';
    _changed();
  }

  void markStopped({bool timedOut = false}) {
    state = timedOut ? 'failed' : 'stopped';
    stoppedAt = DateTime.now();
    stopTimedOut = timedOut;
    _changed();
  }

  void markFailed(Object error, {String? traceback}) {
    state = 'failed';
    recordError('$error', traceback: traceback);
  }

  void recordHealth(Duration latency) {
    lastHealthAt = DateTime.now();
    lastHealthLatencyMs = latency.inMilliseconds;
    healthOk = true;
    _changed();
  }

  void recordHealthFailure(Object error) {
    lastHealthAt = DateTime.now();
    healthOk = false;
    recordError('Health check failed: $error');
  }

  void resumeEventDelivery() {
    eventDeliveryPaused = false;
    consecutiveFailures = 0;
    _changed();
  }

  void _changed() => _onChanged?.call();

  int? get rpcP50Ms => _percentile(0.50);
  int? get rpcP95Ms => _percentile(0.95);

  int? _percentile(double p) {
    if (_rpcLatenciesMs.isEmpty) return null;
    final sorted = _rpcLatenciesMs.toList()..sort();
    final index = min(sorted.length - 1, (sorted.length * p).floor());
    return sorted[index];
  }

  Map<String, dynamic> toJson() => {
    'pluginId': pluginId,
    'sessionId': sessionId,
    'generation': generation,
    'messagesSent': messagesSent,
    'messagesReceived': messagesReceived,
    'bytesSent': bytesSent,
    'bytesReceived': bytesReceived,
    'eventQueueDepth': eventQueueDepth,
    'eventQueueHighWater': eventQueueHighWater,
    'controlQueueDepth': controlQueueDepth,
    'controlQueueHighWater': controlQueueHighWater,
    'patchQueueDepth': patchQueueDepth,
    'patchQueueHighWater': patchQueueHighWater,
    'timeouts': timeouts,
    'cancellations': cancellations,
    'drops': drops,
    'errors': errors,
    'viewResyncs': viewResyncs,
    'viewPatches': viewPatches,
    'consecutiveFailures': consecutiveFailures,
    'eventDeliveryPaused': eventDeliveryPaused,
    'state': state,
    'rpcP50Ms': rpcP50Ms,
    'rpcP95Ms': rpcP95Ms,
    'activationMs': activationDuration?.inMilliseconds,
    'stoppedAt': stoppedAt?.toIso8601String(),
    'lastHealthAt': lastHealthAt?.toIso8601String(),
    'lastHealthLatencyMs': lastHealthLatencyMs,
    'healthOk': healthOk,
    'stopTimedOut': stopTimedOut,
    'lastError': lastError,
    'lastTraceback': lastTraceback,
  };
}

/// Host-wide metrics: per-plugin sessions plus runtime restart accounting.
class PluginMetricsRegistry extends ChangeNotifier {
  final Map<String, PluginSessionMetrics> _byPlugin = {};
  int runtimeGeneration = 0;
  int runtimeRestarts = 0;
  final Map<String, DateTime> _restartBackoffUntil = {};
  final Map<String, int> _restartAttempts = {};

  PluginSessionMetrics? forPlugin(String pluginId) => _byPlugin[pluginId];

  Iterable<PluginSessionMetrics> get sessions => _byPlugin.values;

  PluginSessionMetrics beginSession({
    required String pluginId,
    required String sessionId,
    required int generation,
  }) {
    if (generation > runtimeGeneration) runtimeGeneration = generation;
    final metrics = PluginSessionMetrics(
      pluginId: pluginId,
      sessionId: sessionId,
      generation: generation,
      onChanged: _scheduleNotify,
    );
    _byPlugin[pluginId] = metrics;
    notifyListeners();
    return metrics;
  }

  void markActivated(String pluginId) {
    final metrics = _byPlugin[pluginId];
    if (metrics == null) return;
    metrics.markActivated();
  }

  void endSession(String pluginId, {bool timedOut = false}) {
    final metrics = _byPlugin[pluginId];
    if (metrics == null) return;
    metrics.markStopped(timedOut: timedOut);
  }

  void clear() {
    _byPlugin.clear();
    notifyListeners();
  }

  void recordRuntimeRestart(int generation) {
    runtimeRestarts += 1;
    runtimeGeneration = generation;
    _byPlugin.clear();
    notifyListeners();
  }

  /// Returns null when the plugin may start; otherwise the remaining backoff.
  Duration? restartBackoffRemaining(String pluginId) {
    final until = _restartBackoffUntil[pluginId];
    if (until == null) return null;
    final remaining = until.difference(DateTime.now());
    return remaining.isNegative ? null : remaining;
  }

  void noteRestartFailure(String pluginId) {
    final attempt = (_restartAttempts[pluginId] ?? 0) + 1;
    _restartAttempts[pluginId] = attempt;
    final millis = min(
      PluginPerfBudget.restartBackoffMax.inMilliseconds,
      PluginPerfBudget.restartBackoffBase.inMilliseconds * (1 << (attempt - 1)),
    );
    _restartBackoffUntil[pluginId] = DateTime.now().add(
      Duration(milliseconds: millis),
    );
    notifyListeners();
  }

  void noteRestartSuccess(String pluginId) {
    _restartAttempts.remove(pluginId);
    _restartBackoffUntil.remove(pluginId);
    notifyListeners();
  }

  void touch() => notifyListeners();

  bool _notifyScheduled = false;

  void _scheduleNotify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    Future<void>.microtask(() {
      _notifyScheduled = false;
      notifyListeners();
    });
  }
}

final ChangeNotifierProvider<PluginMetricsRegistry> pluginMetricsProvider =
    ChangeNotifierProvider((ref) => PluginMetricsRegistry());
