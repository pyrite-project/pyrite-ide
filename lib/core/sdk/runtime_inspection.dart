/// Runtime inspection topics emitted onto the plugin event bus.
abstract class RuntimeTopics {
  static const String sessionCreated = 'runtime.session.created';
  static const String sessionEnded = 'runtime.session.ended';
  static const String sessionStateChanged = 'runtime.session.state.changed';
  static const String programStarted = 'runtime.program.started';
  static const String programPaused = 'runtime.program.paused';
  static const String programResumed = 'runtime.program.resumed';
  static const String programFinished = 'runtime.program.finished';
  static const String backendRestarted = 'runtime.backend.restarted';
  static const String variablesChanged = 'runtime.variables.changed';
}

/// Execution state of the program on a runtime backend.
enum RuntimeProgramState { idle, running, paused, finished }

/// Whether a backend can serve safe variable inspection right now.
enum RuntimeCapability {
  /// Inspection is supported and safe.
  available,

  /// The backend cannot inspect safely (e.g. no cooperative debug hook); the
  /// service reports this instead of interrupting the program.
  unavailable,
}

/// Caps applied to reprs and container previews so a single value can't flood
/// the transport.
class RuntimeLimits {
  const RuntimeLimits({this.maxRepr = 1024, this.maxChildrenPerPage = 200});

  final int maxRepr;
  final int maxChildrenPerPage;

  String clampRepr(String repr) =>
      repr.length <= maxRepr ? repr : '${repr.substring(0, maxRepr)}…';

  int clampCount(int requested) => requested <= 0
      ? maxChildrenPerPage
      : requested.clamp(1, maxChildrenPerPage);
}

/// An object reference bound to one runtime session and generation.
///
/// Encoded as `runtime-<session>:generation-<generation>:obj-<id>` so a stale
/// reference (from a previous generation, e.g. after a backend restart) is
/// detectable without a lookup table.
class RuntimeReference {
  const RuntimeReference({
    required this.sessionId,
    required this.generation,
    required this.objectId,
  });

  final String sessionId;
  final int generation;
  final String objectId;

  String encode() => 'runtime-$sessionId:generation-$generation:obj-$objectId';

  static RuntimeReference? tryParse(String token) {
    final match = RegExp(
      r'^runtime-(.+):generation-(\d+):obj-(.+)$',
    ).firstMatch(token);
    if (match == null) return null;
    return RuntimeReference(
      sessionId: match.group(1)!,
      generation: int.parse(match.group(2)!),
      objectId: match.group(3)!,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RuntimeReference &&
      other.sessionId == sessionId &&
      other.generation == generation &&
      other.objectId == objectId;

  @override
  int get hashCode => Object.hash(sessionId, generation, objectId);
}

/// A live runtime session (one connected device/backend lifetime).
class RuntimeSession {
  RuntimeSession({
    required this.sessionId,
    required this.generation,
    this.capability = RuntimeCapability.available,
    this.programState = RuntimeProgramState.idle,
  });

  final String sessionId;
  int generation;
  RuntimeCapability capability;
  RuntimeProgramState programState;

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'generation': generation,
    'capability': capability.name,
    'programState': programState.name,
  };
}

/// Result of validating an incoming reference token against the live session.
enum ReferenceStatus { valid, stale, malformed }

/// Tracks runtime sessions, mints/validates object references, and emits the
/// runtime lifecycle events onto the plugin event bus.
///
/// This is Flutter-free so it can be unit-tested with no device. The wiring
/// layer (T14-b) drives it from the real serial/device backend and asks it to
/// validate references before forwarding an inspection query.
class RuntimeInspectionService {
  RuntimeInspectionService({
    required void Function(String topic, Map<String, dynamic> payload) emit,
    this.limits = const RuntimeLimits(),
  }) : _emit = emit;

  final void Function(String topic, Map<String, dynamic> payload) _emit;
  final RuntimeLimits limits;

  final Map<String, RuntimeSession> _sessions = {};

  Iterable<RuntimeSession> get sessions => _sessions.values;
  RuntimeSession? session(String sessionId) => _sessions[sessionId];

  /// Registers a newly connected backend session and announces it.
  RuntimeSession createSession(
    String sessionId, {
    RuntimeCapability capability = RuntimeCapability.available,
  }) {
    final existing = _sessions[sessionId];
    final generation = existing == null ? 1 : existing.generation;
    final session = RuntimeSession(
      sessionId: sessionId,
      generation: generation,
      capability: capability,
    );
    _sessions[sessionId] = session;
    _emit(RuntimeTopics.sessionCreated, session.toJson());
    return session;
  }

  /// Bumps the session's generation so every prior reference becomes stale, and
  /// announces the restart. Used on hardware reset / reconnect / soft reboot.
  void restartBackend(String sessionId) {
    final session = _sessions[sessionId];
    if (session == null) return;
    session.generation += 1;
    session.programState = RuntimeProgramState.idle;
    _emit(RuntimeTopics.backendRestarted, session.toJson());
    _emit(RuntimeTopics.sessionStateChanged, session.toJson());
  }

  void setCapability(String sessionId, RuntimeCapability capability) {
    final session = _sessions[sessionId];
    if (session == null || session.capability == capability) return;
    session.capability = capability;
    _emit(RuntimeTopics.sessionStateChanged, session.toJson());
  }

  /// Transitions the program state and emits the matching lifecycle event.
  void setProgramState(String sessionId, RuntimeProgramState state) {
    final session = _sessions[sessionId];
    if (session == null || session.programState == state) return;
    session.programState = state;
    switch (state) {
      case RuntimeProgramState.running:
        _emit(RuntimeTopics.programStarted, session.toJson());
      case RuntimeProgramState.paused:
        _emit(RuntimeTopics.programPaused, session.toJson());
      case RuntimeProgramState.finished:
        _emit(RuntimeTopics.programFinished, session.toJson());
      case RuntimeProgramState.idle:
        break;
    }
    _emit(RuntimeTopics.sessionStateChanged, session.toJson());
  }

  /// Marks a resume (paused -> running) distinctly from a fresh start.
  void resumeProgram(String sessionId) {
    final session = _sessions[sessionId];
    if (session == null || session.programState != RuntimeProgramState.paused) {
      return;
    }
    session.programState = RuntimeProgramState.running;
    _emit(RuntimeTopics.programResumed, session.toJson());
    _emit(RuntimeTopics.sessionStateChanged, session.toJson());
  }

  /// Announces that a session's variables changed (e.g. a debug step landed),
  /// so plugins can refresh without polling.
  void notifyVariablesChanged(String sessionId) {
    final session = _sessions[sessionId];
    if (session == null) return;
    _emit(RuntimeTopics.variablesChanged, {'sessionId': sessionId});
  }

  /// Mints a reference for [objectId] in the current generation of [sessionId].
  RuntimeReference? reference(String sessionId, String objectId) {
    final session = _sessions[sessionId];
    if (session == null) return null;
    return RuntimeReference(
      sessionId: sessionId,
      generation: session.generation,
      objectId: objectId,
    );
  }

  /// Checks whether [token] is valid for the current session generation.
  ReferenceStatus validate(String token) {
    final reference = RuntimeReference.tryParse(token);
    if (reference == null) return ReferenceStatus.malformed;
    final session = _sessions[reference.sessionId];
    if (session == null || reference.generation != session.generation) {
      return ReferenceStatus.stale;
    }
    return ReferenceStatus.valid;
  }

  /// Ends [sessionId], removing it from the live set and announcing it so
  /// plugins can drop references and fall back to a disconnected state.
  void endSession(String sessionId) {
    final session = _sessions.remove(sessionId);
    if (session == null) return;
    _emit(RuntimeTopics.sessionEnded, session.toJson());
  }

  void clear() => _sessions.clear();
}
