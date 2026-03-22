import 'dart:async';
import 'package:flutter/foundation.dart';

/// 全局定期任务管理器
class PeriodicTaskManager {
  final Map<String, Timer> _timers = {};
  bool _paused = false;

  /// 注册一个定期任务
  /// [name] 任务唯一标识
  /// [interval] 执行间隔
  /// [callback] 要执行的函数（同步）
  /// 返回是否注册成功（同名已存在则返回 false）
  bool registerTask({
    required String name,
    required Duration interval,
    required VoidCallback callback,
  }) {
    if (_timers.containsKey(name)) {
      debugPrint('PeriodicTaskManager: Task "$name" already exists');
      return false;
    }
    final timer = Timer.periodic(interval, (_) {
      if (_paused) return;
      try {
        callback();
      } catch (e, stack) {
        debugPrint('PeriodicTaskManager: Error in task "$name": $e\n$stack');
      }
    });
    _timers[name] = timer;
    return true;
  }

  /// 注销指定任务
  void unregisterTask(String name) {
    _timers.remove(name)?.cancel();
  }

  /// 暂停所有任务
  void pause() {
    if (_paused) return;
    _paused = true;
    debugPrint('PeriodicTaskManager: Paused');
  }

  /// 恢复所有任务
  void resume() {
    if (!_paused) return;
    _paused = false;
    debugPrint('PeriodicTaskManager: Resumed');
  }

  /// 销毁所有任务，释放资源
  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _paused = false;
  }
}
