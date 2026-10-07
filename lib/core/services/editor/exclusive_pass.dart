import 'dart:async';

/// Runs async passes one at a time.
///
/// Used where several independent triggers can ask for the same work while an
/// earlier request is still running -- a window-focus check that fires several
/// times, for instance. Without serialization each request starts its own pass,
/// sees the same unresolved state, and opens its own prompt, so the prompts
/// stack up and the user has to dismiss them one at a time.
class ExclusivePass {
  Future<void> _tail = Future<void>.value();
  int _pending = 0;

  /// Whether a pass has been accepted and has not finished yet.
  ///
  /// Counts passes that are queued as well as the one running, so a caller
  /// asking between the two -- while the accepted pass is still waiting to be
  /// scheduled -- is treated the same as one asking mid-pass. That gap is a
  /// single microtask, but a trigger firing in it would otherwise slip past
  /// [runIfIdle] and queue a duplicate behind a request already on its way.
  bool get isBusy => _pending > 0;

  /// Runs [action] once every pass queued before it has finished.
  Future<T> run<T>(Future<T> Function() action) {
    final previous = _tail;
    final completer = Completer<T>();
    _pending++;
    _tail = () async {
      // A pass that threw must not wedge everything queued behind it.
      try {
        await previous;
      } catch (_) {}
      try {
        completer.complete(await action());
      } catch (error, stack) {
        completer.completeError(error, stack);
      } finally {
        _pending--;
      }
    }();
    return completer.future;
  }

  /// Like [run], but for a trigger whose request is worth nothing once an
  /// earlier one is under way: a pass already in flight is looking at the same
  /// state, or is about to, so this one is dropped instead of queued behind it.
  ///
  /// Completes with null when the request was dropped.
  Future<T?> runIfIdle<T>(Future<T> Function() action) async {
    if (isBusy) return null;
    return run(action);
  }
}
