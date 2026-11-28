import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';

/// SDK 命令响应的统一封装。
///
/// `lib/core/sdk/api/**` 下的每个命令处理器都需要回 `sdk.response.ok` /
/// `sdk.response.error`。历史上这段 envelope 拼装被复制到了 11 个文件里
/// （`_respondOk` 11 份、`_respondError` 8 份），升级协议时极易漏改。
/// 现在统一走 [makeEnvelope]，出站字段由
/// `PluginRunManager._prepareOutgoing` 再做一次规范化。
void respondOk(
  Map<String, dynamic> envelope,
  void Function(Map<String, dynamic>) respond, {
  Object? data,
}) {
  respond(
    makeEnvelope(
      type: SdkCommands.responseOk,
      payload: {'data': data},
      replyTo: envelope['id']?.toString(),
    ),
  );
}

void respondError(
  Map<String, dynamic> envelope,
  void Function(Map<String, dynamic>) respond,
  String message,
) {
  respond(
    makeEnvelope(
      type: SdkCommands.responseError,
      payload: {'message': message},
      replyTo: envelope['id']?.toString(),
    ),
  );
}
