/// Flutter Web implementation of the `pyrite_io` facade — a browser-backed
/// subset of `dart:io` (see [WebFs] for the storage backend).
///
/// Synchronous filesystem operations cannot be mapped onto the asynchronous
/// browser APIs, so `*Sync` members throw [UnsupportedError]; call sites that
/// can run on the web have been moved to the async variants.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:pyrite_ide/core/platform/web/pyrite_io_base.dart';
import 'package:pyrite_ide/core/platform/web/web_fs_backend.dart' as webfs;

export 'package:pyrite_ide/core/platform/web/pyrite_io_base.dart'
    show
        FileSystemException,
        FileSystemEntityType,
        FileSystemEvent,
        IOException,
        OSError,
        ProcessException,
        WebSocketException;

Never _syncUnsupported(String op) => throw UnsupportedError(
      'Synchronous filesystem operation "$op" is not supported on the web.',
    );

webfs.WebFs get _fs => webfs.WebFs.instance;

// ---------------------------------------------------------------------------
// Platform
// ---------------------------------------------------------------------------

extension type _WebNavigator._(JSObject _) implements JSObject {
  external JSString get userAgent;
  external JSString get language;
}

final _WebNavigator _navigator = _WebNavigator._(
  globalContext.getProperty('navigator'.toJS) as JSObject,
);

/// Web stand-in for `dart:io` [Platform], deriving the OS from the user agent.
class Platform {
  Platform._();

  static String? _cachedUserAgent;
  static String get _userAgent {
    final cached = _cachedUserAgent;
    if (cached != null) return cached;
    final ua = _navigator.userAgent.toDart;
    _cachedUserAgent = ua;
    return ua;
  }

  static String get operatingSystem {
    final ua = _userAgent;
    if (ua.contains('Android')) return 'android';
    if (ua.contains('iPhone') || ua.contains('iPad') || ua.contains('iPod')) {
      return 'ios';
    }
    if (ua.contains('Windows')) return 'windows';
    if (ua.contains('Mac OS X') || ua.contains('Macintosh')) return 'macos';
    return 'linux';
  }

  static bool get isWindows => operatingSystem == 'windows';
  static bool get isMacOS => operatingSystem == 'macos';
  static bool get isLinux => operatingSystem == 'linux';
  static bool get isAndroid => operatingSystem == 'android';
  static bool get isIOS => operatingSystem == 'ios';
  static bool get isFuchsia => false;

  static String get operatingSystemVersion => '';
  static String get localHostname => '';
  static String get localeName => _navigator.language.toDart;
  static String get version => 'Flutter Web';
  static int get numberOfProcessors => 1;
  static String get pathSeparator => '/';
  static String get resolvedExecutable => '';
  static String get scriptFileName => '';
  static Map<String, String> get environment => const {};
  static Uri get script => Uri.base;
}

// ---------------------------------------------------------------------------
// Top-level helpers
// ---------------------------------------------------------------------------

/// Process id placeholder (no processes on the web).
const int pid = 0;

/// Web stand-in for `dart:io` [exit]; the browser tab cannot be terminated
/// programmatically the way a desktop process can.
Never exit(int code) =>
    throw UnsupportedError('exit() is not supported on the web.');

/// Web stand-in for `dart:io` [sleep].
Never sleep(Duration duration) =>
    throw UnsupportedError('sleep() is not supported on the web.');

/// Web stand-in for `dart:io` [exitCode].
int exitCode = 0;

// ---------------------------------------------------------------------------
// Process (unsupported)
// ---------------------------------------------------------------------------

/// Web stand-in for `dart:io` [ProcessResult].
class ProcessResult {
  ProcessResult(this.pid, this.exitCode, this.stdout, this.stderr);

  final int pid;
  final int exitCode;
  final dynamic stdout;
  final dynamic stderr;
}

/// Web stand-in for `dart:io` [Process]; every operation throws.
class Process {
  Process._();

  static Never _unsupported() => throw UnsupportedError(
        'Local processes are not available in the browser.',
      );

  static Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Encoding? stdoutEncoding = const Utf8Codec(),
    Encoding? stderrEncoding = const Utf8Codec(),
  }) =>
      _unsupported();

  static Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
  }) =>
      _unsupported();
}

// ---------------------------------------------------------------------------
// Socket (unsupported)
// ---------------------------------------------------------------------------

/// Web stand-in for `dart:io` [Socket]; every operation throws.
class Socket {
  Socket._();

  static Never _unsupported() => throw UnsupportedError(
        'Raw TCP sockets are not available in the browser; use WebSockets.',
      );

  static Future<Socket> connect(
    String host,
    int port, {
    Duration? timeout,
  }) =>
      _unsupported();

  void write(List<int> bytes) => _unsupported();
  void destroy() => _unsupported();
  Future<void> close() => _unsupported();
  Stream<Uint8List> get stream => _unsupported();
}

// ---------------------------------------------------------------------------
// File stat / link
// ---------------------------------------------------------------------------

/// Web stand-in for `dart:io` [FileStat].
class FileStat {
  FileStat._(this.modified, this.size, this.type);

  final DateTime modified;
  final int size;
  final FileSystemEntityType type;

  static Future<FileStat> stat(String path) async {
    final entryType = await _fs.typeOf(path);
    if (entryType == webfs.WebFsEntryType.file) {
      final (modified, size) = await _fs.statFile(path);
      return FileStat._(modified, size, FileSystemEntityType.file);
    }
    if (entryType == webfs.WebFsEntryType.directory) {
      return FileStat._(
        DateTime.fromMillisecondsSinceEpoch(0),
        0,
        FileSystemEntityType.directory,
      );
    }
    return FileStat._(
      DateTime.fromMillisecondsSinceEpoch(0),
      -1,
      FileSystemEntityType.notFound,
    );
  }
}

/// Web stand-in for `dart:io` [Link]; symbolic links do not exist in the
/// browser filesystem, so every operation throws.
class Link extends FileSystemEntity {
  factory Link(String path) => Link._(path);

  Link._(super.path) : super._();

  @override
  Future<bool> exists() async => false;

  @override
  Future<Link> rename(String newPath) => _syncUnsupported('Link.rename');

  Future<String> target() => _syncUnsupported('Link.target');

  Future<Link> create(String target, {bool recursive = false}) =>
      _syncUnsupported('Link.create');

  Link createSync(String target, {bool recursive = false}) =>
      _syncUnsupported('Link.createSync');

  Future<Link> delete({bool recursive = false}) =>
      _syncUnsupported('Link.delete');

  Link deleteSync({bool recursive = false}) =>
      _syncUnsupported('Link.deleteSync');
}

// ---------------------------------------------------------------------------
// File / Directory / FileSystemEntity
// ---------------------------------------------------------------------------

/// Web stand-in for `dart:io` [FileSystemEntity].
abstract class FileSystemEntity {
  FileSystemEntity._(this.path);

  final String path;

  /// Whether the entity exists.
  Future<bool> exists();

  bool existsSync() => _syncUnsupported('$runtimeType.existsSync');

  /// Renames (moves) this entity to [newPath].
  Future<FileSystemEntity> rename(String newPath);

  Uri get uri => Uri.file(path, windows: false);

  static Future<FileSystemEntityType> type(
    String path, {
    bool followLinks = true,
  }) async {
    final entryType = await _fs.typeOf(path);
    return switch (entryType) {
      webfs.WebFsEntryType.file => FileSystemEntityType.file,
      webfs.WebFsEntryType.directory => FileSystemEntityType.directory,
      webfs.WebFsEntryType.notFound => FileSystemEntityType.notFound,
    };
  }

  static FileSystemEntityType typeSync(
    String path, {
    bool followLinks = true,
  }) =>
      _syncUnsupported('FileSystemEntity.typeSync');

  static Future<bool> isFile(String path) async =>
      await type(path) == FileSystemEntityType.file;

  static Future<bool> isDirectory(String path) async =>
      await type(path) == FileSystemEntityType.directory;

  static bool isFileSync(String path) =>
      _syncUnsupported('FileSystemEntity.isFileSync');

  static bool isDirectorySync(String path) =>
      _syncUnsupported('FileSystemEntity.isDirectorySync');

  static Future<String> identifyFullPath(String path) async => path;
}

/// Modes accepted by the file writing APIs.
enum FileMode {
  read,
  write,
  append,
  writeOnly,
  writeOnlyAppend,
}

/// Web stand-in for `dart:io` [File], backed by [WebFs].
class File extends FileSystemEntity {
  factory File(String path) => File._(_normalize(path));

  factory File.fromUri(Uri uri) => File._(_normalize(uri.toFilePath()));

  File._(super.path) : super._();

  static String _normalize(String path) {
    final normalized = webfs.normalizeVirtualPath(path);
    if (!normalized.startsWith('/')) {
      throw FileSystemException('Web paths must be absolute', path);
    }
    return normalized;
  }

  @override
  Future<bool> exists() => _fs.fileExists(path);

  @override
  Future<File> rename(String newPath) async {
    await _fs.rename(path, _normalize(newPath));
    return File._(_normalize(newPath));
  }

  Future<File> renameSync(String newPath) => _syncUnsupported('File.renameSync');

  Future<File> create({bool recursive = false, bool exclusive = false}) async {
    await _fs.createFile(path, recursive: recursive);
    return this;
  }

  Future<File> createSync({bool recursive = false, bool exclusive = false}) =>
      _syncUnsupported('File.createSync');

  Future<DateTime> lastModified() async => (await _fs.statFile(path)).$1;

  Future<int> length() async => (await _fs.statFile(path)).$2;

  int lengthSync() => _syncUnsupported('File.lengthSync');

  Future<DateTime> lastModifiedSync() => _syncUnsupported('File.lastModifiedSync');

  Future<FileStat> stat() => FileStat.stat(path);

  FileStat statSync() => _syncUnsupported('File.statSync');

  Future<Uint8List> readAsBytes() => _fs.readFileBytes(path);

  Uint8List readAsBytesSync() => _syncUnsupported('File.readAsBytesSync');

  Future<String> readAsString({Encoding encoding = utf8}) async {
    final bytes = await _fs.readFileBytes(path);
    return encoding.decode(bytes);
  }

  String readAsStringSync({Encoding encoding = utf8}) =>
      _syncUnsupported('File.readAsStringSync');

  Future<List<String>> readAsLines({Encoding encoding = utf8}) async {
    final content = await readAsString(encoding: encoding);
    return const LineSplitter().convert(content);
  }

  List<String> readAsLinesSync({Encoding encoding = utf8}) =>
      _syncUnsupported('File.readAsLinesSync');

  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) async {
    if (mode == FileMode.append || mode == FileMode.writeOnlyAppend) {
      final existing =
          await exists() ? await _fs.readFileBytes(path) : Uint8List(0);
      await _fs.writeFileBytes(path, [...existing, ...bytes]);
      return this;
    }
    await _fs.writeFileBytes(path, bytes);
    return this;
  }

  File writeAsBytesSync(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) =>
      _syncUnsupported('File.writeAsBytesSync');

  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) {
    return writeAsBytes(encoding.encode(contents), mode: mode, flush: flush);
  }

  File writeAsStringSync(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) =>
      _syncUnsupported('File.writeAsStringSync');

  Future<File> copy(String newPath) async {
    await _fs.copyFile(path, _normalize(newPath));
    return File._(_normalize(newPath));
  }

  File copySync(String newPath) => _syncUnsupported('File.copySync');

  Future<File> delete({bool recursive = false}) async {
    await _fs.deleteEntry(path);
    return this;
  }

  File deleteSync({bool recursive = false}) =>
      _syncUnsupported('File.deleteSync');

  Directory get parent => Directory(_parentPath(path));

  /// Absolute form; web paths are already absolute.
  File get absolute => this;
}

/// Web stand-in for `dart:io` [Directory], backed by [WebFs].
class Directory extends FileSystemEntity {
  factory Directory(String path) => Directory._(_normalize(path));

  factory Directory.fromUri(Uri uri) => Directory._(_normalize(
        uri.scheme == 'file' ? uri.toFilePath() : uri.path,
      ));

  Directory._(super.path) : super._();

  /// The OPFS-backed temporary directory mount.
  static Directory get systemTemp => Directory('/.pyrite_ide/tmp');

  /// The app-support mount stands in for the (meaningless) web cwd.
  static Directory get current => Directory('/.pyrite_ide');

  /// Accepts a [Directory] or a path string, mirroring `dart:io`; changing
  /// the working directory is meaningless on the web.
  static set current(Object? path) =>
      _syncUnsupported('Directory.current set');

  static String _normalize(String path) {
    final normalized = webfs.normalizeVirtualPath(path);
    if (!normalized.startsWith('/')) {
      throw FileSystemException('Web paths must be absolute', path);
    }
    return normalized;
  }

  @override
  Future<bool> exists() => _fs.directoryExists(path);

  @override
  Future<Directory> rename(String newPath) async {
    await _fs.rename(path, _normalize(newPath));
    return Directory._(_normalize(newPath));
  }

  Future<Directory> renameSync(String newPath) =>
      _syncUnsupported('Directory.renameSync');

  Future<Directory> create({bool recursive = false}) async {
    await _fs.createDirectory(path, recursive: recursive);
    return this;
  }

  Directory createSync({bool recursive = false}) =>
      _syncUnsupported('Directory.createSync');

  Future<Directory> createTemp([String? prefix]) =>
      _syncUnsupported('Directory.createTemp');

  Directory createTempSync([String? prefix]) =>
      _syncUnsupported('Directory.createTempSync');

  Future<Directory> delete({bool recursive = false}) async {
    await _fs.deleteEntry(path, recursive: recursive);
    return this;
  }

  Directory deleteSync({bool recursive = false}) =>
      _syncUnsupported('Directory.deleteSync');

  /// Lists the children of this directory as a stream of [File] and
  /// [Directory] entities, mirroring `dart:io` semantics.
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) async* {
    if (recursive) {
      for (final entry in await _fs.listDirectoryRecursive(path)) {
        yield entry.isDirectory ? Directory(entry.path) : File(entry.path);
      }
      return;
    }
    for (final entry in await _fs.listDirectory(path)) {
      yield entry.isDirectory ? Directory(entry.path) : File(entry.path);
    }
  }

  List<FileSystemEntity> listSync({
    bool recursive = false,
    bool followLinks = true,
  }) =>
      _syncUnsupported('Directory.listSync');

  Stream<FileSystemEvent> watch({
    int events = 15,
    bool recursive = false,
  }) => throw UnsupportedError('Directory.watch is not supported on the web.');

  Directory get parent => Directory(_parentPath(path));

  /// Absolute form; web paths are already absolute.
  Directory get absolute => this;
}

/// Computes the parent directory of a normalized absolute path.
String _parentPath(String path) {
  final segments = webfs.splitVirtualPath(path);
  if (segments.length <= 1) return '/';
  return '/${segments.sublist(0, segments.length - 1).join('/')}';
}
