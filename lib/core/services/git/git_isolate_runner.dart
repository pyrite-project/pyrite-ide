import 'dart:async';
import 'dart:isolate';

import 'package:git2dart/git2dart.dart';
import 'package:pyrite_ide/core/services/git/git_debug_log.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';

/// 跨 isolate 传递的失败描述。
///
/// git2dart 的异常对象（`Error` 子类、携带原生指针的包装对象）不适合作为
/// isolate 消息直接传递，因此工作 isolate 只回传纯数据；主 isolate 再根据
/// [code] 还原成原始异常类型，调用方（provider/UI）拿到的仍然是
/// `GitCheckoutBlockedException` 这类可判定的异常。
class GitJobFailure {
  const GitJobFailure({
    required this.code,
    required this.message,
    this.paths = const [],
    this.stack = '',
    this.isError = false,
  });

  /// 稳定分类码，例如 `blocked`、`argument`、`state`、`other`。
  final String code;

  final String message;

  /// 仅 `blocked` 分类使用：会被切换分支覆盖的路径。
  final List<String> paths;

  /// 工作 isolate 内的堆栈文本，仅用于调试日志。
  final String stack;

  /// 原始异常是 `Error` 还是 `Exception`，用于还原时保持语义。
  final bool isError;

  @override
  String toString() => 'GitJobFailure($code, $message)';
}

/// 把工作 isolate 内的异常映射成可传输的 [GitJobFailure]。
typedef GitJobErrorDescriber =
    GitJobFailure Function(Object error, StackTrace stackTrace);

/// 承载 [GitJobFailure] 的异常，由服务层还原成具体异常类型。
class GitJobFailureException implements Exception {
  const GitJobFailureException(this.failure);

  final GitJobFailure failure;

  @override
  String toString() => failure.message;
}

class _JobReply {
  const _JobReply({this.value, this.failure});

  final Object? value;
  final GitJobFailure? failure;
}

/// 工作 isolate 的消息载荷：任务 + 错误分类器 + 回信端口。
class _GitJob {
  const _GitJob({
    required this.body,
    required this.describeError,
    required this.reply,
    required this.debugLabel,
  });

  final FutureOr<Object?> Function() body;
  final GitJobErrorDescriber describeError;
  final SendPort reply;
  final String debugLabel;
}

/// 在一次性后台 isolate 中执行 [body]，并把结果/错误带回当前 isolate。
///
/// 设计取舍：
/// - 使用 `Isolate.spawn` 而不是 `Isolate.run`：需要显式 `onError`、超时后
///   `kill`，以及在工作 isolate 结束时调用 `Libgit2.shutdown()` 归还本
///   isolate 的初始化计数，`Isolate.run` 不提供这些钩子。
/// - [body] 是普通闭包，可以捕获 `this`（服务实例）；不要捕获不可发送的对象
///   （`ReceivePort`、原生指针、`Repository` 等）。
/// - 超时通过 `kill` 放弃 isolate。libgit2 的同步原生调用无法在中途打断，
///   因此“超时”表示不再等待结果，而不是回滚已经写入磁盘的内容；调用方应以
///   刷新 snapshot 的方式确认真实仓库状态。
Future<T> runGitJob<T>(
  FutureOr<Object?> Function() body, {
  required Duration timeout,
  required GitJobErrorDescriber describeError,
  String debugLabel = 'git job',
}) async {
  final resultPort = ReceivePort();
  final errorPort = ReceivePort();
  final completer = Completer<T>();
  StreamSubscription<Object?>? errorSubscription;

  Isolate? isolate;
  try {
    isolate = await Isolate.spawn<_GitJob>(
      _gitJobEntry,
      _GitJob(
        body: body,
        describeError: describeError,
        reply: resultPort.sendPort,
        debugLabel: debugLabel,
      ),
      onError: errorPort.sendPort,
      debugName: 'pyrite-git-$debugLabel',
    );

    resultPort.listen((Object? message) {
      if (completer.isCompleted) return;
      final reply = message! as _JobReply;
      final failure = reply.failure;
      if (failure != null) {
        completer.completeError(GitJobFailureException(failure));
        return;
      }
      completer.complete(reply.value as T);
    });

    errorSubscription = errorPort.listen((Object? message) {
      // 只有工作 isolate 抛出未捕获错误才会走到这里；正常失败已由 body 的
      // try/catch 转成 _JobReply 回传，因此这里属于兜底。
      if (completer.isCompleted) return;
      final parts = message is List && message.isNotEmpty
          ? message.map((part) => '$part').toList()
          : ['$message'];
      completer.completeError(
        GitJobFailureException(
          GitJobFailure(
            code: 'isolate',
            message: parts.first,
            stack: parts.length > 1 ? parts[1] : '',
            isError: true,
          ),
        ),
      );
    });

    return await completer.future.timeout(timeout);
  } on TimeoutException {
    GitDebugLog.log(
      'runGitJob timeout label=$debugLabel timeout=${timeout.inMilliseconds}ms',
    );
    throw TimeoutException(
      I18nKey.gitIsolateTimeout.fallback
          .replaceAll('{seconds}', '${timeout.inSeconds}')
          .replaceAll('{label}', debugLabel),
      timeout,
    );
  } finally {
    resultPort.close();
    await errorSubscription?.cancel();
    errorPort.close();
    isolate?.kill(priority: Isolate.immediate);
  }
}

Future<void> _gitJobEntry(_GitJob job) async {
  _JobReply reply;
  try {
    reply = _JobReply(value: await job.body());
  } catch (error, stackTrace) {
    try {
      reply = _JobReply(failure: job.describeError(error, stackTrace));
    } catch (describeError, describeStackTrace) {
      reply = _JobReply(
        failure: GitJobFailure(
          code: 'other',
          message: '$error',
          stack: '$stackTrace\n$describeError\n$describeStackTrace',
        ),
      );
    }
  }

  try {
    job.reply.send(reply);
  } catch (sendError, sendStackTrace) {
    // 结果不可跨 isolate 传递属于编程错误：尽力把原因回传，避免主 isolate
    // 只能看到一个没有信息的超时。
    job.reply.send(
      _JobReply(
        failure: GitJobFailure(
          code: 'unserializable',
          message: 'Git 任务返回值无法跨 isolate 传递：${reply.value} / $sendError',
          stack: '$sendStackTrace',
        ),
      ),
    );
  }

  // 每个 isolate 各自加载一份 libgit2；结束时归还本 isolate 的初始化计数。
  // 若任务异常退出仍持有原生 owner，shutdown 会抛错；此时忽略即可，该
  // isolate 即将销毁，进程退出时 libgit2 会自行清理。
  try {
    Libgit2.shutdown();
  } catch (error) {
    GitDebugLog.log(
      'runGitJob shutdown skipped label=${job.debugLabel}',
      error: error,
    );
  }
}
