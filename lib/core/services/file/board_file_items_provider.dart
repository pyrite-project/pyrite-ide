import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/models/file.dart';
import 'package:pyrite_ide/core/services/board_manager/serial_data_callbacks_provider.dart';
import 'package:pyrite_ide/core/services/board_manager/utils.dart';
import 'package:pyrite_ide/core/services/file/board_utils.dart';
import 'package:pyrite_ide/shared/toly_tree.dart';

class BoardFileItemsNotifier
    extends StateNotifier<List<TreeNode<BoardFileTreeItem>>> {
  final Ref ref;

  BoardFileItemsNotifier(this.ref) : super(const []);

  Future<String> _getCommandResult(String command) async {
    final completer = Completer<String>();
    String result = "";
    bool completed = false;

    void callback(Uint8List data) {
      if (completed) return;

      final decoded = utf8.decode(data);
      print("Received chunk: $decoded");
      result += decoded;
      if (decoded.contains("!@#PyriteIDEEnd#@!")) {
        print("Full data received, length: ${result.length}");
        completed = true;
        completer.complete(result);

        // 移除当前callback
        ref.read(serialDataCallbacksProvider.notifier).remove(callback);
      }
    }

    ref.read(serialDataCallbacksProvider.notifier).add(callback);

    try {
      ref.read(getUsbSerialProvider().notifier).enterRawRepl();
      await Future.delayed(Duration(milliseconds: 50));

      ref.read(getUsbSerialProvider().notifier).sendCommand("\x04");
      await Future.delayed(Duration(milliseconds: 50));

      ref.read(getUsbSerialProvider().notifier).sendCommand(command);
      await Future.delayed(Duration(milliseconds: 100));

      ref.read(getUsbSerialProvider().notifier).sendCommand("\x04");

      final res = await completer.future.timeout(
        Duration(milliseconds: 10000),
        onTimeout: () => result,
      );

      return res;
    } finally {
      completed = true;

      ref.read(serialDataCallbacksProvider.notifier).remove(callback);

      ref.read(getUsbSerialProvider().notifier).exitRawRepl();
    }
  }

  Future<String> getCommandResult(String command) async {
    String originalData = await _getCommandResult(command);

    // print(originalData);

    final String startIdentifier = "!@#PyriteIDEStart#@!";
    final String endIdentifier = "!@#PyriteIDEEnd#@!";

    final int startIdentifierIndex = originalData.indexOf(startIdentifier);
    final int endIdentifierIndex = originalData.indexOf(endIdentifier);

    final List<int> startIdentifierPosition = [
      startIdentifierIndex,
      startIdentifierIndex + startIdentifier.length,
    ];
    final List<int> endIdentifierPosition = [
      endIdentifierIndex,
      endIdentifierIndex + endIdentifier.length,
    ];

    String resultString = originalData.substring(
      startIdentifierPosition[1],
      endIdentifierPosition[0],
    );
    // print(resultString);

    return resultString;
  }

  Future<List<Map<String, String>>> getFilesList({String path = "/"}) async {
    String command = "import uos\n";
    command += "try:\n";
    command += "  l=[]\n";
    command += "  for f in uos.ilistdir('$path'):\n";
    command +=
        '    l.append({"path": "${(path[path.length - 1] != '/') ? '$path/' : path}"+f[0], "name": f[0], "type": "folder" if f[1]==0x4000 else "file"})\n';
    command += "  print('!@#PyriteIDEStart#@!'+str(l)+'!@#PyriteIDEEnd#@!')\n";
    command += "except OSError:\n";
    command += "  print([])\n";
    var originalData = await getCommandResult(command);
    return (jsonDecode(originalData.replaceAll("'", "\"")) as List)
        .cast<Map<String, dynamic>>()
        .map((map) => map.map((key, value) => MapEntry(key, value.toString())))
        .toList();
  }

  Future<List<TreeNode<BoardFileTreeItem>>> buildRootFileListItems() async {
    List<TreeNode<BoardFileTreeItem>> items = await buildFileListItems(
      await getFilesList(),
    );
    state = items;

    return items;
  }

  Future<String> getFileContent(String path) async {
    String command = "try:\n";
    command += "  with open('$path', 'r') as f:\n";
    command +=
        "    print('!@#PyriteIDEStart#@!'+f.read()+'!@#PyriteIDEEnd#@!')\n";
    command += "except Exception as e:\n";
    command += "  print('$path', e)\n";
    String contentString = await _getCommandResult(command);
    String resultString = contentString
        .split("!@#PyriteIDEStart#@!")[1]
        .split("!@#PyriteIDEEnd#@!")[0];
    return resultString;
  }

  Future<String> saveFile(String path, String content) async {
    print("debug: saveFile with path $path, content length ${content.length}");
    String command = "try:\n";
    command += "  with open('$path', 'w') as f:\n";
    command += "    f.write('''$content''')\n";
    command +=
        "    print('!@#PyriteIDEStart#@!SaveFileSuccessfully!@#PyriteIDEEnd#@!')\n";
    command += "except Exception as e:\n";
    command += "  print('$path', e)\n";
    String contentString = await _getCommandResult(command);
    String resultString = contentString
        .split("!@#PyriteIDEStart#@!")[1]
        .split("!@#PyriteIDEEnd#@!")[0];
    return resultString;
  }

  void clear() {
    state = const [];
  }
}

final StateNotifierProvider<
  BoardFileItemsNotifier,
  List<TreeNode<BoardFileTreeItem>>
>
boardFileItemsProvider = StateNotifierProvider(
  (ref) => BoardFileItemsNotifier(ref),
);
