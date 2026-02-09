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

  void _debugLog(String message) {
    printController.text = '${printController.text}\n$message';
    print(message);
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

      _debugLog('Python directory: ${pythonDir.path}');
      _debugLog('Python executable: ${pythonExecutable.path}');
      _debugLog('Environment: ${env.toString()}');

      if (await pythonExecutable.exists() &&
          await isPackageInstalled("pylsp")) {
        _debugLog('Python Env already deployed');
        Future(() => container.read(state.notifier).state = false);
        // await testPython();
        return;
      }
      await deployPython();
      Future(() => container.read(state.notifier).state = false);
    } catch (e) {
      _debugLog('Python initialization failed: $e');
      rethrow;
    }

    // context.go("/index");
  }

  Future<void> deployPython() async {
    try {
      _debugLog('Deploying start');
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

      _debugLog('Successfully released the assets. Next step. (1/5)');

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

      _debugLog('Successfully deployed Python bin. Next step. (2/5)');

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

      _debugLog('Successfully deployed Python lib (50%). Next step. (3/5)');
      _debugLog('下一步将部署大量 Python 标准库文件，等待时间较长，请耐心等待');

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

      _debugLog('Successfully deployed Python lib (100%). Next step. (4/5)');
    } catch (e) {
      _debugLog('Failed to deploy Python: $e');
      rethrow;
    }
  }

  Future<void> setExecutable(File file) async {
    try {
      await Process.run('chmod', ['777', file.path]);
    } catch (e) {
      _debugLog('Warning: Failed to set executable: $e');
    }
  }

  Future<void> testPython() async {
    try {
      _debugLog('Testing Python installation...');
      final result = await Process.run(pythonExecutable.path, [
        '--version',
      ], environment: env);

      if (result.exitCode == 0) {
        _debugLog('Python version: ${result.stdout}');
      } else {
        throw Exception('Python test failed: ${result.stderr}');
      }

      final testResult = await Process.run(pythonExecutable.path, [
        '-c',
        'import pylsp; print(f"Python {pylsp} ready!")',
      ], environment: env);

      _debugLog('Python execution test: ${testResult.stdout}');
    } catch (e) {
      _debugLog('Python test failed: $e');
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
      _debugLog('Installing $package');

      final result = await executePython(
        args: ['-m', 'pip', 'install', package],
      );

      if (result.exitCode == 0) {
        _debugLog('$package installed successfully (5/5)');
        return true;
      } else {
        _debugLog('Failed to install $package: ${result.stderr}');
        return false;
      }
    } catch (e) {
      _debugLog('Installation error: $e');
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
