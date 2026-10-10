import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';

/// 检查更新的三种结局。
///
/// 三态是**必须**的，不是洁癖：上游把「没有新版本」和「请求失败」都表示成 `null`，
/// 于是手动点「检查更新」时，仓库 404、断网、GitHub API 限流全都会被显示成
/// **「当前应用已经是最新版了」** —— 把一次失败说成了成功。用户据此以为自己在用最新版，
/// 而这恰好是最需要他知道「我查不到」的场景。
enum UpdateCheckStatus {
  hasUpdate,
  upToDate,
  failed,
}

/// [`checkForUpdate`] 的返回值。`data` 仅在 [UpdateCheckStatus.hasUpdate] 时非空。
class UpdateCheckResult {
  const UpdateCheckResult(this.status, [this.data]);

  final UpdateCheckStatus status;
  final Map<String, dynamic>? data;
}

class Request {
  late final Dio dio;
  late final Dio _clashDio;
  late final Dio _directDio;
  String? userAgent;

  ProviderReader? _read;

  void attach(ProviderReader read) {
    _read = read;
  }

  Request() {
    dio = Dio(BaseOptions(headers: {'User-Agent': browserUa}));
    // 订阅下载必须有上界。Dio 默认的 receiveTimeout 是 null，也就是无限等待 ——
    // 服务端接受连接后迟迟不吐数据时，配置页会永远停在转圈上，「全部更新」按钮
    // 从此变哑，连删除菜单都点不出来，只能重启应用。
    _clashDio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    _clashDio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.findProxy = (Uri uri) {
          client.userAgent = globalState.ua;
          final read = _read;
          if (read == null) {
            return 'DIRECT';
          }
          return BiLoomHttpOverrides.findProxyForReader(read, uri);
        };
        return client;
      },
    );
    // 内核端口拒连时的直连兜底：findProxy 是同步裁决，内核「宣称在跑」但端口
    // 实际没监听（启动竞态/连接失败退出后状态未回退）时，订阅请求会撞
    // Connection refused 且无法在 findProxy 层自救 —— 只能在请求层捕获后换
    // 直连重试。订阅地址大多国内可直连，回退不改变正常路径的行为。
    _directDio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 60),
        headers: {'User-Agent': browserUa},
      ),
    );
    _directDio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.findProxy = (Uri uri) => 'DIRECT';
        return client;
      },
    );
  }

  /// 内核内部端口的 Connection refused：findProxy 把请求指向了
  /// `localhost:mixedPort` 但内核没在监听（状态不同步）。此时换直连重试。
  bool _isLocalPortRefused(DioException e) {
    final error = e.error;
    if (error is! SocketException) {
      return false;
    }
    final host = error.address?.host.toLowerCase();
    return (host == 'localhost' || host == '127.0.0.1' || host == '::1');
  }

  Future<Response<T>> _getWithDirectFallback<T extends Object?>(
    String url,
    Options options,
  ) async {
    try {
      return await _clashDio.get<T>(url, options: options);
    } on DioException catch (e) {
      if (!_isLocalPortRefused(e)) {
        rethrow;
      }
      commonPrint.log(
        'core port refused, falling back to direct fetch for $url',
        logLevel: LogLevel.warning,
      );
      return _directDio.get<T>(url, options: options);
    }
  }

  Future<Response<Uint8List>> getFileResponseForUrl(String url) async {
    try {
      return await _getWithDirectFallback<Uint8List>(
        url,
        Options(responseType: ResponseType.bytes),
      );
    } catch (e) {
      commonPrint.log(
        'getFileResponseForUrl error ${compactError(e)}',
        logLevel: LogLevel.warning,
      );
      rethrow;
    }
  }

  Future<Response<String>> getTextResponseForUrl(String url) async {
    try {
      return await _getWithDirectFallback<String>(
        url,
        Options(responseType: ResponseType.plain),
      );
    } catch (e) {
      commonPrint.log(
        'getTextResponseForUrl error ${compactError(e)}',
        logLevel: LogLevel.warning,
      );
      rethrow;
    }
  }

  Future<UpdateCheckResult> checkForUpdate() async {
    try {
      final response = await dio.get(
        'https://api.github.com/repos/$repository/releases/latest',
        options: Options(responseType: ResponseType.json),
      );
      if (response.statusCode != 200) {
        return const UpdateCheckResult(UpdateCheckStatus.failed);
      }
      final data = response.data as Map<String, dynamic>;
      final remoteVersion = data['tag_name'];
      final version = globalState.packageInfo.version;
      final hasUpdate =
          compareVersions(remoteVersion.replaceAll('v', ''), version) > 0;
      return hasUpdate
          ? UpdateCheckResult(UpdateCheckStatus.hasUpdate, data)
          : const UpdateCheckResult(UpdateCheckStatus.upToDate);
    } catch (e) {
      commonPrint.log('checkForUpdate failed', logLevel: LogLevel.warning);
      return const UpdateCheckResult(UpdateCheckStatus.failed);
    }
  }

  final Map<String, IpInfo Function(Map<String, dynamic>)> _ipInfoSources = {
    'https://ipwho.is': IpInfo.fromIpWhoIsJson,
    'https://api.myip.com': IpInfo.fromMyIpJson,
    'https://ipapi.co/json': IpInfo.fromIpApiCoJson,
    'https://ident.me/json': IpInfo.fromIdentMeJson,
    'http://ip-api.com/json': IpInfo.fromIpAPIJson,
    'https://api.ip.sb/geoip': IpInfo.fromIpSbJson,
    'https://ipinfo.io/json': IpInfo.fromIpInfoIoJson,
  };

  Future<Result<IpInfo?>> checkIp({CancelToken? cancelToken}) async {
    var failureCount = 0;
    final token = cancelToken ?? CancelToken();
    final futures = _ipInfoSources.entries.map((source) async {
      final Completer<Result<IpInfo?>> completer = Completer();
      void handleFailRes() {
        if (!completer.isCompleted && failureCount == _ipInfoSources.length) {
          completer.complete(Result.success(null));
        }
      }

      final future = dio
          .get<Map<String, dynamic>>(
            source.key,
            cancelToken: token,
            options: Options(responseType: ResponseType.json),
          )
          .timeout(const Duration(seconds: 10));
      unawaited(
        future
            .then((res) {
              if (res.statusCode == HttpStatus.ok && res.data != null) {
                completer.complete(Result.success(source.value(res.data!)));
                return;
              }
              commonPrint.log('checkIp data empty', logLevel: LogLevel.info);
              failureCount++;
              handleFailRes();
            })
            .catchError((e) {
              failureCount++;
              if (e is DioException && e.type == DioExceptionType.cancel) {
                completer.complete(Result.error('cancelled'));
                return;
              }
              commonPrint.log('checkIp error $e', logLevel: LogLevel.warning);
              handleFailRes();
            }),
      );
      return completer.future;
    });
    final res = await Future.any(futures);
    token.cancel();
    return res;
  }
}

final request = Request();

String? getFileNameForDisposition(String? disposition) {
  if (disposition == null) return null;
  final parseValue = HeaderValue.parse(disposition);
  final parameters = parseValue.parameters;
  final fileNamePointKey = parameters.keys.firstWhere(
    (key) => key == 'filename*',
    orElse: () => '',
  );
  if (fileNamePointKey.isNotEmpty) {
    final res = parameters[fileNamePointKey]?.split("''") ?? [];
    if (res.length >= 2) {
      return Uri.decodeComponent(res[1]);
    }
  }
  final fileNameKey = parameters.keys.firstWhere(
    (key) => key == 'filename',
    orElse: () => '',
  );
  if (fileNameKey.isEmpty) return null;
  return parameters[fileNameKey];
}
