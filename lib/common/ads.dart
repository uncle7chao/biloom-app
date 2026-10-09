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
///   "v": 2,
///   "enabled": true,
///   "bannerAndroid": {"enabled": true, "adUnitId": "ca-app-pub-…/…"},
///   "bannerWindows": {"enabled": false, "adUnitId": ""},
///   "promoWindows": {"enabled": true, "url": "https://biloom.top/promo",
///                    "badge": "新"}
/// }
/// ```
///
/// v2 新增 [AdsRemoteConfig.promoWindows]：Windows 端「活动」页入口。它是
/// **引流位不是广告位**——WebView 加载自家页面（绝不允许 AdSense 代码进
/// 应用内窗口，政策会封整个 AdSense 账号），页内「在浏览器中打开」跳系统
/// 浏览器，广告收入由官网承接。url 有**域白名单**（[isValidPromoUrl]）：
/// 远程配置只能指向 biloom.top 及其子域，防止开关 JSON 被改后 WebView 被
/// 指向任意站点。
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
/// AdMob 只有 Android/iOS。Android 已接 google_mobile_ads（2026-09-29 批 2，
/// App ID 与广告位 ID 见 AndroidManifest 注释与 biloom.top/ads.json）——
/// 把 [AdPlatform.android] 加进本集合即点亮整条链路，配置层零改动。
/// Windows/macOS/Linux 依旧没有 SDK，配置可先在远程 JSON 预置、接缝打开
/// 即生效。公开成常量而非私有：state 层的平台裁决要先查它（跨库可见性）。
const kAdSdkPlatforms = <AdPlatform>{AdPlatform.android};

/// 活动页 url 的**域白名单**：只允许 https 与 biloom.top 及其子域。
///
/// 远程开关 JSON 是唯一真源，但它本身也是可被篡改的输入（DNS 劫持、托管
/// 被黑、JSON 手改）——WebView 是应用里权限最高的组件（可执行任意网页
/// JS），入口 url 必须在客户端再校验一道。大小写不敏感；尾随的 `/`、查询
/// 参数与路径都放行（路径内容仍是我们自己服务器上的东西）。
bool isValidPromoUrl(String url) {
  final Uri? uri;
  try {
    uri = Uri.tryParse(url);
  } catch (_) {
    return false;
  }
  if (uri == null || uri.scheme.toLowerCase() != 'https') {
    return false;
  }
  final host = uri.host.toLowerCase();
  return host == 'biloom.top' || host.endsWith('.biloom.top');
}

/// 「活动」页入口的远程配置（Windows 端引流位）。
class PromoWindowProps {
  const PromoWindowProps({
    required this.enabled,
    required this.url,
    required this.badge,
  });

  final bool enabled;

  /// 活动页地址。为空或不在 [isValidPromoUrl] 白名单内时即便 enabled 也
  /// 视为关 —— 与广告位「没位子的开=关」同一哲学。
  final String url;

  /// 侧栏入口角标文字（如「新」）。空 = 无角标。
  final String badge;

  /// 非法/缺字段一律取**安全默认值**：关。
  static PromoWindowProps fromMap(Map<dynamic, dynamic> map) {
    final url = map['url'];
    final badge = map['badge'];
    return PromoWindowProps(
      enabled: map['enabled'] == true,
      url: url is String ? url : '',
      badge: badge is String ? badge : '',
    );
  }
}

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
///
/// v4（2026-10-09）：新增 [bannerProxiesAndroid]（代理页底部自适应
/// Banner）与 [nativeProxiesAndroid]（代理页列表内原生卡片）。旧 JSON
/// （v2/v3）缺这两键时取安全默认值=关，旧配置零影响。
class AdsRemoteConfig {
  const AdsRemoteConfig({
    required this.v,
    required this.enabled,
    required this.bannerAndroid,
    required this.bannerWindows,
    this.bannerProxiesAndroid = const AdPlacementProps(
      enabled: false,
      adUnitId: '',
    ),
    this.nativeProxiesAndroid = const AdPlacementProps(
      enabled: false,
      adUnitId: '',
    ),
    this.promoWindows = const PromoWindowProps(
      enabled: false,
      url: '',
      badge: '',
    ),
  });

  final int v;

  /// 总开关。关掉时所有广告位一律不展示，不用逐位去关。
  final bool enabled;
  final AdPlacementProps bannerAndroid;

  /// Windows/macOS/Linux 共用：当前没有 SDK，永远不展示；预留字段让远程
  /// 端可以先配好，SDK 接缝打开即生效。
  final AdPlacementProps bannerWindows;

  /// Android 代理页底部的自适应 Banner（anchored adaptive，宽度随屏幕）。
  final AdPlacementProps bannerProxiesAndroid;

  /// Android 代理页列表内嵌的原生广告卡片（NativeAd，模板由平台侧工厂
  /// 绘制）。原生与 Banner 相互独立：任一关掉不影响另一个。
  final AdPlacementProps nativeProxiesAndroid;

  /// Windows 端「活动」页入口（引流位，见 [isValidPromoUrl] 的白名单说明）。
  final PromoWindowProps promoWindows;

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
      bannerProxiesAndroid: AdPlacementProps.fromMap(
        decoded['bannerProxiesAndroid'] is Map
            ? decoded['bannerProxiesAndroid'] as Map
            : const {},
      ),
      nativeProxiesAndroid: AdPlacementProps.fromMap(
        decoded['nativeProxiesAndroid'] is Map
            ? decoded['nativeProxiesAndroid'] as Map
            : const {},
      ),
      promoWindows: PromoWindowProps.fromMap(
        decoded['promoWindows'] is Map
            ? decoded['promoWindows'] as Map
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
AdPlacementProps? adsBannerPropsFor(
  AdsRemoteConfig? config,
  AdPlatform platform,
) {
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

/// 「活动」入口的**配置层**判定：总开关 → 位开关 → url 有效（白名单域 +
/// 非空），任何一环不满足都返回 null。与 [adsBannerPropsFor] 同一风格：
/// 这里只做配置层；「平台是否提供活动入口」由 state 层裁决。
PromoWindowProps? adsPromoPropsFor(AdsRemoteConfig? config) {
  if (config == null || !config.enabled) {
    return null;
  }
  final props = config.promoWindows;
  if (!props.enabled || !isValidPromoUrl(props.url)) {
    return null;
  }
  return props;
}

/// Android 专属位的**配置层**判定（代理页 Banner / 原生卡片共用模板）：
/// 总开关 → 位开关 → ID 非空。桌面平台传进来直接 null —— 这两位只在
/// Android 有意义，state 层的 SDK 裁决在此之前已挡掉桌面，这里是双保险。
AdPlacementProps? _androidPlacementPropsFor(
  AdsRemoteConfig? config,
  AdPlatform platform,
  AdPlacementProps Function(AdsRemoteConfig config) pick,
) {
  if (config == null ||
      !config.enabled ||
      platform != AdPlatform.android) {
    return null;
  }
  final props = pick(config);
  if (!props.enabled || props.adUnitId.isEmpty) {
    return null;
  }
  return props;
}

/// 代理页底部自适应 Banner 的配置判定。
AdPlacementProps? adsProxiesBannerPropsFor(
  AdsRemoteConfig? config,
  AdPlatform platform,
) => _androidPlacementPropsFor(
  config,
  platform,
  (config) => config.bannerProxiesAndroid,
);

/// 代理页原生卡片（列表内嵌）的配置判定。
AdPlacementProps? adsNativePropsFor(
  AdsRemoteConfig? config,
  AdPlatform platform,
) => _androidPlacementPropsFor(
  config,
  platform,
  (config) => config.nativeProxiesAndroid,
);
