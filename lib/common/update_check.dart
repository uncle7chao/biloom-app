import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:fl_clash/common/package.dart';

/// BiLoom fork: 新版本检查的纯逻辑层。
///
/// 数据源优先级（见 `Request.checkForUpdate`）：
/// 1. `biloom.top/versions.json` —— 自己的服务器，国内可直连，不吃 GitHub
///    API 的每小时 60 次匿名配额；
/// 2. GitHub releases —— 仅作站点不可达时的兜底（上游逻辑原样保留）。
///
/// 这里只放「不碰网络、不碰全局状态」的解析与判定，方便单测覆盖。

const kVersionsJsonUrl = 'https://biloom.top/versions.json';

/// 当前平台在 versions.json `files` 里的下载通道挑选顺序：
/// 桌面优先安装版 exe、其次便携 zip；安卓只有 apk。
List<String> _kindsForPlatform({required bool isAndroid}) =>
    isAndroid ? const ['apk'] : const ['exe', 'zip'];

/// 从 versions.json 的 files 数组里挑一条当前平台的直链。
///
/// 优先国内直连（biloom.top 域名），没有才退 GitHub 镜像；一个都没有
/// 返回 null，由调用方回落到 GitHub release 页。
@visibleForTesting
String? pickSiteDownloadUrl(List<Object?>? files, {required bool isAndroid}) {
  if (files == null) return null;
  final entries = files.whereType<Map>().toList();
  final kinds = _kindsForPlatform(isAndroid: isAndroid);
  String? pick(bool Function(Map entry) where) {
    for (final kind in kinds) {
      for (final entry in entries) {
        if (entry['kind'] == kind && where(entry)) {
          final url = entry['url'];
          return url is String && url.isNotEmpty ? url : null;
        }
      }
    }
    return null;
  }

  // 先挑国内直连，再放宽到任意通道（GitHub 镜像）。
  return pick((entry) => (entry['url'] as String?)?.contains('biloom.top') == true) ??
      pick((_) => true);
}

/// 站点源检查结果：
/// - [reachable] 为 false = 请求失败或 JSON 结构不认识 → 调用方走 GitHub 兜底；
/// - reachable 且 [update] 为 null = 已是最新；
/// - reachable 且 [update] 非 null = 有新版本，map 形制与 GitHub release 对齐
///   （`tag_name` / `body`），外加 fork 私有的 `download_url`。
@visibleForTesting
typedef SiteUpdateEvaluation = ({bool reachable, Map<String, dynamic>? update});

@visibleForTesting
SiteUpdateEvaluation evaluateSiteVersionsJson({
  required Object? decoded,
  required String currentVersion,
  required bool isAndroid,
}) {
  Map? latest;
  try {
    latest = (decoded as Map?)?['latest'] as Map?;
  } catch (_) {
    latest = null;
  }
  final version = latest?['version'];
  if (latest == null || version is! String || version.trim().isEmpty) {
    return (reachable: false, update: null);
  }
  final remoteVersion = version.trim().replaceAll('v', '');
  if (compareVersions(remoteVersion, currentVersion) <= 0) {
    return (reachable: true, update: null);
  }
  final files = latest['files'] is List
      ? (latest['files'] as List).cast<Object?>()
      : null;
  return (
    reachable: true,
    update: {
      'tag_name': 'v$remoteVersion',
      'body': (latest['notes'] as String?) ?? '',
      'download_url': pickSiteDownloadUrl(files, isAndroid: isAndroid),
    },
  );
}
