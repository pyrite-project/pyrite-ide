/// Base dart:io-compatible types shared by the web filesystem backend and the
/// `pyrite_io` web implementation.
library;

/// Web stand-in for `dart:io` [IOException].
class IOException implements Exception {}

/// Web stand-in for `dart:io` [OSError].
class OSError {
  OSError([this.message = '', this.errorCode = -1]);

  final String message;
  final int errorCode;

  @override
  String toString() =>
      message.isEmpty ? 'OSError($errorCode)' : 'OSError: $message';
}

/// Web stand-in for `dart:io` [FileSystemException].
class FileSystemException extends IOException {
  FileSystemException([this.message = '', this.path = '', this.osError]);

  final String message;
  final String path;
  final OSError? osError;

  @override
  String toString() {
    final buffer = StringBuffer('FileSystemException');
    if (message.isNotEmpty) buffer.write(': $message');
    if (path.isNotEmpty) buffer.write(', path = $path');
    if (osError != null) buffer.write(' ($osError)');
    return buffer.toString();
  }
}

/// Web stand-in for `dart:io` [FileSystemEntityType].
class FileSystemEntityType {
  const FileSystemEntityType._(this._name);

  final String _name;

  static const FileSystemEntityType file = FileSystemEntityType._('file');
  static const FileSystemEntityType directory = FileSystemEntityType._(
    'directory',
  );
  static const FileSystemEntityType link = FileSystemEntityType._('link');
  static const FileSystemEntityType unixDomainSock =
      FileSystemEntityType._('unixDomainSock');
  static const FileSystemEntityType pipe = FileSystemEntityType._('pipe');
  static const FileSystemEntityType notFound = FileSystemEntityType._(
    'notFound',
  );

  @override
  String toString() => _name;
}

/// Web stand-in for `dart:io` [FileSystemEvent] (type only; watch streams are
/// unsupported on the web but the subscription type appears in signatures).
class FileSystemEvent {
  FileSystemEvent._();

  static const int create = 1;
  static const int modify = 2;
  static const int delete = 4;
  static const int move = 8;

  int get type => throw UnsupportedError('FileSystemEvent is unsupported');
  String get path => throw UnsupportedError('FileSystemEvent is unsupported');
  bool get isDirectory =>
      throw UnsupportedError('FileSystemEvent is unsupported');
}

/// Web stand-in for `dart:io` [WebSocketException].
class WebSocketException implements Exception {
  WebSocketException([this.message = '']);

  final String message;

  @override
  String toString() => message.isEmpty ? 'WebSocketException' : message;
}

/// Web stand-in for `dart:io` [ProcessException].
class ProcessException implements Exception {
  ProcessException(this.executable, this.arguments, [this.message = '']);

  final String executable;
  final List<String> arguments;
  final String message;

  @override
  String toString() => 'ProcessException: $message';
}
