/// Browser file-system backend for the Flutter Web build.
///
/// Two path spaces are mounted into one virtual, posix-style namespace:
///
/// * `/.pyrite_ide/...` — app-support storage backed by the Origin Private
///   File System (OPFS). Always available; hosts persisted app data.
/// * `/<picked-folder>/...` — a real user directory picked through the File
///   System Access API (`showDirectoryPicker`). The directory handle is kept
///   in IndexedDB so a workspace can be restored across reloads once the
///   user re-grants access.
///
/// Everything here requires a Chromium-based browser (the same requirement as
/// Web Serial), which is the supported web target for PyriteIDE.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:pyrite_ide/core/platform/web/pyrite_io_base.dart';
import 'package:web/web.dart' as web;

// ---------------------------------------------------------------------------
// Additional JS bindings not provided by package:web 1.1.1
// ---------------------------------------------------------------------------

extension type _DirectoryPickerOptions._(JSObject _) implements JSObject {
  external factory _DirectoryPickerOptions({JSString? mode, JSString? id});
}

extension type _PermissionDescriptor._(JSObject _) implements JSObject {
  external factory _PermissionDescriptor({JSString? mode});
}

extension WindowDirectoryPicker on web.Window {
  external JSPromise<web.FileSystemDirectoryHandle> showDirectoryPicker([
    _DirectoryPickerOptions? options,
  ]);
}

extension FileSystemHandleExtras on web.FileSystemHandle {
  external JSPromise<JSString> queryPermission(JSObject? descriptor);
  external JSPromise<JSString> requestPermission(JSObject? descriptor);
  external JSPromise<JSAny?> move(JSAny? target, [JSString? name]);

  Future<void> moveTo(web.FileSystemHandle? directory, String name) async {
    await move(
      directory,
      name.toJS,
    );
  }
}

extension DirectoryAsyncIterable on web.FileSystemDirectoryHandle {
  external JSObject values();
}

extension type _IteratorResult._(JSObject _) implements JSObject {
  external JSAny? get value;
}

/// Converts an IndexedDB request into a Dart future via its success/error
/// events (package:web exposes no direct request-to-future helper).
Future<JSAny?> _requestToFuture(web.IDBRequest request) {
  final completer = Completer<JSAny?>();
  request.onsuccess = ((web.Event _) {
    completer.complete(request.result);
  }).toJS;
  request.onerror = ((web.Event _) {
    completer.completeError(StateError('IndexedDB request failed'));
  }).toJS;
  return completer.future;
}

// ---------------------------------------------------------------------------
// Error helpers
// ---------------------------------------------------------------------------

String? _errorPropertyName(Object? error) {
  if (error is JSObject) {
    try {
      final name = error.getProperty('name'.toJS);
      if (name.isA<JSString>()) return (name as JSString).toDart;
    } catch (_) {}
    try {
      final message = error.getProperty('message'.toJS);
      if (message.isA<JSString>()) return (message as JSString).toDart;
    } catch (_) {}
  }
  return null;
}

bool _isNotFoundError(Object? error) {
  if (error == null) return false;
  final name = _errorPropertyName(error);
  if (name == 'NotFoundError' || name == 'TypeMismatchError') return true;
  final message = error.toString();
  return message.contains('NotFoundError') ||
      message.contains('could not be found');
}

// ---------------------------------------------------------------------------
// Path helpers
// ---------------------------------------------------------------------------

/// Normalizes a virtual path: collapses slashes, resolves `.`/`..`,
/// and guarantees a leading slash.
String normalizeVirtualPath(String input) {
  var path = input.replaceAll('\\', '/');
  final isAbsolute = path.startsWith('/');
  final out = <String>[];
  for (final segment in path.split('/')) {
    switch (segment) {
      case '' || '.':
        continue;
      case '..':
        if (out.isNotEmpty) out.removeLast();
      default:
        out.add(segment);
    }
  }
  final joined = out.join('/');
  if (!isAbsolute) return joined.isEmpty ? '.' : joined;
  return '/$joined';
}

/// Splits a normalized absolute virtual path into segments (no root entry).
List<String> splitVirtualPath(String path) {
  final normalized = normalizeVirtualPath(path);
  if (normalized == '/' || normalized.isEmpty) return const [];
  return normalized.substring(1).split('/');
}

// ---------------------------------------------------------------------------
// Persistent handle storage (IndexedDB)
// ---------------------------------------------------------------------------

class _HandleStore {
  static const _dbName = 'pyrite_ide_fs';
  static const _storeName = 'handles';

  web.IDBDatabase? _db;

  Future<web.IDBDatabase> _open() async {
    final existing = _db;
    if (existing != null) return existing;
    final request = web.indexedDB.open(_dbName, 1);
    request.onupgradeneeded = ((web.IDBVersionChangeEvent _) {
      final db = request.result;
      if (!db.objectStoreNames.contains(_storeName)) {
        db.createObjectStore(_storeName);
      }
    }).toJS;
    final db = (await _requestToFuture(request)) as web.IDBDatabase;
    _db = db;
    return db;
  }

  Future<web.FileSystemDirectoryHandle?> get(String key) async {
    try {
      final db = await _open();
      final tx = db.transaction(_storeName, 'readonly');
      final request = tx.objectStore(_storeName).get(key.toJS);
      final result = await _requestToFuture(request);
      if (result == null || result.isUndefinedOrNull) return null;
      return result as web.FileSystemDirectoryHandle;
    } catch (_) {
      return null;
    }
  }

  Future<void> put(String key, web.FileSystemDirectoryHandle handle) async {
    try {
      final db = await _open();
      final tx = db.transaction(_storeName, 'readwrite');
      tx.objectStore(_storeName).put(handle.toJS, key.toJS);
    } catch (_) {}
  }

  Future<void> delete(String key) async {
    try {
      final db = await _open();
      final tx = db.transaction(_storeName, 'readwrite');
      tx.objectStore(_storeName).delete(key.toJS);
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------------
// Backend
// ---------------------------------------------------------------------------

/// Result of a filesystem type probe.
enum WebFsEntryType { file, directory, notFound }

/// One directory entry produced by [WebFs.listDirectory].
class WebFsEntry {
  WebFsEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
  });

  final String name;
  final String path;
  final bool isDirectory;
}

/// Singleton managing mounts and all browser file operations.
class WebFs {
  WebFs._();

  static final WebFs instance = WebFs._();

  static const _workspaceKey = 'workspace';
  static const appSupportMountName = '.pyrite_ide';

  final _HandleStore _store = _HandleStore();

  /// OPFS root; resolved lazily and kept for the app-support mount.
  web.FileSystemDirectoryHandle? _opfsRoot;

  final Map<String, web.FileSystemDirectoryHandle> _mounts = {};

  /// Label of the currently selected user directory, without slashes.
  String? workspaceLabel;

  bool get hasWorkspaceMount => workspaceLabel != null;

  /// Resolves (and caches) the OPFS root handle.
  Future<web.FileSystemDirectoryHandle> opfsRoot() async {
    final existing = _opfsRoot;
    if (existing != null) return existing;
    final root = await web.window.navigator.storage.getDirectory().toDart;
    _opfsRoot = root;
    return root;
  }

  /// Mounts the OPFS `.pyrite_ide` directory used as the app-support root.
  Future<void> ensureAppSupportMounted() async {
    if (_mounts.containsKey(appSupportMountName)) return;
    final root = await opfsRoot();
    final dir = await root
        .getDirectoryHandle(
          appSupportMountName,
          web.FileSystemGetDirectoryOptions(create: true),
        )
        .toDart;
    _mounts[appSupportMountName] = dir;
  }

  /// Shows the browser directory picker and mounts the chosen folder.
  ///
  /// Returns the virtual root path (for example `/my-project`), or null when
  /// the user cancels.
  Future<String?> pickWorkspaceDirectory() async {
    final web.FileSystemDirectoryHandle handle;
    try {
      handle = await web.window
          .showDirectoryPicker(
            _DirectoryPickerOptions(mode: 'readwrite'.toJS),
          )
          .toDart;
    } catch (_) {
      return null; // user cancelled or API unavailable
    }
    final label = handle.name;
    _mounts[label] = handle;
    workspaceLabel = label;
    await _store.put(_workspaceKey, handle);
    return '/$label';
  }

  /// Restores a previously picked workspace if the browser still grants
  /// access without prompting. Returns the restored root path or null.
  Future<String?> restoreWorkspace() async {
    final handle = await _store.get(_workspaceKey);
    if (handle == null) return null;
    try {
      final permission = await handle
          .queryPermission(_PermissionDescriptor(mode: 'readwrite'.toJS))
          .toDart;
      if (permission.toDart != 'granted') return null;
      final label = handle.name;
      _mounts[label] = handle;
      workspaceLabel = label;
      return '/$label';
    } catch (_) {
      return null;
    }
  }

  /// Requests access to the persisted workspace inside a user gesture.
  /// Returns the root path when granted.
  Future<String?> requestPersistedWorkspace() async {
    final handle = await _store.get(_workspaceKey);
    if (handle == null) return null;
    try {
      final permission = await handle
          .requestPermission(_PermissionDescriptor(mode: 'readwrite'.toJS))
          .toDart;
      if (permission.toDart != 'granted') return null;
      final label = handle.name;
      _mounts[label] = handle;
      workspaceLabel = label;
      return '/$label';
    } catch (_) {
      return null;
    }
  }

  Future<void> forgetWorkspace() async {
    final label = workspaceLabel;
    workspaceLabel = null;
    if (label != null) _mounts.remove(label);
    await _store.delete(_workspaceKey);
  }

  // -------------------------------------------------------------------------
  // Path resolution
  // -------------------------------------------------------------------------

  Future<web.FileSystemDirectoryHandle> _resolveDirectory(
    String path, {
    bool create = false,
  }) async {
    final segments = splitVirtualPath(path);
    if (segments.isEmpty) {
      throw StateError('cannot resolve filesystem root: $path');
    }
    final mount = _mounts[segments.first];
    if (mount == null) {
      throw notFound(path);
    }
    var handle = mount;
    for (final segment in segments.skip(1)) {
      handle = await handle
          .getDirectoryHandle(
            segment,
            web.FileSystemGetDirectoryOptions(create: create),
          )
          .toDart;
    }
    return handle;
  }

  /// Resolves the *parent* directory plus the final segment name.
  Future<(web.FileSystemDirectoryHandle, String)> _resolveParent(
    String path, {
    bool create = false,
  }) async {
    final segments = splitVirtualPath(path);
    if (segments.length < 2) {
      throw StateError('path has no parent inside the virtual root: $path');
    }
    final parentPath =
        '/${segments.sublist(0, segments.length - 1).join('/')}';
    final parent = await _resolveDirectory(parentPath, create: create);
    return (parent, segments.last);
  }

  FileSystemException notFound(String path) => FileSystemException(
        'No such file or directory',
        path,
        OSError('NotFoundError', 2),
      );

  /// Wraps browser errors; rethrows [FileSystemException] when possible.
  Never _rethrow(Object error, String path) {
    if (error is FileSystemException) throw error;
    if (_isNotFoundError(error)) throw notFound(path);
    final message = _errorPropertyName(error) ?? error.toString();
    throw FileSystemException(message, path, OSError(message, 0));
  }

  // -------------------------------------------------------------------------
  // Operations
  // -------------------------------------------------------------------------

  Future<WebFsEntryType> typeOf(String path) async {
    final segments = splitVirtualPath(path);
    if (segments.isEmpty) return WebFsEntryType.directory;
    if (_mounts.containsKey(segments.first) && segments.length == 1) {
      return WebFsEntryType.directory;
    }
    try {
      final (parent, name) = await _resolveParent(path);
      try {
        await parent
            .getFileHandle(name, web.FileSystemGetFileOptions(create: false))
            .toDart;
        return WebFsEntryType.file;
      } catch (fileError) {
        try {
          await parent
              .getDirectoryHandle(
                name,
                web.FileSystemGetDirectoryOptions(create: false),
              )
              .toDart;
          return WebFsEntryType.directory;
        } catch (_) {
          _rethrow(fileError, path);
        }
      }
    } catch (error) {
      if (_isNotFoundError(error)) return WebFsEntryType.notFound;
      rethrow;
    }
  }

  Future<bool> fileExists(String path) async {
    try {
      final (parent, name) = await _resolveParent(path);
      await parent
          .getFileHandle(name, web.FileSystemGetFileOptions(create: false))
          .toDart;
      return true;
    } catch (error) {
      if (_isNotFoundError(error)) return false;
      if (error is StateError) return false;
      rethrow;
    }
  }

  Future<bool> directoryExists(String path) async {
    try {
      final segments = splitVirtualPath(path);
      if (segments.length == 1) return _mounts.containsKey(segments.first);
      final (parent, name) = await _resolveParent(path);
      await parent
          .getDirectoryHandle(
            name,
            web.FileSystemGetDirectoryOptions(create: false),
          )
          .toDart;
      return true;
    } catch (error) {
      if (_isNotFoundError(error)) return false;
      if (error is StateError) return false;
      rethrow;
    }
  }

  Future<Uint8List> readFileBytes(String path) async {
    try {
      final (parent, name) = await _resolveParent(path);
      final handle = await parent
          .getFileHandle(name, web.FileSystemGetFileOptions(create: false))
          .toDart;
      final file = await handle.getFile().toDart;
      final buffer = await file.arrayBuffer().toDart;
      return buffer.asUint8List();
    } catch (error) {
      _rethrow(error, path);
    }
  }

  Future<String> readTextFile(String path) async {
    final bytes = await readFileBytes(path);
    return utf8.decode(bytes, allowMalformed: true);
  }

  Future<void> writeFileBytes(String path, List<int> bytes) async {
    try {
      final (parent, name) = await _resolveParent(path);
      final handle = await parent
          .getFileHandle(name, web.FileSystemGetFileOptions(create: true))
          .toDart;
      final writable = await handle.createWritable().toDart;
      final data = Uint8List.fromList(bytes);
      await writable.write(data.toJS).toDart;
      await writable.close().toDart;
    } catch (error) {
      _rethrow(error, path);
    }
  }

  Future<void> createDirectory(String path, {bool recursive = false}) async {
    final segments = splitVirtualPath(path);
    if (segments.isEmpty) return;
    if (_mounts.containsKey(segments.first) && segments.length == 1) {
      return; // mount roots always exist
    }
    if (!recursive && segments.length > 1) {
      // Only the final segment may be missing for non-recursive creates.
      final parentPath =
          '/${segments.sublist(0, segments.length - 1).join('/')}';
      if (!await directoryExists(parentPath)) {
        throw notFound(path);
      }
    }
    try {
      await _resolveDirectory(path, create: true);
    } catch (error) {
      _rethrow(error, path);
    }
  }

  Future<void> createFile(String path, {bool recursive = false}) async {
    final segments = splitVirtualPath(path);
    if (segments.isEmpty) {
      throw FileSystemException('Invalid file path', path);
    }
    if (recursive) {
      final parentPath =
          '/${segments.sublist(0, segments.length - 1).join('/')}';
      await createDirectory(parentPath, recursive: true);
    }
    try {
      final (parent, name) = await _resolveParent(path);
      await parent
          .getFileHandle(name, web.FileSystemGetFileOptions(create: true))
          .toDart;
    } catch (error) {
      _rethrow(error, path);
    }
  }

  /// Lists the direct children of [path].
  Future<List<WebFsEntry>> listDirectory(String path) async {
    final handle = await _resolveDirectory(path);
    final entries = <WebFsEntry>[];
    final iterator = handle.values();
    while (true) {
      final next =
          await iterator.callMethod<JSPromise<JSAny?>>('next'.toJS).toDart;
      if (next == null || next.isUndefinedOrNull) break;
      final iteratorResult = _IteratorResult._(next as JSObject);
      final value = iteratorResult.value;
      if (value == null || value.isUndefinedOrNull) break;
      final child = value as web.FileSystemHandle;
      final base = path.endsWith('/') && path.length > 1
          ? path.substring(0, path.length - 1)
          : path;
      final kind = child.kind.toDart;
      entries.add(
        WebFsEntry(
          name: child.name,
          path: '$base/${child.name}',
          isDirectory: kind == 'directory',
        ),
      );
    }
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.compareTo(b.name);
    });
    return entries;
  }

  /// Lists every descendant of [path] (breadth first, like
  /// `Directory.list(recursive: true)`).
  Future<List<WebFsEntry>> listDirectoryRecursive(String path) async {
    final out = <WebFsEntry>[];
    final queue = <String>[path];
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      for (final entry in await listDirectory(current)) {
        out.add(entry);
        if (entry.isDirectory) queue.add(entry.path);
      }
    }
    return out;
  }

  Future<void> deleteEntry(String path, {bool recursive = false}) async {
    try {
      final (parent, name) = await _resolveParent(path);
      await parent
          .removeEntry(name, web.FileSystemRemoveOptions(recursive: recursive))
          .toDart;
    } catch (error) {
      _rethrow(error, path);
    }
  }

  Future<void> rename(String oldPath, String newPath) async {
    final newName = splitVirtualPath(newPath).last;
    for (final useFile in [true, false]) {
      try {
        final (oldParent, oldName) = await _resolveParent(oldPath);
        final handle = useFile
            ? await oldParent
                .getFileHandle(
                  oldName,
                  web.FileSystemGetFileOptions(create: false),
                )
                .toDart
            : await oldParent
                .getDirectoryHandle(
                  oldName,
                  web.FileSystemGetDirectoryOptions(create: false),
                )
                .toDart;
        await handle.moveTo(null, newName);
        return;
      } catch (_) {
        // Try the next variant, then fall back to copy+delete.
      }
    }
    await _copyThenDelete(oldPath, newPath);
  }

  Future<void> _copyThenDelete(String oldPath, String newPath) async {
    final type = await typeOf(oldPath);
    switch (type) {
      case WebFsEntryType.file:
        final bytes = await readFileBytes(oldPath);
        await createFile(newPath, recursive: true);
        await writeFileBytes(newPath, bytes);
        await deleteEntry(oldPath);
      case WebFsEntryType.directory:
        await createDirectory(newPath, recursive: true);
        for (final entry in await listDirectory(oldPath)) {
          await _copyThenDelete(entry.path, '$newPath/${entry.name}');
        }
        await deleteEntry(oldPath);
      case WebFsEntryType.notFound:
        throw notFound(oldPath);
    }
  }

  Future<void> copyFile(String sourcePath, String targetPath) async {
    final bytes = await readFileBytes(sourcePath);
    await createFile(targetPath, recursive: true);
    await writeFileBytes(targetPath, bytes);
  }

  /// Last modified time and size of a file.
  Future<(DateTime, int)> statFile(String path) async {
    try {
      final (parent, name) = await _resolveParent(path);
      final handle = await parent
          .getFileHandle(name, web.FileSystemGetFileOptions(create: false))
          .toDart;
      final file = await handle.getFile().toDart;
      return (
        DateTime.fromMillisecondsSinceEpoch(file.lastModified),
        file.size,
      );
    } catch (error) {
      _rethrow(error, path);
    }
  }
}
