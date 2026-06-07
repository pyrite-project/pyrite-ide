import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ReplMutex {
  bool _locked = false;
  final List<Completer<void>> _waitQueue = [];

  Future<T> runExclusive<T>(Future<T> Function() action) async {
    while (_locked) {
      final completer = Completer<void>();
      _waitQueue.add(completer);
      await completer.future;
    }
    _locked = true;
    try {
      return await action();
    } finally {
      _locked = false;
      if (_waitQueue.isNotEmpty) {
        final next = _waitQueue.removeAt(0);
        next.complete();
      }
    }
  }
}

final replMutexProvider = Provider<ReplMutex>((ref) => ReplMutex());
