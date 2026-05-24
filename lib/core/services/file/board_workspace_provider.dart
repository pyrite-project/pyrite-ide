import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path/path.dart' as p;
import 'package:pyrite_ide/core/services/board_manager/repl_mutex_provider.dart';
import 'package:pyrite_ide/core/services/board_manager/serial_data_callbacks_provider.dart';
import 'package:pyrite_ide/core/services/board_manager/utils.dart';
import 'package:pyrite_ide/core/services/file/board_file_tree_view.dart';
import 'package:super_tree/super_tree.dart';

class RawReplException implements Exception {
  final String message;
  RawReplException(this.message);
  @override
  String toString() => 'RawReplException: $message';
}

class BoardWorkspaceNotifier
    extends StateNotifier<List<TreeNode<FileSystemItem>>> {
  final Ref ref;

  BoardWorkspaceNotifier(this.ref) : super(const []);

  Future<String> _getCommandResult(
    String command, {
    int timeoutMs = 15000,
  }) async {
    final mutex = ref.read(replMutexProvider);
    final stopwatch = Stopwatch()..start();

    void _log(String msg) {
      print('[BoardWS] [${stopwatch.elapsedMilliseconds}ms] $msg');
    }

    _log('Starting command execution');

    return mutex.runExclusive(() async {
      final completer = Completer<String>();
      String result = "";
      bool completed = false;
      Timer? timeoutTimer;

      void callback(Uint8List data) {
        if (completed) return;

        final decoded = utf8.decode(data, allowMalformed: true);
        result += decoded;
        print(
          '[BoardWS] Callback: +${data.length} bytes, total=${result.length}',
        );

        if (result.contains("!@#PyriteIDEEnd#@!")) {
          completed = true;
          timeoutTimer?.cancel();
          _log('End marker found!');
          if (!completer.isCompleted) {
            completer.complete(result);
          }
          ref.read(serialDataCallbacksProvider.notifier).remove(callback);
        }
      }

      ref.read(serialDataCallbacksProvider.notifier).add(callback);

      try {
        _log('Entering RAW REPL...');
        final enterStart = Stopwatch()..start();
        final entered = await ref
            .read(getUsbSerialProvider().notifier)
            .enterRawRepl();
        _log(
          'enterRawRepl took ${enterStart.elapsedMilliseconds}ms, success: $entered',
        );
        if (!entered) {
          throw RawReplException('Failed to enter RAW REPL');
        }

        await Future.delayed(Duration(milliseconds: 500));
        _log('After enter delay, sending command...');

        const sendChunkSize = 32;
        const sendDelayMs = 1;
        for (int i = 0; i < command.length; i += sendChunkSize) {
          final end = (i + sendChunkSize < command.length)
              ? i + sendChunkSize
              : command.length;
          ref
              .read(getUsbSerialProvider().notifier)
              .sendCommand(command.substring(i, end), chunked: false);
          await Future.delayed(Duration(milliseconds: sendDelayMs));
        }
        _log('Command fully sent, waiting for result');

        ref.read(getUsbSerialProvider().notifier).sendCommand("\x04");
        _log('Execute command sent (\\x04)');

        timeoutTimer = Timer(Duration(milliseconds: timeoutMs), () {
          if (!completed) {
            completed = true;
            final previewLen = result.length < 200 ? result.length : 200;
            _log(
              'TIMEOUT! Result (${result.length} chars): ${result.substring(0, previewLen)}',
            );
            if (!completer.isCompleted) {
              completer.completeError(
                RawReplException(
                  'Command timeout after ${timeoutMs}ms. Partial result: ${result.length} chars',
                ),
              );
            }
            ref.read(serialDataCallbacksProvider.notifier).remove(callback);
          }
        });

        return await completer.future;
      } catch (e) {
        _log('Exception: $e');
        completed = true;
        rethrow;
      } finally {
        completed = true;
        _log('Cleanup: removing callback');
        ref.read(serialDataCallbacksProvider.notifier).remove(callback);

        try {
          _log('Exiting RAW REPL...');

          await Future.delayed(Duration(milliseconds: 100));
          ref.read(getUsbSerialProvider().notifier).sendCommand("\x02");

          await Future.delayed(Duration(milliseconds: 500));
          _log('exitRawRepl sent');
        } catch (e) {
          _log('exitRawRepl error: $e');
        }
      }
    });
  }

  Future<String> getCommandResult(String command) async {
    String originalData = await _getCommandResult(command);

    final String startIdentifier = "!@#PyriteIDEStart#@!";
    final String endIdentifier = "!@#PyriteIDEEnd#@!";

    final int startIdentifierIndex = originalData.indexOf(startIdentifier);
    final int endIdentifierIndex = originalData.indexOf(endIdentifier);

    if (startIdentifierIndex == -1 || endIdentifierIndex == -1) {
      final previewLen = originalData.length < 200 ? originalData.length : 200;
      throw RawReplException(
        'Missing delimiters in response (${originalData.length} chars): ${originalData.substring(0, previewLen)}',
      );
    }

    String resultString = originalData.substring(
      startIdentifierIndex + startIdentifier.length,
      endIdentifierIndex,
    );

    return resultString;
  }

  Future<String> getFileContent(String path) async {
    String command = "import uos\n";
    command += "try:\n";
    command += "  with open('$path', 'r') as f:\n";
    command += "    content=f.read()\n";
    command += "  import ubinascii\n";
    command +=
        "  print('!@#PyriteIDEStart#@!'+ubinascii.b2a_base64(content).decode().strip()+'!@#PyriteIDEEnd#@!')\n";
    command += "except Exception as e:\n";
    command += "  print('ERROR:', str(e))\n";

    String b64Content = await _getCommandResult(command);
    String resultString = b64Content
        .split("!@#PyriteIDEStart#@!")[1]
        .split("!@#PyriteIDEEnd#@!")[0];

    if (resultString.startsWith('ERROR:')) {
      throw RawReplException(resultString);
    }

    return utf8.decode(base64.decode(resultString));
  }

  Future<String> writeFile(String targetPath, String content) async {
    final bytes = utf8.encode(content);
    final b64Content = base64.encode(bytes);
    print(
      '[BoardWS] writeFile: path=$targetPath, content length=${content.length}, b64 length=${b64Content.length}',
    );

    const chunkSize = 1024;
    String command;

    if (b64Content.length <= chunkSize) {
      command = "import ubinascii\n";
      command += "try:\n";
      command += "  data=ubinascii.a2b_base64('$b64Content')\n";
      command += "  with open('$targetPath', 'wb') as f:\n";
      command += "    f.write(data)\n";
      command +=
          "    print('!@#PyriteIDEStart#@!SaveFileSuccessfully!@#PyriteIDEEnd#@!')\n";
      command += "except Exception as e:\n";
      command += "  print('ERROR:', str(e))\n";
    } else {
      command = "import ubinascii\n";
      command += "try:\n";
      command += "  f=open('$targetPath', 'wb')\n";

      for (int i = 0; i < b64Content.length; i += chunkSize) {
        final end = (i + chunkSize < b64Content.length)
            ? i + chunkSize
            : b64Content.length;
        final chunk = b64Content.substring(i, end);
        command += "  f.write(ubinascii.a2b_base64('$chunk'))\n";
      }

      command += "  f.close()\n";
      command +=
          "  print('!@#PyriteIDEStart#@!SaveFileSuccessfully!@#PyriteIDEEnd#@!')\n";
      command += "except Exception as e:\n";
      command += "  print('ERROR:', str(e))\n";
    }

    print('[BoardWS] writeFile command lines: ${command.split('\n').length}');

    String contentString = await _getCommandResult(command);
    String resultString = contentString
        .split("!@#PyriteIDEStart#@!")[1]
        .split("!@#PyriteIDEEnd#@!")[0];

    if (resultString.startsWith('ERROR:')) {
      throw RawReplException(resultString);
    }

    return resultString;
  }

  Future<String> deleteFile(String path) async {
    String command = "import os\n";
    command += "try:\n";
    command += "  os.remove('$path')\n";
    command +=
        "  print('!@#PyriteIDEStart#@!DeleteFileSuccessfully!@#PyriteIDEEnd#@!')\n";
    command += "except Exception as e:\n";
    command += "  print('ERROR:', str(e))\n";

    String contentString = await _getCommandResult(command);
    String resultString = contentString
        .split("!@#PyriteIDEStart#@!")[1]
        .split("!@#PyriteIDEEnd#@!")[0];

    if (resultString.startsWith('ERROR:')) {
      throw RawReplException(resultString);
    }

    return resultString;
  }

  Future<String> deleteFolder(String path) async {
    String command = "import uos\n";
    command += "def delete_recursive(d):\n";
    command += "  try:\n";
    command += "    for entry in uos.ilistdir(d):\n";
    command += "      entry_path = d.rstrip('/') + '/' + entry[0]\n";
    command += "      if entry[1] == 0x4000:\n";
    command += "        delete_recursive(entry_path)\n";
    command += "      else:\n";
    command += "        uos.remove(entry_path)\n";
    command += "    uos.rmdir(d)\n";
    command += "  except:\n";
    command += "    pass\n";
    command += "try:\n";
    command += "  delete_recursive('$path')\n";
    command +=
        "  print('!@#PyriteIDEStart#@!DeleteDirSuccessfully!@#PyriteIDEEnd#@!')\n";
    command += "except Exception as e:\n";
    command += "  print('ERROR:', str(e))\n";

    String contentString = await _getCommandResult(command);
    String resultString = contentString
        .split("!@#PyriteIDEStart#@!")[1]
        .split("!@#PyriteIDEEnd#@!")[0];

    if (resultString.startsWith('ERROR:')) {
      throw RawReplException(resultString);
    }

    return resultString;
  }

  Future<String> rename(String path, String newName) async {
    String command = "import os\n";
    command += "try:\n";
    command += "  os.rename('$path', '${p.join(p.dirname(path), newName)}')\n";
    command +=
        "  print('!@#PyriteIDEStart#@!RenameSuccessfully!@#PyriteIDEEnd#@!')\n";
    command += "except Exception as e:\n";
    command += "  print('ERROR:', str(e))\n";

    String contentString = await _getCommandResult(command);
    String resultString = contentString
        .split("!@#PyriteIDEStart#@!")[1]
        .split("!@#PyriteIDEEnd#@!")[0];

    if (resultString.startsWith('ERROR:')) {
      throw RawReplException(resultString);
    }

    return resultString;
  }

  Future<void> createFolder(String path) async {
    String command = "import uos\n";
    command += "try:\n";
    command += "  uos.mkdir('$path')\n";
    command +=
        "  print('!@#PyriteIDEStart#@!MkdirSuccessfully!@#PyriteIDEEnd#@!')\n";
    command += "except OSError as e:\n";
    command += "  if e.args[0] == 17:\n";
    command += "    print('!@#PyriteIDEStart#@!DirExists!@#PyriteIDEEnd#@!')\n";
    command += "  else:\n";
    command += "    print('ERROR:', str(e))\n";
    command += "except Exception as e:\n";
    command += "  print('ERROR:', str(e))\n";

    String contentString = await _getCommandResult(command);
    String resultString = contentString
        .split("!@#PyriteIDEStart#@!")[1]
        .split("!@#PyriteIDEEnd#@!")[0];

    if (resultString.startsWith('ERROR:')) {
      throw RawReplException(resultString);
    }
  }

  Future<List<Map<String, String>>> lisFolderRecursive({
    String path = "/",
  }) async {
    String command = "import uos\n";
    command += "def list_recursive(base_path):\n";
    command += "  result=[]\n";
    command += "  try:\n";
    command += "    for entry in uos.ilistdir(base_path):\n";
    command +=
        "      entry_path=base_path+'/'+entry[0] if base_path!='/' else '/'+entry[0]\n";
    command += "      if entry[1]==0x4000:\n";
    command += "        result.append({'path':entry_path,'type':'folder'})\n";
    command += "        result.extend(list_recursive(entry_path))\n";
    command += "      else:\n";
    command += "        result.append({'path':entry_path,'type':'file'})\n";
    command += "  except:\n";
    command += "    pass\n";
    command += "  return result\n";
    command +=
        "import ujson\nprint('!@#PyriteIDEStart#@!'+ujson.dumps(list_recursive('$path'))+'!@#PyriteIDEEnd#@!')\n";

    String contentString = await _getCommandResult(command, timeoutMs: 30000);
    String resultString = contentString
        .split("!@#PyriteIDEStart#@!")[1]
        .split("!@#PyriteIDEEnd#@!")[0];

    return (jsonDecode(resultString) as List)
        .cast<Map<String, dynamic>>()
        .map((map) => map.map((key, value) => MapEntry(key, value.toString())))
        .toList();
  }

  Future<void> uploadFolder(String localPath, String remotePath) async {
    final dir = io.Directory(localPath);
    final entities = await dir.list(recursive: true).toList();
    final createdDirs = <String>{};

    for (final entity in entities) {
      final relativePath = p
          .relative(entity.path, from: localPath)
          .replaceAll('\\', '/');
      final remoteEntityPath = '$remotePath/$relativePath';
      final parentDir = p.dirname(remoteEntityPath).replaceAll('\\', '/');

      if (entity is io.Directory) {
        print('[BoardWS] Creating remote dir: $remoteEntityPath');
        try {
          await createFolder(remoteEntityPath);
          createdDirs.add(remoteEntityPath);
        } catch (e) {
          print('[BoardWS] Failed to create dir: $e');
        }
      } else if (entity is io.File) {
        if (!createdDirs.contains(parentDir)) {
          print('[BoardWS] Creating parent dir: $parentDir');
          try {
            await createFolder(parentDir);
            createdDirs.add(parentDir);
          } catch (e) {
            print('[BoardWS] Failed to create parent dir: $e');
          }
        }
        print('[BoardWS] Uploading file: $remoteEntityPath');
        await writeFile(
          remoteEntityPath,
          await (entity as io.File).readAsString(),
        );
        print('[BoardWS] Uploaded: $remoteEntityPath');
      }
    }
  }

  Future<void> downloadFolder(String remotePath, String localPath) async {
    final items = await lisFolderRecursive(path: remotePath);

    final localDir = io.Directory(localPath);
    if (!await localDir.exists()) {
      await localDir.create(recursive: true);
    }

    for (final item in items) {
      final relativePath = p
          .relative(item['path']!, from: remotePath)
          .replaceAll('\\', '/');
      final localItemPath = p.join(localPath, relativePath);

      if (item['type'] == 'folder') {
        await io.Directory(localItemPath).create(recursive: true);
      } else {
        print('[BoardWS] Downloading: ${item['path']}');
        final content = await getFileContent(item['path']!);
        await io.File(localItemPath).writeAsString(content);
        print('[BoardWS] Downloaded: $localItemPath');
      }
    }
  }

  TreeNode<FileSystemItem>? getFocusFileNode() {
    String focusNodeId =
        ref.read(boardFileTreeViewControllerProvider).selectedNodeId ?? "/";
    TreeNode<FileSystemItem>? focusNode = ref
        .read(boardFileTreeViewControllerProvider)
        .findNodeById(focusNodeId);
    if (focusNode?.data is FileItem) {
      return focusNode;
    } else {
      return null;
    }
  }

  TreeNode<FileSystemItem>? getFocusFolderNode() {
    String focusNodeId =
        ref.read(boardFileTreeViewControllerProvider).selectedNodeId ?? "/";
    TreeNode<FileSystemItem>? focusNode = ref
        .read(boardFileTreeViewControllerProvider)
        .findNodeById(focusNodeId);
    if (focusNode?.data is FolderItem) {
      return focusNode;
    } else {
      return ref
          .read(boardFileTreeViewControllerProvider)
          .findNodeById(path.dirname(focusNodeId));
    }
  }

  void clear() {
    state = const [];
  }
}

final StateNotifierProvider<
  BoardWorkspaceNotifier,
  List<TreeNode<FileSystemItem>>
>
boardWorkspaceProvider = StateNotifierProvider(
  (ref) => BoardWorkspaceNotifier(ref),
);
