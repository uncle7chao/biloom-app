import 'package:dio/dio.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/state.dart';
import 'package:material_ui/material_ui.dart';

String compactError(Object error) {
  if (error is DioException) {
    final statusCode = error.response?.statusCode;
    final code = statusCode != null ? ', HTTP $statusCode' : '';
    // 底层原因（SocketException: Failed host lookup / Connection timed out
    // 这类）必须带上 —— 只打 type 名没法区分「DNS 挂了」和「连不上」。
    final inner = error.error ?? error.message;
    return inner != null && inner.toString().isNotEmpty
        ? 'DioException(${error.type.name}$code: $inner)'
        : 'DioException(${error.type.name}$code)';
  }
  return error.toString();
}

class CommonPrint {
  static CommonPrint? _instance;

  CommonPrint._internal();

  factory CommonPrint() {
    _instance ??= CommonPrint._internal();
    return _instance!;
  }

  void log(String? text, {LogLevel logLevel = LogLevel.info}) {
    final payload = '[APP] $text';
    debugPrint(payload);
    if (!globalState.isAttach) {
      return;
    }
    globalState.container
        .read(logsProvider.notifier)
        .add(Log.app(payload).copyWith(logLevel: logLevel));
  }
}

final commonPrint = CommonPrint();
