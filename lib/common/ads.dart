/// M3 变现层的「远程开关」数据模型与判定 —— **纯 Dart，零依赖，可独立测试**。
///
/// 广告架构（2026-09-27 拍板：双端框架先行 + 官网静态 JSON + Android 仅 Banner）：
/// - 开关数据源 = biloom.top 上的静态 JSON（[kAdsConfigUrl]），应用启动时按
///   新鲜期拉取一次并缓存进 SP。**失败静默**：网络挂了/JSON 坏了就沿用上次
///   缓存，从来没成功过就当作「全部关闭」—— 广告永远不能反过来影响主功能。
/// - 双端共用本文件与 `state/ads.dart` 的 store；Windows/macOS/Linux 没有
///   广告 SDK（AdMob 只有 Android/iOS），`_adSdkPlatforms` 是唯一的平台接缝
///   —— Android 侧接 google_mobile_ads 时把它加进集合即可，配置链路零改动。
/// - 广告位 ID 一并由远程 JSON 下发：换广告位不需要重新出包。
///
/// 远程 JSON 的约定格式（多余字段忽略，缺字段取安全默认值=关）：
/// ```json
/// {
///   "v": 1,
///   "enabled": true,
///   "bannerAndroid": {"enabled": true, "adUnitId": "ca-app-pub-…/…"},
///   "bannerWindows": {"enabled": false, "adUnitId": ""}
/// }
/// ```
library;

import 'dart:convert';

/// 远程开关 JSON 的地址。M4 官网未建先占位路径；到时候把这个文件传上
/// biloom.top 即可，应用侧零改动。
const kAdsConfigUrl = 'https://biloom.top/ads.json';

/// SP 键：最近一次**成功**拉取的原始 JSON 与成功时刻的时间戳。
const kAdsConfigPrefsKey = 'adsRemoteConfig';
const kAdsFetchedAtPrefsKey = 'adsFetchedAt';

/// 缓存新鲜期：之内不重复请求（启动节流）。过期只是「会再拉一次」，
/// 缓存值在新请求成功前继续生效 —— 拉取失败不改变现有状态。
const kAdsConfigTtl = Duration(hours: 12);

/// 广告平台。
enum AdPlatform { android, windows, macos, linux }

/// 当前**真正接了广告 SDK** 的平台。
///
/// AdMob 只有 Android/iOS，而 Android 侧的 google_mobile_ads 尚未接入
/// （Android 全线押后中）—— 所以现在是空集：任何平台都不展示，但拉取/
/// 缓存/判定全链路照常运转，改 biloom.top 的 JSON 就能在 Windows 上完整
/// 验证开关行为（看日志与 provider 状态）。Android 集成时把
/// [AdPlatform.android] 加进来，此处之外零改动。公开成常量而非私有：
/// state 层的平台裁决要先查它（跨库可见性），它本来就是公开的接缝。
const kAdSdkPlatforms = <AdPlatform>{};

/// 一个广告位的远程配置。
class AdPlacementProps {
  const AdPlacementProps({required this.enabled, required this.adUnitId});

  final bool enabled;

  /// AdMob 广告位 ID（`ca-app-pub-…/…`）。为空时即便 enabled 也视为关 ——
  /// 没有位子的「开」等于「关」，与其让 SDK 拿空 ID 去崩，不如不展示。
  final String adUnitId;

  /// 非法/缺字段一律取**安全默认值**：关。
  static AdPlacementProps fromMap(Map<dynamic, dynamic> map) {
    final adUnitId = map['adUnitId'];
    return AdPlacementProps(
      enabled: map['enabled'] == true,
      adUnitId: adUnitId is String ? adUnitId : '',
    );
  }
}

/// 一份远程广告开关配置。[v] 是格式版本号：将来字段语义变了的逃生口，
/// 现在只透传不参与判定。
class AdsRemoteConfig {
  const AdsRemoteConfig({
    required this.v,
    required this.enabled,
    required this.bannerAndroid,
    required this.bannerWindows,
  });

  final int v;

  /// 总开关。关掉时所有广告位一律不展示，不用逐位去关。
  final bool enabled;
  final AdPlacementProps bannerAndroid;

  /// Windows/macOS/Linux 共用：当前没有 SDK，永远不展示；预留字段让远程
  /// 端可以先配好，SDK 接缝打开即生效。
  final AdPlacementProps bannerWindows;

  /// 解析远程 JSON 文本。任何形态的坏数据（非 Map、编码失败、结构不符）
  /// 都返回 null —— 调用方拿到 null 就当「无配置」处理，绝不上抛。
  static AdsRemoteConfig? parse(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final Object? decoded;
    try {
      decoded = json.decode(raw);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) {
      return null;
    }
    final v = decoded['v'];
    return AdsRemoteConfig(
      v: v is int ? v : 1,
      enabled: decoded['enabled'] == true,
      bannerAndroid: AdPlacementProps.fromMap(
        decoded['bannerAndroid'] is Map
            ? decoded['bannerAndroid'] as Map
            : const {},
      ),
      bannerWindows: AdPlacementProps.fromMap(
        decoded['bannerWindows'] is Map
            ? decoded['bannerWindows'] as Map
            : const {},
      ),
    );
  }
}

/// 缓存是否已不新鲜（该再拉一次了）。从未拉取、时间戳来自「未来」（设备
/// 时钟被回拨过）或超出 [kAdsConfigTtl] 都算不新鲜 —— 宁可多拉一次，
/// 不可该拉不拉。
bool adsConfigIsStale(int? fetchedAtMs, int nowMs) {
  if (fetchedAtMs == null || fetchedAtMs > nowMs) {
    return true;
  }
  return nowMs - fetchedAtMs > kAdsConfigTtl.inMilliseconds;
}

/// 某平台 Banner 广告位的**配置层**判定结果：总开关 → 对应位 → 位开关 →
/// 广告位 ID 非空，任何一环不满足都返回 null。
///
/// 这里只做配置层判定；「平台有没有 SDK」是运行时事实（`_adSdkPlatforms`），
/// 由 state 层先查再进来 —— 两层分开，配置判定才能独立测试。
AdPlacementProps? adsBannerPropsFor(AdsRemoteConfig? config, AdPlatform platform) {
  if (config == null || !config.enabled) {
    return null;
  }
  final props = switch (platform) {
    AdPlatform.android => config.bannerAndroid,
    AdPlatform.windows ||
    AdPlatform.macos ||
    AdPlatform.linux => config.bannerWindows,
  };
  if (!props.enabled || props.adUnitId.isEmpty) {
    return null;
  }
  return props;
}
