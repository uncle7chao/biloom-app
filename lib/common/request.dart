import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

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

  Future<Response<T>> _download<T>(String url, ResponseType responseType) {
    final target = downloadTarget(url);
    final cancelToken = CancelToken();
    final options = Options(responseType: responseType, headers: target.headers);
    return _clashDio
        .getUri<T>(target.uri, options: options, cancelToken: cancelToken)
        .catchError((Object e) {
          // 内核端口拒连时的直连兜底：findProxy 是同步裁决，内核「宣称在跑」
          // 但端口实际没监听（启动竞态/连接失败退出后状态未回退）时，订阅
          // 请求会撞 Connection refused 且无法在 findProxy 层自救 —— 只能在
          // 请求层捕获后换直连重试。订阅地址大多国内可直连，回退不改变正常
          // 路径的行为。
          if (e is DioException && _isLocalPortRefused(e)) {
            commonPrint.log(
              'core port refused, falling back to direct fetch for $url',
              logLevel: LogLevel.warning,
            );
            return _directDio.getUri<T>(target.uri, options: options);
          }
          throw e;
        })
        .timeout(
          downloadTimeoutDuration,
          onTimeout: () {
            cancelToken.cancel();
            throw DioException.receiveTimeout(
              timeout: downloadTimeoutDuration,
              requestOptions: RequestOptions(path: url),
            );
          },
        );
  }

  Future<Response<Uint8List>> getFileResponseForUrl(String url) async {
    try {
      return await _download<Uint8List>(url, ResponseType.bytes);
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
      return await _download<String>(url, ResponseType.plain);
    } catch (e) {
      commonPrint.log(
        'getTextResponseForUrl error ${compactError(e)}',
        logLevel: LogLevel.warning,
      );
      rethrow;
    }
  }

  /// Null when this build is current; throws when GitHub cannot be asked.
  Future<Map<String, dynamic>?> checkForUpdate() async {
    final release = await latestRelease();
    final remoteVersion = release['tag_name'] as String;
    final version = globalState.packageInfo.version;
    final hasUpdate =
        compareVersions(remoteVersion.replaceAll('v', ''), version) > 0;
    return hasUpdate ? release : null;
  }

  /// The release page redirect still answers once the hourly API quota is spent.
  @visibleForTesting
  Future<Map<String, dynamic>> latestRelease() async {
    try {
      final response = await dio.get<Map<String, dynamic>>(
        'https://api.github.com/repos/$repository/releases/latest',
        options: Options(responseType: ResponseType.json),
      );
      return response.data!;
    } on DioException catch (error) {
      commonPrint.log(
        'latest release API failed: ${compactError(error)}',
        logLevel: LogLevel.warning,
      );
    }
    final response = await dio.get<void>(
      'https://github.com/$repository/releases/latest',
      options: Options(
        followRedirects: false,
        validateStatus: (status) => status != null && status < 400,
      ),
    );
    final location = response.headers.value(HttpHeaders.locationHeader);
    final segments = Uri.tryParse(location ?? '')?.pathSegments ?? const [];
    final tagIndex = segments.indexOf('tag') + 1;
    if (tagIndex == 0 || tagIndex >= segments.length) {
      throw FormatException('No release tag in the redirect', location);
    }
    return {'tag_name': segments[tagIndex]};
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

/// Some subscription servers send a gzip or zlib body without saying so in
/// Content-Encoding, which is the only signal dart:io decompresses on.
Uint8List decompressUnlabeled(Uint8List bytes) {
  final codec = switch (bytes) {
    [0x1f, 0x8b, ...] => gzip,
    [0x78, final flags, ...] when (0x78 << 8 | flags) % 31 == 0 => zlib,
    _ => null,
  };
  if (codec == null) {
    return bytes;
  }
  try {
    return Uint8List.fromList(codec.decode(bytes));
  } on FormatException {
    return bytes;
  }
}

/// dart:io turns [Uri.userInfo] into Basic credentials still percent-encoded.
@visibleForTesting
({Uri uri, Map<String, Object> headers}) downloadTarget(String url) {
  final uri = url.webUri ?? Uri.parse(url);
  if (uri.userInfo.isEmpty) {
    return (uri: uri, headers: const {});
  }
  final credentials = uri.userInfo.split(':').map(_decodeUserInfo).join(':');
  return (
    uri: uri.replace(userInfo: ''),
    headers: {
      HttpHeaders.authorizationHeader:
          'Basic ${base64.encode(utf8.encode(credentials))}',
    },
  );
}

String _decodeUserInfo(String value) {
  try {
    return Uri.decodeComponent(value);
  } on ArgumentError {
    return value;
  }
}

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

/// fork 兼容：三态检查更新（上游把「无新版」和「失败」混为 null）。
enum UpdateCheckStatus {
  hasUpdate,
  upToDate,
  failed,
}

class UpdateCheckResult {
  const UpdateCheckResult(this.status, [this.data]);

  final UpdateCheckStatus status;
  final Map<String, dynamic>? data;
}
