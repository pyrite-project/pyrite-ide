import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef ContextKeyChangeListener = void Function(Set<String> changedKeys);

class ContextKeyService extends ChangeNotifier {
  ContextKeyService({Set<String>? allowedKeys})
    : allowedKeys = Set<String>.unmodifiable(allowedKeys ?? defaultKeys);

  static const Set<String> defaultKeys = {
    'editor.language',
    'editor.hasDocument',
    'runtime.language',
    'runtime.state',
    'device.connected',
    'workspace.opened',
    'plugin.enabled',
    'view.active',
  };

  final Set<String> allowedKeys;
  final Map<String, Object> _values = {};
  final Set<ContextKeyChangeListener> _changeListeners = {};

  Map<String, Object> get values => Map<String, Object>.unmodifiable(_values);

  Object? value(String key) {
    _validateKey(key);
    return _values[key];
  }

  void setValue(String key, Object? value) => setValues({key: value});

  void setValues(Map<String, Object?> values) {
    for (final entry in values.entries) {
      _validateKey(entry.key);
      _validateValue(entry.value);
    }
    final changed = <String>{};
    for (final entry in values.entries) {
      final previous = _values[entry.key];
      if (entry.value == null) {
        if (_values.remove(entry.key) != null) changed.add(entry.key);
      } else if (previous != entry.value || !_values.containsKey(entry.key)) {
        _values[entry.key] = entry.value!;
        changed.add(entry.key);
      }
    }
    if (changed.isEmpty) return;
    final immutable = Set<String>.unmodifiable(changed);
    for (final listener in _changeListeners.toList(growable: false)) {
      listener(immutable);
    }
    notifyListeners();
  }

  void addChangeListener(ContextKeyChangeListener listener) {
    _changeListeners.add(listener);
  }

  void removeChangeListener(ContextKeyChangeListener listener) {
    _changeListeners.remove(listener);
  }

  bool evaluate(WhenExpression? expression) =>
      expression?.evaluate(_values) ?? true;

  void _validateKey(String key) {
    if (!allowedKeys.contains(key)) {
      throw ArgumentError.value(key, 'key', 'Unknown context key');
    }
  }

  static void _validateValue(Object? value) {
    if (value == null || value is bool || value is String || value is num) {
      return;
    }
    throw ArgumentError.value(
      value,
      'value',
      'Context values must be bool, string, number, or null',
    );
  }

  @override
  void dispose() {
    _changeListeners.clear();
    super.dispose();
  }
}

final contextKeyServiceProvider = ChangeNotifierProvider<ContextKeyService>(
  (ref) => ContextKeyService(),
);

class WhenExpression {
  const WhenExpression._(this.source, this.dependencies, this._root);

  final String source;
  final Set<String> dependencies;
  final _WhenNode _root;

  factory WhenExpression.parse(
    String source, {
    Set<String> allowedKeys = ContextKeyService.defaultKeys,
  }) {
    final parser = _WhenExpressionParser(source, allowedKeys);
    final root = parser.parse();
    return WhenExpression._(
      source,
      Set<String>.unmodifiable(root.dependencies),
      root,
    );
  }

  bool evaluate(Map<String, Object?> context) => _root.evaluate(context);
}

sealed class _WhenNode {
  const _WhenNode();

  Set<String> get dependencies;
  bool evaluate(Map<String, Object?> context);
}

class _PredicateNode extends _WhenNode {
  const _PredicateNode(this.key, this.operator, this.expected);

  final String key;
  final _WhenTokenType? operator;
  final Object? expected;

  @override
  Set<String> get dependencies => {key};

  @override
  bool evaluate(Map<String, Object?> context) {
    final actual = context[key];
    if (operator == null) {
      return switch (actual) {
        bool value => value,
        num value => value != 0,
        String value => value.isNotEmpty,
        _ => false,
      };
    }
    final equal = actual == expected;
    return operator == _WhenTokenType.equal ? equal : !equal;
  }
}

class _NotNode extends _WhenNode {
  const _NotNode(this.child);

  final _WhenNode child;

  @override
  Set<String> get dependencies => child.dependencies;

  @override
  bool evaluate(Map<String, Object?> context) => !child.evaluate(context);
}

class _BinaryNode extends _WhenNode {
  const _BinaryNode(this.left, this.operator, this.right);

  final _WhenNode left;
  final _WhenTokenType operator;
  final _WhenNode right;

  @override
  Set<String> get dependencies => {...left.dependencies, ...right.dependencies};

  @override
  bool evaluate(Map<String, Object?> context) => operator == _WhenTokenType.and
      ? left.evaluate(context) && right.evaluate(context)
      : left.evaluate(context) || right.evaluate(context);
}

enum _WhenTokenType {
  identifier,
  literal,
  and,
  or,
  not,
  equal,
  notEqual,
  leftParenthesis,
  rightParenthesis,
  end,
}

class _WhenToken {
  const _WhenToken(this.type, this.value, this.offset);

  final _WhenTokenType type;
  final Object? value;
  final int offset;
}

class _WhenExpressionParser {
  _WhenExpressionParser(this.source, this.allowedKeys)
    : _tokens = _tokenize(source);

  static const _maxSourceLength = 4096;
  static const _maxTokens = 256;
  static const _maxDepth = 64;

  final String source;
  final Set<String> allowedKeys;
  final List<_WhenToken> _tokens;
  int _index = 0;
  int _depth = 0;

  _WhenNode parse() {
    if (source.trim().isEmpty) {
      throw const FormatException('expression is empty');
    }
    final result = _parseOr();
    _expect(_WhenTokenType.end, 'unexpected trailing input');
    return result;
  }

  _WhenNode _parseOr() {
    var result = _parseAnd();
    while (_match(_WhenTokenType.or)) {
      result = _BinaryNode(result, _WhenTokenType.or, _parseAnd());
    }
    return result;
  }

  _WhenNode _parseAnd() {
    var result = _parseUnary();
    while (_match(_WhenTokenType.and)) {
      result = _BinaryNode(result, _WhenTokenType.and, _parseUnary());
    }
    return result;
  }

  _WhenNode _parseUnary() {
    if (_depth >= _maxDepth) {
      throw FormatException('expression is too deeply nested', source);
    }
    _depth++;
    try {
      if (_match(_WhenTokenType.not)) return _NotNode(_parseUnary());
      if (_match(_WhenTokenType.leftParenthesis)) {
        final result = _parseOr();
        _expect(_WhenTokenType.rightParenthesis, 'missing closing parenthesis');
        return result;
      }
      return _parsePredicate();
    } finally {
      _depth--;
    }
  }

  _WhenNode _parsePredicate() {
    final identifier = _expect(
      _WhenTokenType.identifier,
      'expected a context key',
    );
    final key = identifier.value! as String;
    if (!allowedKeys.contains(key)) {
      throw FormatException(
        'unknown context key $key',
        source,
        identifier.offset,
      );
    }
    _WhenTokenType? operator;
    if (_match(_WhenTokenType.equal)) {
      operator = _WhenTokenType.equal;
    } else if (_match(_WhenTokenType.notEqual)) {
      operator = _WhenTokenType.notEqual;
    }
    final expected = operator == null
        ? null
        : _expect(_WhenTokenType.literal, 'expected a literal value').value;
    return _PredicateNode(key, operator, expected);
  }

  bool _match(_WhenTokenType type) {
    if (_tokens[_index].type != type) return false;
    _index++;
    return true;
  }

  _WhenToken _expect(_WhenTokenType type, String message) {
    final token = _tokens[_index];
    if (token.type != type) {
      throw FormatException(message, source, token.offset);
    }
    _index++;
    return token;
  }

  static List<_WhenToken> _tokenize(String source) {
    if (source.length > _maxSourceLength) {
      throw FormatException('expression is too long', source);
    }
    final tokens = <_WhenToken>[];
    var index = 0;
    while (index < source.length) {
      final code = source.codeUnitAt(index);
      if (_isWhitespace(code)) {
        index++;
        continue;
      }
      if (tokens.length >= _maxTokens) {
        throw FormatException('expression is too complex', source, index);
      }
      if (source.startsWith('&&', index)) {
        tokens.add(_WhenToken(_WhenTokenType.and, null, index));
        index += 2;
      } else if (source.startsWith('||', index)) {
        tokens.add(_WhenToken(_WhenTokenType.or, null, index));
        index += 2;
      } else if (source.startsWith('==', index)) {
        tokens.add(_WhenToken(_WhenTokenType.equal, null, index));
        index += 2;
      } else if (source.startsWith('!=', index)) {
        tokens.add(_WhenToken(_WhenTokenType.notEqual, null, index));
        index += 2;
      } else if (code == 0x21) {
        tokens.add(_WhenToken(_WhenTokenType.not, null, index++));
      } else if (code == 0x28) {
        tokens.add(_WhenToken(_WhenTokenType.leftParenthesis, null, index++));
      } else if (code == 0x29) {
        tokens.add(_WhenToken(_WhenTokenType.rightParenthesis, null, index++));
      } else if (code == 0x22 || code == 0x27) {
        final start = index;
        final quote = code;
        index++;
        final buffer = StringBuffer();
        var closed = false;
        while (index < source.length) {
          final current = source.codeUnitAt(index++);
          if (current == quote) {
            closed = true;
            break;
          }
          if (current == 0x0a || current == 0x0d) break;
          if (current == 0x5c) {
            if (index >= source.length) break;
            final escaped = source.codeUnitAt(index++);
            buffer.writeCharCode(switch (escaped) {
              0x6e => 0x0a,
              0x72 => 0x0d,
              0x74 => 0x09,
              0x5c || 0x22 || 0x27 => escaped,
              _ => throw FormatException(
                'unsupported string escape',
                source,
                index - 2,
              ),
            });
          } else {
            buffer.writeCharCode(current);
          }
        }
        if (!closed) {
          throw FormatException('unterminated string literal', source, start);
        }
        tokens.add(
          _WhenToken(_WhenTokenType.literal, buffer.toString(), start),
        );
      } else if (_isDigit(code) ||
          (code == 0x2d &&
              index + 1 < source.length &&
              _isDigit(source.codeUnitAt(index + 1)))) {
        final start = index++;
        while (index < source.length && _isDigit(source.codeUnitAt(index))) {
          index++;
        }
        var isDouble = false;
        if (index < source.length && source.codeUnitAt(index) == 0x2e) {
          isDouble = true;
          index++;
          final fractionStart = index;
          while (index < source.length && _isDigit(source.codeUnitAt(index))) {
            index++;
          }
          if (index == fractionStart) {
            throw FormatException('invalid number literal', source, start);
          }
        }
        final raw = source.substring(start, index);
        tokens.add(
          _WhenToken(
            _WhenTokenType.literal,
            isDouble ? double.parse(raw) : int.parse(raw),
            start,
          ),
        );
      } else if (_isIdentifierStart(code)) {
        final start = index++;
        while (index < source.length &&
            _isIdentifierPart(source.codeUnitAt(index))) {
          index++;
        }
        final value = source.substring(start, index);
        tokens.add(
          _WhenToken(
            value == 'true' || value == 'false'
                ? _WhenTokenType.literal
                : _WhenTokenType.identifier,
            value == 'true'
                ? true
                : value == 'false'
                ? false
                : value,
            start,
          ),
        );
      } else {
        throw FormatException('unsupported token', source, index);
      }
    }
    tokens.add(_WhenToken(_WhenTokenType.end, null, source.length));
    return tokens;
  }

  static bool _isWhitespace(int code) =>
      code == 0x20 || code == 0x09 || code == 0x0a || code == 0x0d;
  static bool _isDigit(int code) => code >= 0x30 && code <= 0x39;
  static bool _isIdentifierStart(int code) =>
      (code >= 0x41 && code <= 0x5a) ||
      (code >= 0x61 && code <= 0x7a) ||
      code == 0x5f;
  static bool _isIdentifierPart(int code) =>
      _isIdentifierStart(code) || _isDigit(code) || code == 0x2e;
}
