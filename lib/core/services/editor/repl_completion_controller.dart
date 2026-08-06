import 'package:flutter/foundation.dart';

enum ReplCompletionKind {
  keyword,
  builtin,
  module,
  function,
  className,
  variable,
  property,
  constant,
  text,
}

enum ReplCompletionSource { staticCatalog, runtime, lsp }

class ReplCompletionItem {
  const ReplCompletionItem({
    required this.label,
    required this.insertText,
    required this.replaceStart,
    required this.replaceEnd,
    required this.kind,
    required this.source,
    this.detail,
    this.documentation,
  });

  final String label;
  final String insertText;
  final int replaceStart;
  final int replaceEnd;
  final ReplCompletionKind kind;
  final ReplCompletionSource source;
  final String? detail;
  final String? documentation;

  ReplCompletionItem withRange(int start, int end) => ReplCompletionItem(
    label: label,
    insertText: insertText,
    replaceStart: start,
    replaceEnd: end,
    kind: kind,
    source: source,
    detail: detail,
    documentation: documentation,
  );
}

class ReplCompletionContext {
  const ReplCompletionContext({
    required this.source,
    required this.cursor,
    required this.token,
    required this.replaceStart,
    required this.replaceEnd,
    required this.owner,
    required this.isMemberAccess,
    this.manual = false,
  });

  final String source;
  final int cursor;
  final String token;
  final int replaceStart;
  final int replaceEnd;
  final String? owner;
  final bool isMemberAccess;
  final bool manual;

  bool get hasQuery => token.isNotEmpty || isMemberAccess;
  bool get shouldAutoTrigger => isMemberAccess || token.length >= 2;
  bool get shouldQueryRuntime => manual || shouldAutoTrigger;

  static ReplCompletionContext fromText(
    String source,
    int cursor, {
    bool manual = false,
  }) {
    final boundedCursor = cursor.clamp(0, source.length);
    final before = source.substring(0, boundedCursor);
    final tokenMatch = RegExp(r'[A-Za-z_]\w*$').firstMatch(before);
    final token = tokenMatch?.group(0) ?? '';
    final tokenStart = tokenMatch?.start ?? boundedCursor;
    final ownerMatch = RegExp(
      r'(?:^|[^A-Za-z0-9_])([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\.$',
    ).firstMatch(before.substring(0, tokenStart));
    return ReplCompletionContext(
      source: source,
      cursor: boundedCursor,
      token: token,
      replaceStart: tokenStart,
      replaceEnd: boundedCursor,
      owner: ownerMatch?.group(1),
      isMemberAccess: ownerMatch != null,
      manual: manual,
    );
  }
}

class ReplCompletionController extends ChangeNotifier {
  ReplCompletionController({
    Future<List<ReplCompletionItem>> Function(ReplCompletionContext context)?
    provider,
  }) : _provider = provider ?? ReplCompletionCatalog.complete;

  final Future<List<ReplCompletionItem>> Function(ReplCompletionContext context)
  _provider;

  List<ReplCompletionItem> _items = const [];
  int _selectedIndex = 0;
  int _requestId = 0;
  bool _isOpen = false;
  bool _isLoading = false;

  List<ReplCompletionItem> get items => _items;
  int get selectedIndex => _selectedIndex;
  ReplCompletionItem? get selected => _items.isEmpty
      ? null
      : _items[_selectedIndex.clamp(0, _items.length - 1)];
  bool get isOpen => _isOpen;
  bool get isLoading => _isLoading;

  Future<void> request(ReplCompletionContext context) async {
    final requestId = ++_requestId;
    _isLoading = true;
    _isOpen = false;
    notifyListeners();
    final result = await _provider(context);
    if (requestId != _requestId) return;
    _items = result;
    _selectedIndex = 0;
    _isLoading = false;
    _isOpen = result.isNotEmpty;
    notifyListeners();
  }

  void move(int delta) {
    if (!_isOpen || _items.isEmpty) return;
    _selectedIndex = (_selectedIndex + delta) % _items.length;
    if (_selectedIndex < 0) _selectedIndex += _items.length;
    notifyListeners();
  }

  void select(int index) {
    if (index < 0 || index >= _items.length || _selectedIndex == index) return;
    _selectedIndex = index;
    notifyListeners();
  }

  void dismiss() {
    _requestId++;
    if (!_isOpen && !_isLoading) return;
    _isOpen = false;
    _isLoading = false;
    _items = const [];
    _selectedIndex = 0;
    notifyListeners();
  }
}

class ReplCompletionCatalog {
  static Future<List<ReplCompletionItem>> complete(
    ReplCompletionContext context,
  ) async {
    final source = context.isMemberAccess
        ? _membersFor(context.owner)
        : _globalItems;
    final prefix = context.token;
    final filtered = source
        .where((item) => item.label.startsWith(prefix))
        .map((item) => item.withRange(context.replaceStart, context.replaceEnd))
        .toList();
    filtered.sort((a, b) {
      final aExact = a.label == prefix ? 0 : 1;
      final bExact = b.label == prefix ? 0 : 1;
      final exact = aExact.compareTo(bExact);
      return exact != 0 ? exact : a.label.compareTo(b.label);
    });
    return filtered.take(80).toList(growable: false);
  }

  static List<ReplCompletionItem> _membersFor(String? owner) {
    final key = owner?.split('.').last;
    return _memberCatalog[key] ?? const [];
  }

  static ReplCompletionItem _item(
    String label,
    ReplCompletionKind kind,
    String detail,
  ) => ReplCompletionItem(
    label: label,
    insertText: label,
    replaceStart: 0,
    replaceEnd: 0,
    kind: kind,
    source: ReplCompletionSource.staticCatalog,
    detail: detail,
  );

  static final _globalItems = <ReplCompletionItem>[
    for (final name in const [
      'and',
      'as',
      'assert',
      'async',
      'await',
      'break',
      'case',
      'class',
      'continue',
      'def',
      'del',
      'elif',
      'else',
      'except',
      'finally',
      'for',
      'from',
      'global',
      'if',
      'import',
      'in',
      'is',
      'lambda',
      'match',
      'not',
      'or',
      'pass',
      'raise',
      'return',
      'try',
      'while',
      'with',
      'yield',
    ])
      _item(name, ReplCompletionKind.keyword, 'Python keyword'),
    for (final name in const [
      'abs',
      'all',
      'any',
      'bin',
      'bool',
      'bytes',
      'callable',
      'chr',
      'dict',
      'dir',
      'enumerate',
      'eval',
      'filter',
      'float',
      'getattr',
      'hasattr',
      'hex',
      'id',
      'int',
      'isinstance',
      'iter',
      'len',
      'list',
      'map',
      'max',
      'min',
      'next',
      'object',
      'open',
      'ord',
      'pow',
      'print',
      'property',
      'range',
      'repr',
      'reversed',
      'round',
      'set',
      'setattr',
      'slice',
      'sorted',
      'str',
      'sum',
      'super',
      'tuple',
      'type',
      'vars',
      'zip',
    ])
      _item(name, ReplCompletionKind.builtin, 'MicroPython builtin'),
    for (final name in const [
      'machine',
      'micropython',
      'network',
      'os',
      'sys',
      'time',
      'uasyncio',
      'ubinascii',
      'ucollections',
      'uctypes',
      'ujson',
      'uselect',
      'usocket',
      'ustruct',
      'gc',
      'framebuf',
      'esp',
      'rp2',
      'pyb',
    ])
      _item(name, ReplCompletionKind.module, 'MicroPython module'),
    for (final name in const [
      'Pin',
      'ADC',
      'PWM',
      'UART',
      'SPI',
      'I2C',
      'RTC',
      'Timer',
      'WDT',
    ])
      _item(name, ReplCompletionKind.className, 'Hardware class'),
  ];

  static final _memberCatalog = <String, List<ReplCompletionItem>>{
    'machine': [
      for (final name in const [
        'Pin',
        'ADC',
        'PWM',
        'UART',
        'SPI',
        'I2C',
        'RTC',
        'Timer',
        'WDT',
        'reset',
        'freq',
        'unique_id',
      ])
        _item(name, ReplCompletionKind.property, 'machine member'),
    ],
    'time': [
      for (final name in const [
        'sleep',
        'sleep_ms',
        'sleep_us',
        'ticks_ms',
        'ticks_us',
        'ticks_cpu',
        'ticks_diff',
        'localtime',
        'mktime',
      ])
        _item(name, ReplCompletionKind.function, 'time function'),
    ],
    'network': [
      for (final name in const ['WLAN', 'STA_IF', 'AP_IF', 'LAN'])
        _item(name, ReplCompletionKind.property, 'network member'),
    ],
    'os': [
      for (final name in const [
        'listdir',
        'mkdir',
        'remove',
        'rmdir',
        'stat',
        'statvfs',
        'uname',
        'getcwd',
        'chdir',
      ])
        _item(name, ReplCompletionKind.function, 'os function'),
    ],
    'sys': [
      for (final name in const [
        'argv',
        'byteorder',
        'implementation',
        'path',
        'platform',
        'stderr',
        'stdin',
        'stdout',
      ])
        _item(name, ReplCompletionKind.property, 'sys member'),
    ],
    'ujson': [
      for (final name in const ['dumps', 'loads'])
        _item(name, ReplCompletionKind.function, 'ujson function'),
    ],
    'Pin': [
      for (final name in const ['init', 'value', 'on', 'off', 'toggle', 'irq'])
        _item(name, ReplCompletionKind.function, 'Pin method'),
    ],
    'UART': [
      for (final name in const [
        'init',
        'deinit',
        'any',
        'read',
        'readline',
        'readinto',
        'write',
      ])
        _item(name, ReplCompletionKind.function, 'UART method'),
    ],
  };
}

class ReplSignatureContext {
  const ReplSignatureContext({
    required this.source,
    required this.cursor,
    required this.callable,
    required this.activeParameter,
    this.triggerCharacter,
  });

  final String source;
  final int cursor;
  final String callable;
  final int activeParameter;
  final String? triggerCharacter;

  static ReplSignatureContext? fromText(
    String source,
    int cursor, {
    String? triggerCharacter,
  }) {
    final boundedCursor = cursor.clamp(0, source.length);
    final stack = <int>[];
    String? quote;
    var escaped = false;
    var comment = false;
    for (var index = 0; index < boundedCursor; index++) {
      final char = source[index];
      if (comment) {
        if (char == '\n') comment = false;
        continue;
      }
      if (quote != null) {
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
          escaped = true;
        } else if (char == quote) {
          quote = null;
        }
        continue;
      }
      if (char == '#') {
        comment = true;
      } else if (char == "'" || char == '"') {
        quote = char;
      } else if (char == '(') {
        stack.add(index);
      } else if (char == ')' && stack.isNotEmpty) {
        stack.removeLast();
      }
    }
    if (stack.isEmpty) return null;
    final open = stack.last;
    final beforeOpen = source.substring(0, open);
    final callableMatch = RegExp(
      r'([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s*$',
    ).firstMatch(beforeOpen);
    final callable = callableMatch?.group(1);
    if (callable == null) return null;

    var activeParameter = 0;
    var nested = 0;
    quote = null;
    escaped = false;
    for (var index = open + 1; index < boundedCursor; index++) {
      final char = source[index];
      if (quote != null) {
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
          escaped = true;
        } else if (char == quote) {
          quote = null;
        }
        continue;
      }
      if (char == "'" || char == '"') {
        quote = char;
      } else if (char == '(' || char == '[' || char == '{') {
        nested++;
      } else if (char == ')' || char == ']' || char == '}') {
        if (nested > 0) nested--;
      } else if (char == ',' && nested == 0) {
        activeParameter++;
      }
    }
    return ReplSignatureContext(
      source: source,
      cursor: boundedCursor,
      callable: callable,
      activeParameter: activeParameter,
      triggerCharacter: triggerCharacter,
    );
  }
}

class ReplSignatureHint {
  const ReplSignatureHint({
    required this.label,
    required this.activeParameter,
    this.documentation,
    this.source = ReplCompletionSource.staticCatalog,
  });

  final String label;
  final int activeParameter;
  final String? documentation;
  final ReplCompletionSource source;
}

class ReplSignatureController extends ChangeNotifier {
  ReplSignatureController({
    Future<ReplSignatureHint?> Function(ReplSignatureContext context)? provider,
  }) : _provider = provider ?? ReplSignatureCatalog.find;

  final Future<ReplSignatureHint?> Function(ReplSignatureContext context)
  _provider;
  int _requestId = 0;
  ReplSignatureHint? _hint;

  ReplSignatureHint? get hint => _hint;
  bool get isOpen => _hint != null;

  Future<void> request(ReplSignatureContext context) async {
    final requestId = ++_requestId;
    final hint = await _provider(context);
    if (requestId != _requestId) return;
    _hint = hint;
    notifyListeners();
  }

  void dismiss() {
    _requestId++;
    if (_hint == null) return;
    _hint = null;
    notifyListeners();
  }
}

class ReplSignatureCatalog {
  static Future<ReplSignatureHint?> find(ReplSignatureContext context) async {
    final label =
        _signatures[context.callable] ??
        _signatures[context.callable.split('.').last];
    if (label == null) return null;
    return ReplSignatureHint(
      label: label,
      activeParameter: context.activeParameter,
    );
  }

  static const _signatures = <String, String>{
    'print': 'print(*objects, sep=" ", end="\\n")',
    'range': 'range(start, stop=None, step=1)',
    'len': 'len(object)',
    'open': 'open(file, mode="r")',
    'enumerate': 'enumerate(iterable, start=0)',
    'machine.Pin': 'machine.Pin(id, mode=-1, pull=-1, *, value=None)',
    'Pin': 'Pin(id, mode=-1, pull=-1, *, value=None)',
    'machine.UART': 'machine.UART(id, baudrate=9600, ...)',
    'UART': 'UART(id, baudrate=9600, ...)',
    'machine.I2C': 'machine.I2C(id, *, scl, sda, freq=400000)',
    'I2C': 'I2C(id, *, scl, sda, freq=400000)',
    'time.sleep': 'time.sleep(seconds)',
    'sleep': 'sleep(seconds)',
  };
}
