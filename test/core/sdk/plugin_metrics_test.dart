import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/plugin_metrics.dart';

void main() {
  test('consecutive failures pause delivery and resume clears the circuit', () {
    final metrics = PluginSessionMetrics(
      pluginId: 'fixture',
      sessionId: 'session',
      generation: 1,
    );

    for (var index = 0; index < 8; index++) {
      metrics.recordError('failure $index');
    }

    expect(metrics.eventDeliveryPaused, isTrue);
    expect(metrics.consecutiveFailures, 8);
    metrics.resumeEventDelivery();
    expect(metrics.eventDeliveryPaused, isFalse);
    expect(metrics.consecutiveFailures, 0);
  });

  test('restart failures use capped exponential backoff', () {
    final registry = PluginMetricsRegistry();

    registry.noteRestartFailure('fixture');
    final first = registry.restartBackoffRemaining('fixture');
    expect(first, isNotNull);
    expect(first!.inMilliseconds, lessThanOrEqualTo(1000));

    for (var index = 0; index < 10; index++) {
      registry.noteRestartFailure('fixture');
    }
    final capped = registry.restartBackoffRemaining('fixture');
    expect(capped, isNotNull);
    expect(capped!.inSeconds, lessThanOrEqualTo(60));

    registry.noteRestartSuccess('fixture');
    expect(registry.restartBackoffRemaining('fixture'), isNull);
  });
}
