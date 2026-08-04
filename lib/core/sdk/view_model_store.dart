import 'package:flutter/foundation.dart';
import 'package:pyrite_ide/core/sdk/plugin_perf_budget.dart';

/// Lifecycle state of a native plugin view instance.
enum ViewState { loading, ready, empty, error, disconnected }

/// Uniquely identifies one live view instance.
///
/// A plugin may open the same [viewId] more than once (e.g. two outline panels);
/// [instanceId] separates those, and [sessionId] scopes everything to one plugin
/// run so a restarted session can never patch a previous instance's model.
class ViewInstanceId {
  const ViewInstanceId({
    required this.pluginId,
    required this.sessionId,
    required this.viewId,
    required this.instanceId,
  });

  final String pluginId;
  final String sessionId;
  final String viewId;
  final String instanceId;

  String get key => '$pluginId\u0000$sessionId\u0000$viewId\u0000$instanceId';

  Map<String, dynamic> toJson() => {
    'pluginId': pluginId,
    'sessionId': sessionId,
    'viewId': viewId,
    'instanceId': instanceId,
  };

  @override
  bool operator ==(Object other) => other is ViewInstanceId && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// The kind of a single patch operation.
enum PatchOpKind { insert, update, remove, move }

/// One operation within a patch transaction. Nodes are addressed by [id]; the
/// data model is an ordered list of `{'id': ..., ...}` maps.
class PatchOp {
  const PatchOp({required this.kind, required this.id, this.index, this.data});

  final PatchOpKind kind;
  final String id;

  /// Target index for insert/move.
  final int? index;

  /// Node body for insert/update.
  final Map<String, dynamic>? data;

  factory PatchOp.fromJson(Map<String, dynamic> json) {
    final kind = switch (json['op']?.toString()) {
      'insert' => PatchOpKind.insert,
      'update' => PatchOpKind.update,
      'remove' => PatchOpKind.remove,
      'move' => PatchOpKind.move,
      _ => throw const ViewProtocolException('unknown patch op'),
    };
    final id = json['id']?.toString();
    if (id == null || id.isEmpty) {
      throw const ViewProtocolException('patch op missing id');
    }
    final rawData = json['data'];
    return PatchOp(
      kind: kind,
      id: id,
      index: json['index'] is int ? json['index'] as int : null,
      data: rawData is Map
          ? rawData.map((k, v) => MapEntry(k.toString(), v))
          : null,
    );
  }
}

/// Raised when a patch or protocol message is malformed or cannot apply.
class ViewProtocolException implements Exception {
  const ViewProtocolException(this.message);
  final String message;
  @override
  String toString() => 'ViewProtocolException: $message';
}

/// Why a patch was rejected, so the wiring layer can nack appropriately.
enum PatchRejection {
  /// baseRevision did not match the model's current revision.
  revisionGap,

  /// The instance has no snapshot yet.
  noSnapshot,

  /// The view is closed.
  closed,

  /// An operation was invalid (e.g. update of a missing node); the transaction
  /// was rolled back with no partial state.
  invalidOperation,
}

/// Result of applying a patch.
class PatchResult {
  const PatchResult._({this.revision, this.rejection, this.message});

  const PatchResult.ok(int revision) : this._(revision: revision);
  const PatchResult.rejected(PatchRejection rejection, String message)
    : this._(rejection: rejection, message: message);

  final int? revision;
  final PatchRejection? rejection;
  final String? message;

  bool get isOk => revision != null;
}

/// One view instance's versioned, ordered node model.
class ViewModel {
  ViewModel({
    required this.instance,
    required int revision,
    required List<Map<String, dynamic>> nodes,
    this.state = ViewState.ready,
  }) : _revision = revision,
       _nodes = nodes;

  final ViewInstanceId instance;
  int _revision;
  List<Map<String, dynamic>> _nodes;
  ViewState state;
  bool _closed = false;

  int get revision => _revision;
  bool get closed => _closed;
  List<Map<String, dynamic>> get nodes => List.unmodifiable(_nodes);

  /// Applies [ops] as one transaction against a working copy; only commits when
  /// every op succeeds, so a failure leaves the model untouched.
  ///
  /// [baseRevision] must equal the current revision; on success the revision is
  /// bumped to [nextRevision].
  PatchResult applyPatch({
    required int baseRevision,
    required int nextRevision,
    required List<PatchOp> ops,
  }) {
    if (_closed) {
      return const PatchResult.rejected(
        PatchRejection.closed,
        'view is closed',
      );
    }
    if (baseRevision != _revision) {
      return PatchResult.rejected(
        PatchRejection.revisionGap,
        'expected baseRevision $_revision, got $baseRevision',
      );
    }

    final working = [
      for (final node in _nodes) Map<String, dynamic>.from(node),
    ];
    for (final op in ops) {
      final error = _applyOp(working, op);
      if (error != null) {
        // Roll back: the working copy is discarded, model is unchanged.
        return PatchResult.rejected(PatchRejection.invalidOperation, error);
      }
    }
    if (working.length > PluginPerfBudget.maxSnapshotNodes) {
      return const PatchResult.rejected(
        PatchRejection.invalidOperation,
        'view node budget exceeded',
      );
    }

    _nodes = working;
    _revision = nextRevision;
    state = working.isEmpty ? ViewState.empty : ViewState.ready;
    return PatchResult.ok(_revision);
  }

  /// Applies one op to [working], returning an error string on failure.
  String? _applyOp(List<Map<String, dynamic>> working, PatchOp op) {
    int indexOf(String id) => working.indexWhere((n) => n['id'] == id);
    switch (op.kind) {
      case PatchOpKind.insert:
        if (indexOf(op.id) != -1) return 'insert of existing id ${op.id}';
        if (op.data == null) return 'insert ${op.id} missing data';
        final node = {...op.data!, 'id': op.id};
        final at = op.index;
        if (at == null || at >= working.length) {
          working.add(node);
        } else if (at < 0) {
          return 'insert ${op.id} negative index';
        } else {
          working.insert(at, node);
        }
        return null;
      case PatchOpKind.update:
        final at = indexOf(op.id);
        if (at == -1) return 'update of missing id ${op.id}';
        if (op.data == null) return 'update ${op.id} missing data';
        working[at] = {...working[at], ...op.data!, 'id': op.id};
        return null;
      case PatchOpKind.remove:
        final at = indexOf(op.id);
        if (at == -1) return 'remove of missing id ${op.id}';
        working.removeAt(at);
        return null;
      case PatchOpKind.move:
        final from = indexOf(op.id);
        if (from == -1) return 'move of missing id ${op.id}';
        final to = op.index;
        if (to == null || to < 0 || to >= working.length) {
          return 'move ${op.id} index out of range';
        }
        final node = working.removeAt(from);
        working.insert(to, node);
        return null;
    }
  }

  void close() {
    _closed = true;
    state = ViewState.disconnected;
  }

  Map<String, dynamic> toSnapshot() => {
    'instance': instance.toJson(),
    'revision': _revision,
    'state': state.name,
    'nodes': nodes,
  };
}

/// Holds the view models for all open instances and applies the snapshot/patch
/// protocol against them.
///
/// Transport-agnostic: the wiring layer (T15-b) feeds decoded messages in and
/// turns the results into ack/nack/resync frames.
///
/// Observable per instance: the render surface listens on one instance's
/// [Listenable] rather than the whole store, so a patch to one view never
/// rebuilds another.
class ViewModelStore {
  final Map<String, ViewModel> _models = {};
  final Map<String, ChangeNotifier> _notifiers = {};

  int get length => _models.length;

  Iterable<ViewInstanceId> instancesForPlugin(String pluginId) => _models.values
      .where((model) => model.instance.pluginId == pluginId)
      .map((model) => model.instance);

  ViewModel? model(ViewInstanceId instance) => _models[instance.key];

  /// A listenable that fires whenever [instance]'s model changes.
  ///
  /// Created on demand so a surface can subscribe before the first snapshot
  /// arrives, and kept across close/reopen of the same instance key.
  Listenable listenableFor(ViewInstanceId instance) =>
      _notifiers[instance.key] ??= ChangeNotifier();

  void _notify(ViewInstanceId instance) {
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    _notifiers[instance.key]?.notifyListeners();
  }

  /// Installs a fresh model from a snapshot, replacing any prior instance.
  ViewModel installSnapshot({
    required ViewInstanceId instance,
    required int revision,
    required List<Map<String, dynamic>> nodes,
  }) {
    final model = ViewModel(
      instance: instance,
      revision: revision,
      nodes: [for (final n in nodes) Map<String, dynamic>.from(n)],
      state: nodes.isEmpty ? ViewState.empty : ViewState.ready,
    );
    _models[instance.key] = model;
    _notify(instance);
    return model;
  }

  /// Applies a patch to an existing instance. Returns a [noSnapshot] rejection
  /// when the instance was never snapshotted.
  PatchResult applyPatch({
    required ViewInstanceId instance,
    required int baseRevision,
    required int nextRevision,
    required List<PatchOp> ops,
  }) {
    final model = _models[instance.key];
    if (model == null) {
      return const PatchResult.rejected(
        PatchRejection.noSnapshot,
        'no snapshot for instance',
      );
    }
    final result = model.applyPatch(
      baseRevision: baseRevision,
      nextRevision: nextRevision,
      ops: ops,
    );
    // Only a committed patch changed anything; a rejected one rolled back.
    if (result.isOk) _notify(instance);
    return result;
  }

  void setState(ViewInstanceId instance, ViewState state) {
    final model = _models[instance.key];
    if (model == null || model.state == state) return;
    model.state = state;
    _notify(instance);
  }

  /// Closes and removes an instance; later patches to it are rejected.
  void close(ViewInstanceId instance) {
    final model = _models.remove(instance.key);
    if (model == null) return;
    model.close();
    _notify(instance);
  }

  /// Drops every instance belonging to a stopped plugin session.
  void clearSession(String pluginId, String sessionId) {
    final dropped = <ViewInstanceId>[];
    _models.removeWhere((key, model) {
      final match =
          model.instance.pluginId == pluginId &&
          model.instance.sessionId == sessionId;
      if (match) {
        model.close();
        dropped.add(model.instance);
      }
      return match;
    });
    for (final instance in dropped) {
      _notify(instance);
    }
  }

  void clearPlugin(String pluginId) {
    final dropped = <ViewInstanceId>[];
    _models.removeWhere((key, model) {
      final match = model.instance.pluginId == pluginId;
      if (match) {
        model.close();
        dropped.add(model.instance);
      }
      return match;
    });
    for (final instance in dropped) {
      _notify(instance);
    }
  }

  void clear() {
    final dropped = _models.values.map((model) => model.instance).toList();
    _models.clear();
    for (final instance in dropped) {
      _notify(instance);
    }
  }

  /// Releases the notifiers; call when the store itself goes away.
  void disposeNotifiers() {
    for (final notifier in _notifiers.values) {
      notifier.dispose();
    }
    _notifiers.clear();
  }
}
