import 'dart:async';

import 'package:code_forge/code_forge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers [EditorModifierKeys], the fix for alt-click staying permanently on.
///
/// `HardwareKeyboard.instance.isAltPressed` answers from a framework-side cache
/// that only sheds entries on a key-up. When that key-up is lost - a modifier
/// held while the window loses focus, Alt+Tab, a combination swallowed by the
/// system menu - Alt reads as held for the rest of the session. Pointer events
/// carry no modifier bits of their own, so every later click inherits the stale
/// reading and silently becomes an alt-click.
///
/// The tracker repairs this by consulting the engine, but only when the engine's
/// answer is at least as new as the newest Alt key event. These tests pin both
/// halves of that rule: a lost key-up must be recoverable, and a genuine
/// alt-click must keep working while a channel round-trip is in flight.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter/keyboard');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Map<int, int>? engineState;
  late bool channelAvailable;

  /// Delivers a key event the way the editor surface does, so the tracker
  /// stamps its generation and re-reads the engine exactly as in production.
  void deliver(EditorModifierKeys keys, KeyEvent event) =>
      keys.observeKeyEvent(event);

  KeyEvent altDown() => const KeyDownEvent(
    physicalKey: PhysicalKeyboardKey.altLeft,
    logicalKey: LogicalKeyboardKey.altLeft,
    timeStamp: Duration.zero,
  );

  KeyEvent altUp() => const KeyUpEvent(
    physicalKey: PhysicalKeyboardKey.altLeft,
    logicalKey: LogicalKeyboardKey.altLeft,
    timeStamp: Duration.zero,
  );

  Map<int, int> pressed(
    PhysicalKeyboardKey physical,
    LogicalKeyboardKey logical,
  ) => <int, int>{physical.usbHidUsage: logical.keyId};

  /// The engine's standing answer, for the common case where nothing is in
  /// flight and the reply can be immediate.
  void answerWith(Map<int, int>? state) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (!channelAvailable) throw MissingPluginException();
      if (call.method != 'getKeyboardState') {
        throw PlatformException(code: 'unknown');
      }
      return state;
    });
  }

  setUp(() async {
    engineState = <int, int>{};
    channelAvailable = true;
    answerWith(engineState);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    // The shared tracker is a process-wide singleton, so each test starts from a
    // clean slate rather than inheriting the previous test's generations.
    editorModifierKeys
      ..invalidate()
      ..resetForTesting();
  });

  test('reports Alt as released when the engine holds nothing', () async {
    final keys = EditorModifierKeys();
    answerWith(<int, int>{});

    expect(await keys.sync(), isFalse);
    expect(keys.isAltPressed, isFalse);
  });

  test('reports Alt as held when the engine says it is held', () async {
    final keys = EditorModifierKeys();
    answerWith(
      pressed(PhysicalKeyboardKey.altLeft, LogicalKeyboardKey.altLeft),
    );

    expect(await keys.sync(), isTrue);
    expect(keys.isAltPressed, isTrue);
  });

  test('ignores non-Alt keys when deciding whether Alt is held', () async {
    final keys = EditorModifierKeys();
    answerWith(
      pressed(PhysicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftLeft),
    );

    expect(await keys.sync(), isFalse);
  });

  test('a null engine map is treated as no modifiers held', () async {
    final keys = EditorModifierKeys();
    answerWith(null);

    expect(await keys.sync(), isFalse);
  });

  test(
    'an engine-confirmed release overrides a stale framework cache',
    () async {
      final keys = EditorModifierKeys();

      // The framework cache claims Alt is held...
      await simulateKeyDownEvent(
        LogicalKeyboardKey.altLeft,
        platform: 'windows',
      );
      addTearDown(
        () =>
            simulateKeyUpEvent(LogicalKeyboardKey.altLeft, platform: 'windows'),
      );
      expect(HardwareKeyboard.instance.isAltPressed, isTrue);

      // ...while the engine knows it was released long ago.
      answerWith(<int, int>{});
      expect(await keys.sync(), isFalse);

      // The stale cache still says Alt is down, but the editor reads the
      // engine-confirmed value, so alt-click is off again. This is the exact
      // state that used to trap the user in permanent multi-cursor mode.
      expect(keys.isAltPressed, isFalse);
      expect(HardwareKeyboard.instance.isAltPressed, isTrue);
    },
  );

  test(
    'an engine answer taken before the newest key-down is ignored',
    () async {
      // The channel round-trip is slow enough that a real Alt+Click routinely
      // lands while a query is still in flight. Blindly trusting that answer
      // would drop genuine alt-clicks - the mirror image of the original bug -
      // so an answer older than the newest Alt key event must not count.
      final firstReply = Completer<void>();
      final secondReply = Completer<void>();
      var call = 0;
      messenger.setMockMethodCallHandler(channel, (call2) async {
        if (call2.method != 'getKeyboardState') {
          throw PlatformException(code: 'unknown');
        }
        final isFirst = call++ == 0;
        await (isFirst ? firstReply.future : secondReply.future);
        // The first reply describes a moment before Alt was pressed and so
        // reports nothing held; the second describes the present, where the
        // user really is holding Alt.
        return isFirst
            ? <int, int>{}
            : pressed(PhysicalKeyboardKey.altLeft, LogicalKeyboardKey.altLeft);
      });

      final keys = EditorModifierKeys();
      // A query is issued while nothing is held, and parks in flight.
      final pending = keys.sync();
      await pumpEventQueue();

      // Alt goes down and the user alt-clicks before that query returns.
      await simulateKeyDownEvent(
        LogicalKeyboardKey.altLeft,
        platform: 'windows',
      );
      addTearDown(
        () =>
            simulateKeyUpEvent(LogicalKeyboardKey.altLeft, platform: 'windows'),
      );
      deliver(keys, altDown());
      expect(keys.isAltPressed, isTrue);

      // The stale reply lands claiming Alt is up. It was requested before the
      // key-down, so it must not veto the fresh one.
      firstReply.complete();
      await pending;
      await pumpEventQueue();
      expect(keys.isAltPressed, isTrue);

      // The re-read taken after the key-down confirms Alt really is held.
      secondReply.complete();
      await pumpEventQueue();
      await pumpEventQueue();
      expect(keys.isAltPressed, isTrue);
    },
  );

  test(
    'a key-up we received beats an engine answer taken while it was held',
    () async {
      final keys = EditorModifierKeys();
      answerWith(
        pressed(PhysicalKeyboardKey.altLeft, LogicalKeyboardKey.altLeft),
      );
      expect(await keys.sync(), isTrue);

      // The user lets go; we hear about it. Alt cannot still be held, so the
      // engine's older "held" answer must not resurrect multi-cursor mode.
      deliver(keys, altUp());
      expect(keys.isAltPressed, isFalse);
    },
  );

  test(
    'an engine answer taken after a key-down detects a lost key-up',
    () async {
      final keys = EditorModifierKeys();

      // Alt is held, the window loses focus, and the key-up never arrives. The
      // framework cache stays wrong; the engine is re-read once focus returns
      // and is the only evidence that can overturn the cache.
      await simulateKeyDownEvent(
        LogicalKeyboardKey.altLeft,
        platform: 'windows',
      );
      addTearDown(
        () =>
            simulateKeyUpEvent(LogicalKeyboardKey.altLeft, platform: 'windows'),
      );
      deliver(keys, altDown());
      expect(keys.isAltPressed, isTrue);

      // The user let go while the window was in the background, so the engine
      // now reports Alt released while the framework cache still disagrees.
      answerWith(<int, int>{});
      keys.onWindowFocus();
      await pumpEventQueue();
      await pumpEventQueue();

      expect(keys.isAltPressed, isFalse);
      // The framework cache never recovered on its own, which is why the
      // engine had to be consulted at all.
      expect(HardwareKeyboard.instance.isAltPressed, isTrue);
    },
  );

  test('falls back to the framework cache before the engine has answered', () {
    final keys = EditorModifierKeys();

    expect(keys.hasEngineState, isFalse);
    // With no engine answer yet the framework reading is used, so behaviour is
    // unchanged on platforms where the channel is unavailable.
    expect(keys.isAltPressed, HardwareKeyboard.instance.isAltPressed);
  });

  test(
    'stops querying once the engine reports the channel unavailable',
    () async {
      final keys = EditorModifierKeys();
      channelAvailable = false;

      expect(await keys.sync(), isNull);
      // A second call short-circuits rather than throwing again.
      expect(await keys.sync(), isNull);
    },
  );

  test(
    'invalidate forgets the cached answer so the engine is re-read',
    () async {
      final keys = EditorModifierKeys();
      answerWith(
        pressed(PhysicalKeyboardKey.altLeft, LogicalKeyboardKey.altLeft),
      );
      expect(await keys.sync(), isTrue);

      keys.invalidate();
      expect(keys.hasEngineState, isFalse);

      answerWith(<int, int>{});
      expect(await keys.sync(), isFalse);
    },
  );

  test('onWindowFocus drops the pre-blur answer synchronously', () async {
    final keys = EditorModifierKeys();
    answerWith(
      pressed(PhysicalKeyboardKey.altLeft, LogicalKeyboardKey.altLeft),
    );
    expect(await keys.sync(), isTrue);
    expect(keys.isAltPressed, isTrue);

    // Focus leaves with Alt still held and comes back after the user let go -
    // a key-up the framework never saw. The click that follows the focus
    // event cannot wait on a channel round-trip, so the abandoned answer has
    // to be discarded the moment focus returns rather than when the re-read
    // happens to land.
    answerWith(<int, int>{});
    keys.onWindowFocus();
    expect(keys.hasEngineState, isFalse);

    await pumpEventQueue();
    await pumpEventQueue();
    expect(keys.isAltPressed, isFalse);
  });

  test(
    'onWindowBlur re-reads the engine rather than trusting the pre-blur answer',
    () async {
      final keys = EditorModifierKeys();
      answerWith(<int, int>{});
      expect(await keys.sync(), isFalse);

      // Alt is held as focus leaves. The refresh is fire-and-forget, so the
      // test waits for it; what matters is that the hook consulted the engine
      // instead of leaving the old answer in place.
      answerWith(
        pressed(PhysicalKeyboardKey.altLeft, LogicalKeyboardKey.altLeft),
      );
      keys.onWindowBlur();
      await pumpEventQueue();
      expect(keys.isAltPressed, isTrue);
    },
  );

  group('focus loss while Alt is held', () {
    // The engine is no help here. It tracks the keys delivered to this window,
    // so a key-up that lands while the window is in the background is lost for
    // the engine exactly as it is for the framework, and `getKeyboardState`
    // goes on reporting Alt as held. On Windows there is additionally no focus
    // callback at all - window_manager never handles WM_ACTIVATE and the engine
    // has no lifecycle channel - so the only witness is the platform.
    //
    // The engine mock therefore reports Alt as held throughout: that is the
    // real state, and it is exactly what makes the case unrecoverable from the
    // engine alone.

    setUp(() {
      answerWith(
        pressed(PhysicalKeyboardKey.altLeft, LogicalKeyboardKey.altLeft),
      );
    });

    test('a focus loss the probe reports retires the lost key-up', () async {
      var focused = true;
      final keys = EditorModifierKeys()..windowFocusProbe = () async => focused;
      addTearDown(keys.dispose);

      // Alt goes down and the window is still focused: a genuine alt-click, and
      // it has to keep working.
      keys.observeKeyEvent(altDown());
      expect(keys.isAltPressed, isTrue);

      // Alt+Tab away, the user lets go of Alt over the other app, Alt+Tab back
      // and clicks. Nothing this process can see ever recorded the key-up.
      focused = false;
      await keys.probeWindowFocusNow();
      expect(keys.isAltPressed, isFalse);
    });

    test('pressing Alt again makes alt-click work once more', () async {
      var focused = true;
      final keys = EditorModifierKeys()..windowFocusProbe = () async => focused;
      addTearDown(keys.dispose);

      keys.observeKeyEvent(altDown());
      focused = false;
      await keys.probeWindowFocusNow();
      expect(keys.isAltPressed, isFalse);

      // A real key event is genuine evidence, so it outranks the suspicion.
      focused = true;
      keys.observeKeyEvent(altDown());
      expect(keys.isAltPressed, isTrue);
    });

    test('a focused window leaves the modifier alone', () async {
      final keys = EditorModifierKeys()..windowFocusProbe = () async => true;
      addTearDown(keys.dispose);

      keys.observeKeyEvent(altDown());
      await keys.probeWindowFocusNow();
      expect(keys.isAltPressed, isTrue);
    });

    test('a probe that throws is dropped instead of retried forever', () async {
      final keys = EditorModifierKeys()
        ..windowFocusProbe = () async => throw UnimplementedError();
      addTearDown(keys.dispose);

      keys.observeKeyEvent(altDown());
      await keys.probeWindowFocusNow();

      expect(keys.windowFocusProbe, isNull);
      // The tracker keeps its previous behaviour rather than giving up on Alt
      // entirely: a genuine alt-click still registers.
      expect(keys.isAltPressed, isTrue);
    });

    test('the watch stays idle when no probe is supplied', () async {
      final keys = EditorModifierKeys();
      addTearDown(keys.dispose);

      // The polling only exists to serve the host probe, so without one there
      // is nothing to poll and nothing to break.
      keys.observeKeyEvent(altDown());
      await pumpEventQueue();
      expect(keys.isAltPressed, isTrue);
    });
  });

  test('an answer requested before invalidate is discarded', () async {
    // A query already in flight when the focus hook invalidates must not
    // resurrect the answer it was carrying. Without this the drop in
    // `onWindowFocus` is undone the moment the older reply lands, which is the
    // one window where a stale "Alt is held" gets adopted.
    final gate = Completer<Map<int, int>?>();
    messenger.setMockMethodCallHandler(channel, (_) => gate.future);
    final keys = EditorModifierKeys();
    addTearDown(keys.dispose);

    keys.observeKeyEvent(altDown());
    keys.invalidate();

    gate.complete(<int, int>{});
    await pumpEventQueue();
    await pumpEventQueue();

    expect(keys.hasEngineState, isFalse);
  });
}
