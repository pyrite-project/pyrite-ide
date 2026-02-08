import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pyrite_ide/core/services/android_env_deployer/main.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/pylsp/main.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class PythonDeployer {
  static const String pythonAssetPath = 'assets/android/python_env.zip';

  late Directory appDocDir;
  late Directory pythonDir;
  late Directory binDir;
  late Directory libDir;
  late File pythonExecutable;
  late final env = Map<String, String>.from(Platform.environment);

  final CodeLineEditingController printController = CodeLineEditingController();

  void print(String message) {
    printController.text = '${printController.text}\n$message';
  }

  Future<void> initialize() async {
    Future(() => container.read(state.notifier).state = true);
    printController.readOnly();
    try {
      appDocDir = await getApplicationDocumentsDirectory();
      pythonDir = Directory(path.join(appDocDir.path, 'python'));
      binDir = Directory(path.join(pythonDir.path, 'bin'));
      libDir = Directory(path.join(pythonDir.path, 'lib'));
      pythonExecutable = File(path.join(binDir.path, 'python3.12'));
      env['LD_LIBRARY_PATH'] = [
        binDir.path,
        libDir.path,
        '/system/lib64',
        '/system/lib64',
        '/system/lib',
        '/vendor/lib64',
        '/vendor/lib',
        if (env.containsKey('LD_LIBRARY_PATH')) env['LD_LIBRARY_PATH']!,
      ].join(':');
      env['TERMUX_PREFIX'] = pythonDir.path;
      env['PREFIX'] = pythonDir.path;
      env['PYTHONHOME'] = pythonDir.path;
      env['PYTHONPATH'] = path.join(libDir.path, 'python3.12', 'site-packages');

      print('Python directory: ${pythonDir.path}');
      print('Python executable: ${pythonExecutable.path}');
      print('Environment: ${env.toString()}');

      if (await pythonExecutable.exists() &&
          await isPackageInstalled("pylsp")) {
        print('Python Env already deployed');
        container.read(lspClientProvider);
        Future(() => container.read(state.notifier).state = false);
        // await testPython();
        return;
      }
      await deployPython();
      Future(() => container.read(state.notifier).state = false);
    } catch (e) {
      print('Python initialization failed: $e');
      rethrow;
    }

    // context.go("/index");
  }

  Future<void> deployPython() async {
    try {
      print('Deploying start');
      final ByteData data = await rootBundle.load(pythonAssetPath);
      final Uint8List bytes = data.buffer.asUint8List();
      Archive archive = ZipDecoder().decodeBytes(bytes);

      for (final file in archive) {
        if (file.isFile) {
          final filename = file.name;
          final data = file.content as List<int>;
          final outputFile = File(path.join(pythonDir.path, filename));
          await outputFile.parent.create(recursive: true);
          await outputFile.writeAsBytes(data);
          await setExecutable(outputFile);
        }
      }

      print('Successfully released the assets. Next step. (1/5)');

      archive = ZipDecoder().decodeBytes(
        await File('${binDir.path}.zip').readAsBytes(),
      );

      for (final file in archive) {
        if (file.isFile) {
          final filename = file.name;
          final data = file.content as List<int>;
          final outputFile = File(path.join(binDir.path, filename));
          await outputFile.parent.create(recursive: true);
          await outputFile.writeAsBytes(data);
          await setExecutable(outputFile);
        }
      }

      print('Successfully deployed Python bin. Next step. (2/5)');

      archive = ZipDecoder().decodeBytes(
        await File('${libDir.path}.zip').readAsBytes(),
      );

      for (final file in archive) {
        if (file.isFile) {
          final filename = file.name;
          final data = file.content as List<int>;
          final outputFile = File(path.join(libDir.path, filename));
          await outputFile.parent.create(recursive: true);
          await outputFile.writeAsBytes(data);
          await setExecutable(outputFile);
        }
      }

      print('Successfully deployed Python lib (50%). Next step. (3/5)');
      print('下一步将部署大量 Python 标准库文件，等待时间较长，请耐心等待');

      archive = ZipDecoder().decodeBytes(
        await File(path.join(libDir.path, 'python3.12.zip')).readAsBytes(),
      );

      for (final file in archive) {
        if (file.isFile) {
          final filename = file.name;
          final data = file.content as List<int>;
          final outputFile = File(
            path.join(libDir.path, 'python3.12', filename),
          );
          await outputFile.parent.create(recursive: true);
          await outputFile.writeAsBytes(data);
          await setExecutable(outputFile);
        }
      }

      print('Successfully deployed Python lib (100%). Next step. (4/5)');
    } catch (e) {
      print('Failed to deploy Python: $e');
      rethrow;
    }
  }

  Future<void> setExecutable(File file) async {
    try {
      await Process.run('chmod', ['777', file.path]);
    } catch (e) {
      print('Warning: Failed to set executable: $e');
    }
  }

  Future<void> testPython() async {
    try {
      print('Testing Python installation...');
      final result = await Process.run(pythonExecutable.path, [
        '--version',
      ], environment: env);

      if (result.exitCode == 0) {
        print('Python version: ${result.stdout}');
      } else {
        throw Exception('Python test failed: ${result.stderr}');
      }

      final testResult = await Process.run(pythonExecutable.path, [
        '-c',
        'import pylsp; print(f"Python {pylsp} ready!")',
      ], environment: env);

      print('Python execution test: ${testResult.stdout}');
    } catch (e) {
      print('Python test failed: $e');
      rethrow;
    }
  }

  /// 获取 Python 可执行文件路径
  String getPythonPath() {
    return pythonExecutable.path;
  }

  /// 执行 Python 代码
  Future<ProcessResult> executePython({
    String? script,
    List<String> args = const [],
    String? workingDirectory,
  }) async {
    final pythonPath = getPythonPath();

    if (script != null) {
      return await Process.run(
        pythonPath,
        ['-c', script, ...args],
        workingDirectory: workingDirectory ?? pythonDir.path,
        runInShell: true,
        environment: env,
      );
    } else {
      return await Process.run(
        pythonPath,
        args,
        workingDirectory: workingDirectory ?? pythonDir.path,
        runInShell: true,
        environment: env,
      );
    }
  }

  Future<bool> installPipPackage(String package) async {
    try {
      print('Installing $package');

      final result = await executePython(
        args: ['-m', 'pip', 'install', package],
      );

      if (result.exitCode == 0) {
        print('$package installed successfully (5/5)');
        return true;
      } else {
        print('Failed to install $package: ${result.stderr}');
        return false;
      }
    } catch (e) {
      print('Installation error: $e');
      return false;
    }
  }

  Future<bool> isPackageInstalled(String package) async {
    try {
      final result = await executePython(
        script:
            '''
try:
    import $package
    print("INSTALLED")
except ImportError:
    print("NOT_INSTALLED")
''',
      );

      return result.stdout.toString().contains('INSTALLED');
    } catch (e) {
      return false;
    }
  }
}

// 全局单例
PythonDeployer pythonDeployer = PythonDeployer();
