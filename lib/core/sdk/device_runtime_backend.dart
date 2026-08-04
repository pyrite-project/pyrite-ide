import 'dart:convert';

import 'package:pyrite_ide/core/sdk/api/runtime_api.dart';
import 'package:pyrite_ide/core/sdk/runtime_inspection.dart';

/// Running-operation id used by runtime inspection transactions.
///
/// Distinct from `code-exec` so the program-state gate — which watches the
/// operation list for any *other* serial transaction — never flags its own
/// inspection query as a device-busy state.
const runtimeInspectionOperationId = 'runtime-inspect';

/// Runs one inspection script on the connected device and returns stdout.
typedef DeviceScriptRunner = Future<String> Function(String script);

/// Returns true while another serial transaction is active, in which case
/// inspection must decline rather than risk interrupting it.
typedef RuntimeBusyCheck = bool Function();

/// Marker line prefix used to extract the JSON result from device stdout.
const _runtimeMarker = '__PYRITE_RUNTIME__';

/// Matches the plugin's `MAX_REPR_CHARS` cap so a single value can't flood the
/// transport.
const _maxReprChars = 2000;

/// Serves runtime inspection queries from the real MicroPython REPL.
///
/// Design notes:
/// * Every query runs through the shared REPL transaction machinery
///   ([DeviceScriptRunner], defaulting to `runPythonOnDevice`) under its own
///   running-operation id. `replMutex` therefore serializes inspection against
///   program runs and file transfers.
/// * The busy gate is consulted *before* any bytes reach the serial port. When
///   another transaction is active (a running program, a transfer, ...) every
///   query returns null so the API reports `unavailable` — inspection never
///   interrupts the device.
/// * The device keeps a `__pyrite_refs` dict plus a `__pyrite_seq` counter in
///   its globals. REPL transactions do not reset the interpreter, so references
///   minted by a `variables` query stay valid for later `children` /
///   `objectInfo` queries. The registry is reset on the next full
///   (`start == 0`) globals refresh, mirroring the plugin clearing its
///   references on refresh.
/// * The device script returns short registry keys; this class mints the full
///   reference tokens via [RuntimeInspectionService.reference] so they carry
///   the session's current generation and become stale on backend restarts.
class DeviceRuntimeBackend implements RuntimeBackend {
  DeviceRuntimeBackend({
    required RuntimeInspectionService service,
    required DeviceScriptRunner runScript,
    required RuntimeBusyCheck isBusy,
    int maxRepr = _maxReprChars,
  }) : _service = service,
       _runScript = runScript,
       _isBusy = isBusy,
       _maxRepr = maxRepr;

  final RuntimeInspectionService _service;
  final DeviceScriptRunner _runScript;
  final RuntimeBusyCheck _isBusy;
  final int _maxRepr;

  static const String globalsScopeId = 'globals';

  @override
  Future<RuntimePage?> scopes(String sessionId) async {
    if (_isBusy()) return null;
    return const RuntimePage(
      items: [
        {'id': 'globals', 'name': 'globals', 'type': 'scope'},
      ],
      total: 1,
    );
  }

  @override
  Future<RuntimePage?> variables(
    String sessionId,
    String scopeId, {
    int start = 0,
    int count = 0,
  }) async {
    if (_isBusy()) return null;
    if (scopeId != globalsScopeId) {
      return RuntimePage(items: const [], total: 0, start: start);
    }
    return _readPage(
      () => _runScript(_globalsPageScript(start, count)),
      sessionId,
      start,
    );
  }

  @override
  Future<RuntimePage?> children(
    String reference, {
    int start = 0,
    int count = 0,
  }) async {
    if (_isBusy()) return null;
    final parsed = RuntimeReference.tryParse(reference);
    if (parsed == null) return null;
    return _readPage(
      () => _runScript(_childrenPageScript(parsed.objectId, start, count)),
      parsed.sessionId,
      start,
    );
  }

  @override
  Future<Map<String, dynamic>?> objectInfo(String reference) async {
    if (_isBusy()) return null;
    final parsed = RuntimeReference.tryParse(reference);
    if (parsed == null) return null;
    try {
      final raw = await _runScript(_objectInfoScript(parsed.objectId));
      final decoded = _decodeMarkerJson(raw);
      if (decoded == null) return null;
      final attributes = <Map<String, dynamic>>[];
      for (final e in (decoded['attributes'] as List?) ?? const []) {
        attributes.add(_withMintedReference(e as Map, parsed.sessionId));
      }
      return {
        'reference': reference,
        'type': decoded['type'],
        'repr': decoded['repr'],
        'attributes': attributes,
      };
    } catch (_) {
      return null;
    }
  }

  Future<RuntimePage?> _readPage(
    Future<String> Function() run,
    String sessionId,
    int start,
  ) async {
    try {
      final raw = await run();
      final decoded = _decodeMarkerJson(raw);
      if (decoded == null) return null;
      final items = <Map<String, dynamic>>[];
      for (final e in (decoded['items'] as List?) ?? const []) {
        items.add(_withMintedReference(e as Map, sessionId));
      }
      final total = decoded['total'] as int?;
      return RuntimePage(items: items, total: total, start: start);
    } catch (_) {
      return null;
    }
  }

  /// Replaces the device-side registry key in [item]'s `reference` slot with a
  /// full, generation-carrying reference token.
  Map<String, dynamic> _withMintedReference(Map item, String sessionId) {
    final result = Map<String, dynamic>.from(item);
    final key = result['reference'];
    result['reference'] = (key is String && key.isNotEmpty)
        ? _service.reference(sessionId, key)?.encode()
        : null;
    return result;
  }

  Map<String, dynamic>? _decodeMarkerJson(String raw) {
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith(_runtimeMarker)) {
        final jsonStr = trimmed.substring(_runtimeMarker.length);
        final decoded = jsonDecode(jsonStr);
        if (decoded is Map<String, dynamic>) return decoded;
      }
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Device scripts. All helpers are module-level names that start with
  // `__pyrite_` so they are excluded from the globals listing and stay
  // constant across queries. `__pyrite_refs` / `__pyrite_seq` are the only
  // state that must survive between transactions.
  // -------------------------------------------------------------------------

  String get _helperPreamble =>
      '''
def __pyrite_reg(obj):
    g = globals()
    refs = g.get('__pyrite_refs')
    if refs is None:
        refs = {}
        g['__pyrite_refs'] = refs
    seq = g.get('__pyrite_seq', 0)
    g['__pyrite_seq'] = seq + 1
    key = str(seq)
    refs[key] = obj
    return key

def __pyrite_expandable(obj):
    if isinstance(obj, (dict, list, tuple, set, frozenset)):
        return True
    try:
        return hasattr(obj, '__dict__')
    except Exception:
        return False

def __pyrite_type(obj):
    t = type(obj)
    mod = getattr(t, '__module__', '') or ''
    name = getattr(t, '__name__', '') or 'object'
    if mod and mod != 'builtins':
        return mod + '.' + name
    return name

def __pyrite_repr(obj):
    try:
        r = repr(obj)
    except Exception as e:
        r = '<repr error: %s>' % (e,)
    if len(r) > $_maxRepr:
        r = r[:${_maxRepr - 3}] + '...'
    return r

def __pyrite_slots(obj):
    if isinstance(obj, dict):
        keys = []
        for k in obj:
            keys.append(k)
        return keys, lambda k: obj[k]
    if isinstance(obj, (list, tuple)):
        return list(range(len(obj))), lambda i: obj[i]
    if isinstance(obj, (set, frozenset)):
        vals = []
        for v in obj:
            vals.append(v)
        return list(range(len(vals))), lambda i: vals[i]
    try:
        d = obj.__dict__
    except Exception:
        d = None
    if isinstance(d, dict):
        keys = []
        for k in d:
            keys.append(k)
        return keys, lambda k: d[k]
    names = []
    for n in dir(obj):
        if not n.startswith('_'):
            names.append(n)
    return names, lambda n: getattr(obj, n)

def __pyrite_item(name, obj):
    has = __pyrite_expandable(obj)
    ref = None
    if has:
        ref = __pyrite_reg(obj)
    return {
        'name': name,
        'type': __pyrite_type(obj),
        'repr': __pyrite_repr(obj),
        'hasChildren': has,
        'reference': ref,
    }
''';

  String _globalsPageScript(int start, int count) =>
      '''
$_helperPreamble
def __pyrite_globals_page(start, count):
    import ujson as json
    g = globals()
    if start == 0:
        g['__pyrite_refs'] = {}
        g['__pyrite_seq'] = 0
    names = [k for k in g if not k.startswith('__')]
    total = len(names)
    if count <= 0:
        end = total
    else:
        end = start + count
    items = []
    i = start
    while i < end and i < total:
        k = names[i]
        try:
            items.append(__pyrite_item(k, g[k]))
        except Exception as e:
            items.append({'name': k, 'type': 'exception', 'repr': __pyrite_repr(e), 'hasChildren': False, 'reference': None})
        i += 1
    return {'items': items, 'total': total, 'start': start}

def __pyrite_emit():
    import ujson as json
    print('$_runtimeMarker' + json.dumps(__pyrite_globals_page($start, $count)))

__pyrite_emit()
''';

  String _childrenPageScript(String objectId, int start, int count) =>
      '''
$_helperPreamble
def __pyrite_children_page(ref_key, start, count):
    import ujson as json
    refs = globals().get('__pyrite_refs', {})
    obj = refs.get(ref_key)
    if obj is None:
        return {'items': [], 'total': 0, 'start': start}
    keys, getter = __pyrite_slots(obj)
    total = len(keys)
    if count <= 0:
        end = total
    else:
        end = start + count
    items = []
    i = start
    while i < end and i < total:
        k = keys[i]
        name = str(k)
        try:
            child = getter(k)
            has = __pyrite_expandable(child)
            ref = None
            if has:
                ref = __pyrite_reg(child)
            items.append({'name': name, 'type': __pyrite_type(child), 'repr': __pyrite_repr(child), 'hasChildren': has, 'reference': ref})
        except Exception as e:
            items.append({'name': name, 'type': 'exception', 'repr': __pyrite_repr(e), 'hasChildren': False, 'reference': None})
        i += 1
    return {'items': items, 'total': total, 'start': start}

def __pyrite_emit():
    import ujson as json
    print('$_runtimeMarker' + json.dumps(__pyrite_children_page('$objectId', $start, $count)))

__pyrite_emit()
''';

  String _objectInfoScript(String objectId) =>
      '''
$_helperPreamble
def __pyrite_info(ref_key):
    import ujson as json
    refs = globals().get('__pyrite_refs', {})
    obj = refs.get(ref_key)
    if obj is None:
        return None
    attrs = []
    keys, getter = __pyrite_slots(obj)
    for k in keys:
        name = str(k)
        try:
            child = getter(k)
            has = __pyrite_expandable(child)
            ref = None
            if has:
                ref = __pyrite_reg(child)
            attrs.append({'name': name, 'type': __pyrite_type(child), 'repr': __pyrite_repr(child), 'hasChildren': has, 'reference': ref})
        except Exception as e:
            attrs.append({'name': name, 'type': 'exception', 'repr': __pyrite_repr(e), 'hasChildren': False, 'reference': None})
    return {'type': __pyrite_type(obj), 'repr': __pyrite_repr(obj), 'attributes': attrs}

def __pyrite_emit():
    import ujson as json
    print('$_runtimeMarker' + json.dumps(__pyrite_info('$objectId')))

__pyrite_emit()
''';
}
