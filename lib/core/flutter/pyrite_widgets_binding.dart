import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Defers system font notifications that arrive while Flutter is processing a
/// frame. The framework's text render objects require these notifications to
/// start during the idle phase, but some desktop engines deliver the
/// `fontsChange` platform message from a mid-frame microtask.
class PyriteWidgetsBinding extends WidgetsFlutterBinding {
  static PyriteWidgetsBinding? _current;

  static PyriteWidgetsBinding ensureInitialized() {
    return _current ??= PyriteWidgetsBinding();
  }

  @override
  Future<void> handleSystemMessage(Object systemMessage) {
    if (_isFontsChange(systemMessage) &&
        schedulerPhase != SchedulerPhase.idle) {
      final completer = Completer<void>();
      void completeWhenIdle() {
        if (schedulerPhase == SchedulerPhase.idle) {
          super
              .handleSystemMessage(systemMessage)
              .then(completer.complete, onError: completer.completeError);
          return;
        }
        addPostFrameCallback((_) {
          Future<void>.microtask(completeWhenIdle);
        });
      }

      Future<void>.microtask(completeWhenIdle);
      return completer.future;
    }
    return super.handleSystemMessage(systemMessage);
  }

  bool _isFontsChange(Object message) =>
      message is Map && message['type'] == 'fontsChange';
}
