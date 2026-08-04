import 'dart:async';

import 'package:pyrite_ide/core/sdk/permissions.dart';

/// How a subscription drains events that arrive faster than a plugin consumes
/// them. See the T12 delivery-mode contract.
enum EventDelivery {
  /// Every event must be delivered in order.
  every,

  /// Only the newest event for the subscription is kept while one is pending.
  latest,

  /// Events inside a time window are delivered together as a list.
  batch,

  /// Delivery fires once changes stop for the debounce window.
  debounce,

  /// Delivery is capped to at most one per throttle window.
  throttle,
}

/// Per-subscription delivery configuration.
class EventDeliverySpec {
  const EventDeliverySpec({
    required this.mode,
    this.window = const Duration(milliseconds: 100),
  });

  final EventDelivery mode;

  /// Debounce/throttle/batch window. Ignored for [EventDelivery.every] and
  /// [EventDelivery.latest].
  final Duration window;

  factory EventDeliverySpec.fromJson(Map<String, dynamic> json) {
    final mode = switch (json['mode']?.toString()) {
      'latest' => EventDelivery.latest,
      'batch' => EventDelivery.batch,
      'debounce' => EventDelivery.debounce,
      'throttle' => EventDelivery.throttle,
      _ => EventDelivery.every,
    };
    final ms = json['debounceMs'] ?? json['windowMs'] ?? json['throttleMs'];
    return EventDeliverySpec(
      mode: mode,
      window: ms is num
          ? Duration(milliseconds: ms.toInt())
          : const Duration(milliseconds: 100),
    );
  }
}

/// Static description of an event topic the host can emit.
///
/// Topics declare the permission a plugin needs to subscribe, the default
/// delivery strategy, and whether the newest event is replayed to late
/// subscribers. Lifecycle-critical topics keep [EventDelivery.every] so their
/// events are never silently coalesced.
class EventTopic {
  const EventTopic({
    required this.name,
    this.requiredPermission,
    this.defaultDelivery = EventDelivery.every,
    this.replayLatest = false,
    this.defaultWindow,
  });

  final String name;

  /// `resource:action` token, or null when subscribing needs no permission.
  final String? requiredPermission;
  final EventDelivery defaultDelivery;

  /// When true, a new subscriber immediately receives the last emitted event.
  final bool replayLatest;

  /// Optional default window for debounce/throttle/batch topics.
  final Duration? defaultWindow;
}

/// Registry of the host topics plugins may subscribe to.
///
/// A topic that is not registered here cannot be subscribed to, so the event
/// surface is closed by default just like permissions.
class EventTopicRegistry {
  EventTopicRegistry([Iterable<EventTopic>? topics]) {
    for (final topic in topics ?? _defaults) {
      _topics[topic.name] = topic;
    }
  }

  final Map<String, EventTopic> _topics = {};

  EventTopic? lookup(String name) => _topics[name];
  bool isKnown(String name) => _topics.containsKey(name);
  Iterable<EventTopic> get all => _topics.values;

  void register(EventTopic topic) => _topics[topic.name] = topic;

  static const List<EventTopic> _defaults = [
    // Editor documents (payload delivered by T13; topics reserved here).
    EventTopic(
      name: 'editor.activeDocument.changed',
      requiredPermission: 'editor:read',
      defaultDelivery: EventDelivery.latest,
      replayLatest: true,
    ),
    EventTopic(
      name: 'editor.document.opened',
      requiredPermission: 'editor:read',
    ),
    EventTopic(
      name: 'editor.document.changed',
      requiredPermission: 'editor:read',
      defaultDelivery: EventDelivery.debounce,
      defaultWindow: Duration(milliseconds: 100),
    ),
    EventTopic(
      name: 'editor.document.saved',
      requiredPermission: 'editor:read',
    ),
    EventTopic(
      name: 'editor.document.closed',
      requiredPermission: 'editor:read',
    ),
    EventTopic(
      name: 'editor.document.selection.changed',
      requiredPermission: 'editor:read',
      defaultDelivery: EventDelivery.throttle,
      defaultWindow: Duration(milliseconds: 50),
    ),
    // Runtime inspection (payload delivered by T14).
    EventTopic(
      name: 'runtime.session.created',
      requiredPermission: 'runtime:inspect',
    ),
    EventTopic(
      name: 'runtime.session.ended',
      requiredPermission: 'runtime:inspect',
    ),
    EventTopic(
      name: 'runtime.session.state.changed',
      requiredPermission: 'runtime:inspect',
      replayLatest: true,
    ),
    EventTopic(
      name: 'runtime.program.started',
      requiredPermission: 'runtime:inspect',
    ),
    EventTopic(
      name: 'runtime.program.paused',
      requiredPermission: 'runtime:inspect',
    ),
    EventTopic(
      name: 'runtime.program.resumed',
      requiredPermission: 'runtime:inspect',
    ),
    EventTopic(
      name: 'runtime.program.finished',
      requiredPermission: 'runtime:inspect',
    ),
    EventTopic(
      name: 'runtime.backend.restarted',
      requiredPermission: 'runtime:inspect',
    ),
    EventTopic(
      name: 'runtime.variables.changed',
      requiredPermission: 'runtime:inspect',
      defaultDelivery: EventDelivery.latest,
    ),
    // View lifecycle (deferred from T11; no permission needed for own views).
    EventTopic(name: 'view.opened'),
    EventTopic(name: 'view.closed'),
    EventTopic(
      name: 'view.visibility.changed',
      defaultDelivery: EventDelivery.latest,
    ),
    EventTopic(name: 'view.focused'),
    // Workspace and files.
    EventTopic(
      name: 'workspace.opened',
      requiredPermission: 'file:read',
      replayLatest: true,
    ),
    EventTopic(name: 'workspace.changed', requiredPermission: 'file:read'),
    EventTopic(name: 'file.created', requiredPermission: 'file:read'),
    EventTopic(name: 'file.changed', requiredPermission: 'file:read'),
    EventTopic(name: 'file.deleted', requiredPermission: 'file:read'),
    EventTopic(name: 'file.renamed', requiredPermission: 'file:read'),
    // Devices and serial.
    EventTopic(
      name: 'device.connected',
      requiredPermission: 'serial:read',
      replayLatest: true,
    ),
    EventTopic(name: 'device.disconnected', requiredPermission: 'serial:read'),
    EventTopic(
      name: 'device.state.changed',
      requiredPermission: 'serial:read',
      defaultDelivery: EventDelivery.latest,
      replayLatest: true,
    ),
    EventTopic(
      name: 'serial.data.received',
      requiredPermission: 'serial:read',
      defaultDelivery: EventDelivery.batch,
      defaultWindow: Duration(milliseconds: 32),
    ),
    EventTopic(name: 'serial.error', requiredPermission: 'serial:read'),
    // Plugin Manifest configuration (payload produced by PluginConfigStore).
    EventTopic(
      name: 'configuration.changed',
      defaultDelivery: EventDelivery.latest,
      replayLatest: true,
    ),
  ];
}

/// One event handed to a subscription's sink.
///
/// [payloads] holds one entry for [EventDelivery.every]/[EventDelivery.latest]/
/// [EventDelivery.debounce]/[EventDelivery.throttle] and the whole coalesced
/// window for [EventDelivery.batch].
class DeliveredEvent {
  const DeliveredEvent({
    required this.topic,
    required this.subscriptionId,
    required this.payloads,
  });

  final String topic;
  final String subscriptionId;
  final List<Map<String, dynamic>> payloads;
}

/// A live subscription owned by one plugin session.
///
/// Ingested events are buffered here and released to [_sink] according to the
/// delivery spec. Buffering is bounded: once [queueLimit] pending items build
/// up, the oldest are dropped for coalescing modes and the whole subscription
/// is marked overflowed for [EventDelivery.every] so the caller can resync.
class _Subscription {
  _Subscription({
    required this.id,
    required this.pluginId,
    required this.sessionId,
    required this.generation,
    required this.topic,
    required this.spec,
    required this.filter,
    required void Function(DeliveredEvent event) sink,
    required this.queueLimit,
    Timer Function(Duration, void Function())? scheduleTimer,
  }) : _sink = sink,
       _scheduleTimer =
           scheduleTimer ?? ((duration, cb) => Timer(duration, cb));

  final String id;
  final String pluginId;
  final String sessionId;
  final int generation;
  final EventTopic topic;
  final EventDeliverySpec spec;
  final Map<String, dynamic>? filter;
  final void Function(DeliveredEvent event) _sink;
  final int queueLimit;
  final Timer Function(Duration, void Function()) _scheduleTimer;

  final List<Map<String, dynamic>> _pending = [];
  Timer? _timer;
  DateTime? _lastThrottleEmit;
  bool _closed = false;
  bool overflowed = false;

  int get pendingCount => _pending.length;

  /// True when [payload] passes the equality filter (shallow key match).
  bool matches(Map<String, dynamic> payload) {
    final f = filter;
    if (f == null || f.isEmpty) return true;
    for (final entry in f.entries) {
      if (payload[entry.key] != entry.value) return false;
    }
    return true;
  }

  void ingest(Map<String, dynamic> payload) {
    if (_closed) return;
    switch (spec.mode) {
      case EventDelivery.every:
        if (_pending.length >= queueLimit) {
          overflowed = true;
          return;
        }
        _pending.add(payload);
        _flushNow();
      case EventDelivery.latest:
        _pending
          ..clear()
          ..add(payload);
        _flushNow();
      case EventDelivery.batch:
        _pending.add(payload);
        if (_pending.length > queueLimit) {
          _pending.removeRange(0, _pending.length - queueLimit);
          overflowed = true;
        }
        _timer ??= _scheduleTimer(spec.window, _flushBuffered);
      case EventDelivery.debounce:
        _pending
          ..clear()
          ..add(payload);
        _timer?.cancel();
        _timer = _scheduleTimer(spec.window, _flushBuffered);
      case EventDelivery.throttle:
        _pending
          ..clear()
          ..add(payload);
        final last = _lastThrottleEmit;
        final now = DateTime.now();
        if (last == null || now.difference(last) >= spec.window) {
          _lastThrottleEmit = now;
          _flushBuffered();
        } else {
          _timer ??= _scheduleTimer(spec.window - now.difference(last), () {
            _lastThrottleEmit = DateTime.now();
            _flushBuffered();
          });
        }
    }
  }

  void _flushNow() {
    if (_pending.isEmpty) return;
    if (spec.mode == EventDelivery.batch) {
      final batch = List<Map<String, dynamic>>.from(_pending);
      _pending.clear();
      _emit(batch);
      return;
    }
    // every/latest deliver one payload per pending item.
    final items = List<Map<String, dynamic>>.from(_pending);
    _pending.clear();
    for (final item in items) {
      _emit([item]);
    }
  }

  void _flushBuffered() {
    _timer = null;
    if (_closed || _pending.isEmpty) return;
    if (spec.mode == EventDelivery.batch) {
      final batch = List<Map<String, dynamic>>.from(_pending);
      _pending.clear();
      _emit(batch);
    } else {
      final payload = _pending.last;
      _pending.clear();
      _emit([payload]);
    }
  }

  void _emit(List<Map<String, dynamic>> payloads) {
    if (_closed) return;
    _sink(
      DeliveredEvent(topic: topic.name, subscriptionId: id, payloads: payloads),
    );
  }

  void close() {
    _closed = true;
    _timer?.cancel();
    _timer = null;
    _pending.clear();
  }
}

/// Outcome of a subscribe attempt.
class SubscribeResult {
  const SubscribeResult._({this.subscriptionId, this.errorCode, this.message});

  const SubscribeResult.ok(String id) : this._(subscriptionId: id);
  const SubscribeResult.error(String code, String message)
    : this._(errorCode: code, message: message);

  final String? subscriptionId;
  final String? errorCode;
  final String? message;

  bool get isOk => subscriptionId != null;
}

/// Host-side event bus: plugins subscribe to topics, the host emits events, and
/// the bus schedules delivery per subscription with permission enforcement,
/// bounded queues, and session isolation.
///
/// The bus is transport-agnostic. Delivery is handed to [_deliver], which the
/// protocol layer (T12-b) wires to the owning session's transport.
class PluginEventBus {
  PluginEventBus({
    EventTopicRegistry? topics,
    required void Function(
      String pluginId,
      String sessionId,
      int generation,
      DeliveredEvent event,
    )
    deliver,
    this.queueLimit = 256,
    Timer Function(Duration, void Function())? scheduleTimer,
    this.isDeliveryPaused,
    this.onQueueDepth,
  }) : _topics = topics ?? EventTopicRegistry(),
       _deliver = deliver,
       _scheduleTimer = scheduleTimer;

  final EventTopicRegistry _topics;
  final void Function(
    String pluginId,
    String sessionId,
    int generation,
    DeliveredEvent event,
  )
  _deliver;
  final int queueLimit;
  final Timer Function(Duration, void Function())? _scheduleTimer;

  /// When true for a pluginId, events are retained for replay but not delivered.
  final bool Function(String pluginId)? isDeliveryPaused;

  /// Reports per-plugin queue depth after ingest (for metrics/high-water).
  final void Function(String pluginId, int depth)? onQueueDepth;

  final Map<String, _Subscription> _subscriptions = {};

  /// Newest event per topic, for [EventTopic.replayLatest].
  final Map<String, Map<String, dynamic>> _latest = {};

  final List<void Function(String topic, Map<String, dynamic> payload)>
  _emitListeners = [];

  int get subscriptionCount => _subscriptions.length;

  /// Registers a host-side listener that observes every successful [emit].
  ///
  /// Used by context-key producers that mirror bus topics without a plugin
  /// subscription. Returns a disposer.
  void Function() addEmitListener(
    void Function(String topic, Map<String, dynamic> payload) listener,
  ) {
    _emitListeners.add(listener);
    return () => _emitListeners.remove(listener);
  }

  EventTopic? topic(String name) => _topics.lookup(name);

  /// Registers a subscription for a plugin session.
  ///
  /// Enforces topic existence and the topic's permission against
  /// [pluginPermissions]. On success the newest retained event is replayed when
  /// the topic opts into it.
  SubscribeResult subscribe({
    required String subscriptionId,
    required String pluginId,
    required String sessionId,
    required int generation,
    required String topicName,
    required Map<String, List<String>> pluginPermissions,
    Map<String, dynamic>? filter,
    EventDeliverySpec? delivery,
  }) {
    final topic = _topics.lookup(topicName);
    if (topic == null) {
      return SubscribeResult.error(
        'unknown_topic',
        'Unknown event topic: $topicName',
      );
    }
    final required = topic.requiredPermission;
    if (required != null && !Permissions.check(pluginPermissions, required)) {
      return SubscribeResult.error(
        'permission_denied',
        'Permission denied for topic $topicName: $required',
      );
    }
    final key = _key(pluginId, sessionId, subscriptionId);
    if (_subscriptions.containsKey(key)) {
      return SubscribeResult.error(
        'duplicate_subscription',
        'Subscription already exists: $subscriptionId',
      );
    }
    final subscription = _Subscription(
      id: subscriptionId,
      pluginId: pluginId,
      sessionId: sessionId,
      generation: generation,
      topic: topic,
      spec:
          delivery ??
          EventDeliverySpec(
            mode: topic.defaultDelivery,
            window: topic.defaultWindow ?? const Duration(milliseconds: 100),
          ),
      filter: filter,
      queueLimit: queueLimit,
      scheduleTimer: _scheduleTimer,
      sink: (event) => _deliver(pluginId, sessionId, generation, event),
    );
    _subscriptions[key] = subscription;

    if (topic.replayLatest) {
      final latest = _latest[topicName];
      if (latest != null && subscription.matches(latest)) {
        subscription.ingest(latest);
      }
    }
    return SubscribeResult.ok(subscriptionId);
  }

  /// Removes one subscription. Returns true when it existed.
  bool unsubscribe({
    required String pluginId,
    required String sessionId,
    required String subscriptionId,
  }) {
    final removed = _subscriptions.remove(
      _key(pluginId, sessionId, subscriptionId),
    );
    removed?.close();
    return removed != null;
  }

  /// Emits [payload] on [topicName] to every matching subscription.
  ///
  /// Events are retained for replay when the topic opts in, regardless of
  /// whether any subscriber currently exists.
  void emit(String topicName, Map<String, dynamic> payload) {
    final topic = _topics.lookup(topicName);
    if (topic == null) return;
    if (topic.replayLatest) _latest[topicName] = payload;
    for (final listener in _emitListeners.toList(growable: false)) {
      listener(topicName, payload);
    }
    for (final subscription in _subscriptions.values) {
      if (subscription.topic.name != topicName) continue;
      if (!subscription.matches(payload)) continue;
      if (isDeliveryPaused?.call(subscription.pluginId) == true) {
        continue;
      }
      subscription.ingest(payload);
      onQueueDepth?.call(subscription.pluginId, subscription.pendingCount);
    }
  }

  /// Drops every subscription belonging to a stopped session.
  ///
  /// Called when a plugin session stops so old-session subscriptions never
  /// receive events from a later session/generation.
  void clearSession(String pluginId, String sessionId) {
    _subscriptions.removeWhere((key, subscription) {
      final match =
          subscription.pluginId == pluginId &&
          subscription.sessionId == sessionId;
      if (match) subscription.close();
      return match;
    });
  }

  /// Drops every subscription for a plugin across all sessions.
  void clearPlugin(String pluginId) {
    _subscriptions.removeWhere((key, subscription) {
      final match = subscription.pluginId == pluginId;
      if (match) subscription.close();
      return match;
    });
  }

  /// Clears retained replay state on runtime restart.
  void clearRetained() => _latest.clear();

  void disposeAll() {
    for (final subscription in _subscriptions.values) {
      subscription.close();
    }
    _subscriptions.clear();
    _latest.clear();
  }

  String _key(String pluginId, String sessionId, String subscriptionId) =>
      '$pluginId $sessionId $subscriptionId';
}
