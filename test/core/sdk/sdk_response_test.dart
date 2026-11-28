import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/api/sdk_response.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';

/// 锁定 SDK 响应封装的线上格式：`respondOk` / `respondError` 必须产出
/// `sdk.response.ok` / `sdk.response.error` 且把请求 id 映射到 `replyTo`。
/// 这两个函数是 `lib/core/sdk/api/**` 里所有命令处理器的统一出口。
void main() {
  Map<String, dynamic> capture({
    Map<String, dynamic>? envelope,
    Object? data,
    String? errorMessage,
  }) {
    late Map<String, dynamic> received;
    final request = envelope ?? {'id': 'req-1', 'type': 'sdk.test'};
    void respond(Map<String, dynamic> result) => received = result;
    if (errorMessage != null) {
      respondError(request, respond, errorMessage);
    } else {
      respondOk(request, respond, data: data);
    }
    return received;
  }

  test('respondOk 回写成功类型与 payload.data', () {
    final result = capture(data: {'value': 42});
    expect(result['type'], SdkCommands.responseOk);
    expect(result['payload'], {
      'data': {'value': 42},
    });
    expect(result['replyTo'], 'req-1');
  });

  test('respondOk 保留 data 为 null 的语义', () {
    final result = capture();
    expect(result['type'], SdkCommands.responseOk);
    expect(result['payload'], {'data': null});
    expect(result.containsKey('data'), isFalse);
  });

  test('respondError 回写错误类型与 message', () {
    final result = capture(errorMessage: '设备未连接');
    expect(result['type'], SdkCommands.responseError);
    expect(result['payload'], {'message': '设备未连接'});
    expect(result['replyTo'], 'req-1');
  });

  test('请求缺少 id 时 replyTo 为 null', () {
    final result = capture(envelope: {'type': 'sdk.test'});
    expect(result['replyTo'], isNull);
  });
}
