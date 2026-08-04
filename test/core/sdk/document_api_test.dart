import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/api/document_api.dart';
import 'package:pyrite_ide/core/sdk/document_registry.dart';
import 'package:pyrite_ide/core/sdk/document_service.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/sdk/plugin_transport.dart';

class _Transport implements PluginTransport {
  final StreamController<Uint8List> _messages =
      StreamController<Uint8List>.broadcast();
  final StreamController<PluginTransportState> _states =
      StreamController<PluginTransportState>.broadcast();
  final _responses = StreamController<Map<String, dynamic>>.broadcast();

  @override
  String get type => 'Fake';
  @override
  Stream<Uint8List> get messages => _messages.stream;
  @override
  Stream<PluginTransportState> get states => _states.stream;

  @override
  Future<void> start() async {
    _states.add(PluginTransportState.connecting);
    _states.add(PluginTransportState.ready);
  }

  @override
  Future<void> send(Uint8List message) async {
    final envelope = jsonDecode(utf8.decode(message)) as Map<String, dynamic>;
    switch (envelope['type']) {
      case IdeCommands.initialize:
        emit(SdkCommands.initialize, envelope, 1, {
          'protocolVersion': 1,
          'capabilities': ['sdk.v1'],
        });
      case IdeCommands.initialized:
        emit(SdkCommands.ready, envelope, 2, {
          'capabilities': ['sdk.v1'],
        });
      default:
        _responses.add(envelope);
    }
  }

  void emit(String type, Map<String, dynamic> req, int seq, Map payload) {
    _messages.add(
      Uint8List.fromList(
        utf8.encode(
          jsonEncode(
            makeEnvelope(
              type: type,
              pluginId: req['pluginId'] as String,
              sessionId: req['sessionId'] as String,
              generation: req['generation'] as int,
              replyTo: req['requestId'] as String,
              sequence: seq,
              payload: Map<String, dynamic>.from(payload),
            ),
          ),
        ),
      ),
    );
  }

  Stream<Map<String, dynamic>> get responses => _responses.stream;

  /// Injects an inbound request as if the plugin had sent it.
  void inject(Map<String, dynamic> envelope) {
    _messages.add(Uint8List.fromList(utf8.encode(jsonEncode(envelope))));
  }

  @override
  Future<void> close() async {
    await _messages.close();
    await _states.close();
    await _responses.close();
  }
}

class _FakeAccess implements DocumentAccess {
  _FakeAccess({this.symbols, this.symbolsAvailable = true, this.rev = 1});

  List<dynamic>? symbols;
  bool symbolsAvailable;
  int rev;
  int? revealedLine;

  @override
  int get revision => rev;
  @override
  String get text => 'print(1)\n';
  @override
  int get lineCount => 2;
  @override
  ({int start, int end}) get selection => (start: 0, end: 3);
  @override
  ({int line, int column}) get cursor => (line: 0, column: 0);
  @override
  Future<List<dynamic>>? documentSymbols() =>
      symbolsAvailable ? Future.value(symbols ?? const []) : null;
}

class _FakeHost implements DocumentHost {
  _FakeHost();

  @override
  final DocumentRegistry registry = DocumentRegistry(idFactory: () => 'doc-1');
  final Map<String, _FakeAccess> _access = {};
  String? _active;
  Object? revealError;

  void addDocument(
    String id, {
    required String path,
    bool active = false,
    _FakeAccess? access,
  }) {
    final handle = Object();
    // Force the registry to mint the id we want by using a fixed factory.
    registry.register(handle: handle, filePath: path, languageId: 'python');
    _access[id] = access ?? _FakeAccess();
    if (active) {
      registry.setActive(handle);
      _active = id;
    }
  }

  @override
  DocumentAccess? access(String documentId) => _access[documentId];

  @override
  String? get activeDocumentId => _active;

  @override
  Future<void> reveal(
    String documentId, {
    required int line,
    int? column,
  }) async {
    final error = revealError;
    if (error != null) throw error;
    _access[documentId]?.revealedLine = line;
  }
}

Future<({PluginRunManager manager, _Transport transport})> _start(
  ProviderContainer container,
) async {
  final transport = _Transport();
  final manager = PluginRunManager(
    transport: transport,
    assetsPath: '.',
    pluginId: 'doc-test',
    pluginPermissions: const {
      'editor': ['read', 'write'],
    },
    sessionId: 'session-1',
    generation: 1,
  );
  container.read(sdkEditorDocumentProvider).bind(manager);
  await manager.connect();
  return (manager: manager, transport: transport);
}

Future<Map<String, dynamic>> _request(
  PluginRunManager manager,
  _Transport transport,
  String type,
  Map<String, dynamic> payload,
) async {
  final envelope = makeEnvelope(
    type: type,
    payload: payload,
    pluginId: manager.pluginId,
    sessionId: manager.sessionId,
    generation: manager.generation,
    sequence: 100,
  );
  final response = transport.responses
      .firstWhere((e) => e['replyTo'] == envelope['requestId'])
      .timeout(const Duration(seconds: 5));
  transport.inject(envelope);
  return response;
}

void main() {
  late ProviderContainer container;
  late _FakeHost host;

  setUp(() {
    host = _FakeHost();
    container = ProviderContainer(
      overrides: [documentHostProvider.overrideWithValue(host)],
    );
  });

  tearDown(() => container.dispose());

  test('active_document.get returns the active document', () async {
    host.addDocument('doc-1', path: '/a.py', active: true);
    final started = await _start(container);
    final response = await _request(
      started.manager,
      started.transport,
      SdkEditorDocumentCommands.activeDocumentGet,
      {},
    );
    expect(response['type'], SdkCommands.responseOk);
    final data = response['payload']['data'] as Map<String, dynamic>;
    expect(data['documentId'], 'doc-1');
    expect(data['isActive'], true);
    await started.manager.stop();
  });

  test('document.symbols returns symbols with the query revision', () async {
    host.addDocument(
      'doc-1',
      path: '/a.py',
      access: _FakeAccess(
        symbols: [
          {'name': 'main', 'kind': 12},
        ],
        rev: 7,
      ),
    );
    final started = await _start(container);
    final response = await _request(
      started.manager,
      started.transport,
      SdkEditorDocumentCommands.documentSymbols,
      {'documentId': 'doc-1'},
    );
    final data = response['payload']['data'] as Map<String, dynamic>;
    expect(data['revision'], 7);
    expect(data['stale'], false);
    expect((data['symbols'] as List).single['name'], 'main');
    await started.manager.stop();
  });

  test('document.symbols reports unavailable when LSP is off', () async {
    host.addDocument(
      'doc-1',
      path: '/a.py',
      access: _FakeAccess(symbolsAvailable: false),
    );
    final started = await _start(container);
    final response = await _request(
      started.manager,
      started.transport,
      SdkEditorDocumentCommands.documentSymbols,
      {'documentId': 'doc-1'},
    );
    expect(response['type'], SdkCommands.responseError);
    expect(response['payload']['code'], 'unavailable');
    await started.manager.stop();
  });

  test('reveal moves the caret in the target document', () async {
    final access = _FakeAccess();
    host.addDocument('doc-1', path: '/a.py', access: access);
    final started = await _start(container);
    final response = await _request(
      started.manager,
      started.transport,
      SdkEditorDocumentCommands.documentReveal,
      {'documentId': 'doc-1', 'line': 4},
    );
    expect(response['type'], SdkCommands.responseOk);
    expect(access.revealedLine, 4);
    await started.manager.stop();
  });

  test('reveal reports unavailable instead of leaking host errors', () async {
    host.addDocument('doc-1', path: '/a.py');
    host.revealError = StateError('Editor is not initialized');
    final started = await _start(container);
    final response = await _request(
      started.manager,
      started.transport,
      SdkEditorDocumentCommands.documentReveal,
      {'documentId': 'doc-1', 'line': 4},
    );
    expect(response['type'], SdkCommands.responseError);
    expect(response['payload']['code'], 'unavailable');
    await started.manager.stop();
  });

  test('get for an unknown document returns document_not_found', () async {
    final started = await _start(container);
    final response = await _request(
      started.manager,
      started.transport,
      SdkEditorDocumentCommands.documentGet,
      {'documentId': 'nope'},
    );
    expect(response['type'], SdkCommands.responseError);
    expect(response['payload']['code'], 'document_not_found');
    await started.manager.stop();
  });
}
