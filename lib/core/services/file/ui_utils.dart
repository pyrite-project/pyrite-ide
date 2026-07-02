import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/core/services/file/upload_and_download_diff.dart';
import 'package:pyrite_ide/core/services/message/ide_message.dart';

void showEditorSnackBar(BuildContext context, String message) {
  showIdeSuccess(context, message);
}

/// Shows a prominent Thonny-style dialog when the device is not in REPL state.
/// Returns true if the user chose to send CTRL-C, false if dismissed.
Future<bool> showDeviceNotReadyDialog(
  BuildContext context, {
  required String operation,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => AlertDialog(
      icon: Icon(
        Icons.warning_amber_rounded,
        size: 48,
        color: Theme.of(ctx).colorScheme.error,
      ),
      title: const Text("设备未就绪"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("无法执行「$operation」："),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(ctx).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              "设备未处于 REPL 状态，无法执行文件操作。\n\n"
              "可能原因：\n"
              "· 设备正在运行程序\n"
              "· 固件崩溃或卡死\n"
              "· 串口通信异常",
              style: TextStyle(
                color: Theme.of(ctx).colorScheme.onErrorContainer,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            "请在终端中按 CTRL-C 停止程序，或点击下方按钮发送中断信号。",
            style: TextStyle(fontSize: 13),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => ctx.pop(false),
          child: const Text("取消"),
        ),
        FilledButton.icon(
          onPressed: () => ctx.pop(true),
          icon: const Icon(Icons.stop_circle_outlined, size: 18),
          label: const Text("发送 CTRL-C"),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<bool> showDiffConfirmDialog(
  BuildContext context, {
  required DiffInfo diff,
  required String targetPath,
  required bool isUpload,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.difference),
      title: Text(isUpload ? "确认上传" : "确认下载"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("${isUpload ? "上传" : "下载"}到：$targetPath"),
          const SizedBox(height: 8),
          Text("${diff.addCount} 处添加，${diff.removeCount} 处删除"),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(
                  diff.unifiedLines.join('\n'),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => ctx.pop(false), child: const Text("取消")),
        FilledButton(
          onPressed: () => ctx.pop(true),
          child: Text(isUpload ? "上传" : "下载"),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<bool> confirmDelete(BuildContext context, String name) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.delete_outline),
      title: const Text("删除项目"),
      content: Text("确定要删除“$name”吗？此操作无法直接撤销。"),
      actions: [
        TextButton(
          onPressed: () => context.pop(false),
          child: const Text("取消"),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => context.pop(true),
          child: const Text("删除"),
        ),
      ],
    ),
  );
  return result ?? false;
}
