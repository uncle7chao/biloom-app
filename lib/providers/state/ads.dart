part of '../state.dart';

/// M3 变现层：远程广告开关的**运行时**（拉取/缓存/平台判定）。
///
/// 纯模型与配置判定在 `common/ads.dart`（零依赖可独立测试）；本 store 只做
/// 三件事：启动时按新鲜期决定要不要拉、成功后写 SP 缓存、失败静默。
///
/// 失败静默的准确语义：网络失败 / 超时 / JSON 坏了都**不改变当前状态** ——
/// 上次成功的配置继续生效；从来没成功过就是「全关」。广告链路上任何异常
/// 都不允许打扰主功能，这是底线，所以这里连错误日志都只打到 debug 档。
class AdsConfigStore extends AsyncNotifier<AdsRemoteConfig?> {
  @override
  Future<AdsRemoteConfig?> build() async {
    try {
      final prefs = await preferences.sharedPreferencesCompleter.future;
      final raw = prefs?.getString(kAdsConfigPrefsKey);
      if (raw == null || raw.isEmpty) {
        return null;
      }
      return AdsRemoteConfig.parse(raw);
    } catch (_) {
      // 缓存坏了不挡启动 —— 退化成「无配置」（全关），下次拉取成功自愈。
      return null;
    }
  }

  /// 启动入口：缓存还在新鲜期内就不打扰网络；过期或从未拉取才发请求。
  /// bootstrap._initApp 里 unawaited 调用 —— 拉广告不该等主流程。
  Future<void> refreshIfStale() async {
    final fetchedAt = await _readFetchedAt();
    if (!adsConfigIsStale(fetchedAt, DateTime.now().millisecondsSinceEpoch)) {
      return;
    }
    await refresh();
  }

  /// 拉取并应用远程开关。只在**解析成功**后落盘：坏 JSON 不能把上次的好
  /// 缓存冲掉。超时给得极短（5s）—— 广告配置不值得占用户的网络耐心。
  Future<void> refresh() async {
    try {
      final response = await Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      ).get<String>(kAdsConfigUrl);
      final raw = response.data;
      final config = AdsRemoteConfig.parse(raw);
      if (config == null) {
        return;
      }
      final prefs = await preferences.sharedPreferencesCompleter.future;
      await prefs?.setString(kAdsConfigPrefsKey, raw!);
      await prefs?.setInt(
        kAdsFetchedAtPrefsKey,
        DateTime.now().millisecondsSinceEpoch,
      );
      state = AsyncData(config);
      commonPrint.log(
        'ads config refreshed: v=${config.v} enabled=${config.enabled}',
      );
    } catch (e) {
      commonPrint.log(
        'ads config fetch failed (silent): $e',
        logLevel: LogLevel.debug,
      );
    }
  }

  Future<int?> _readFetchedAt() async {
    try {
      final prefs = await preferences.sharedPreferencesCompleter.future;
      return prefs?.getInt(kAdsFetchedAtPrefsKey);
    } catch (_) {
      return null;
    }
  }
}

final adsConfigStoreProvider =
    AsyncNotifierProvider<AdsConfigStore, AdsRemoteConfig?>(
      AdsConfigStore.new,
    );

/// 当前平台「Banner 广告位」的生效配置；null = 本平台不展示（没接 SDK /
/// 总开关关 / 从未拉到配置 / 广告位 ID 空）。**将来所有广告 UI 挂载点只认
/// 这一个 provider** —— 平台有没有 SDK（`kAdSdkPlatforms`）在这里裁决，
/// 配置层的门（总开关/位开关/ID 非空）交给 `adsBannerPropsFor`。
final adsBannerPlacementProvider = Provider<AdPlacementProps?>((ref) {
  final AdPlatform platform;
  if (system.isAndroid) {
    platform = AdPlatform.android;
  } else if (system.isWindows) {
    platform = AdPlatform.windows;
  } else if (system.isMacOS) {
    platform = AdPlatform.macos;
  } else {
    platform = AdPlatform.linux;
  }
  if (!kAdSdkPlatforms.contains(platform)) {
    return null;
  }
  final config = ref.watch(adsConfigStoreProvider).value;
  return adsBannerPropsFor(config, platform);
});

/// 平台枚举的公共裁决：Android 优先，桌面逐个认领，兜底 linux。
/// v4 新增的 Android 专属位与 home Banner 用同一套平台识别。
AdPlatform _currentAdPlatform() {
  if (system.isAndroid) {
    return AdPlatform.android;
  } else if (system.isWindows) {
    return AdPlatform.windows;
  } else if (system.isMacOS) {
    return AdPlatform.macos;
  } else {
    return AdPlatform.linux;
  }
}

/// 代理页底部自适应 Banner 的生效配置；null = 不展示。与 home Banner
/// 同一套裁决链（SDK 平台集合 → 总开关 → 位开关 → ID 非空），两键互相
/// 独立：关掉代理页位不影响首页位。
final adsProxiesBannerPlacementProvider = Provider<AdPlacementProps?>((ref) {
  final platform = _currentAdPlatform();
  if (!kAdSdkPlatforms.contains(platform)) {
    return null;
  }
  final config = ref.watch(adsConfigStoreProvider).value;
  return adsProxiesBannerPropsFor(config, platform);
});

/// 代理页原生卡片（列表内嵌）的生效配置；null = 不展示。裁决链同上。
final adsNativePlacementProvider = Provider<AdPlacementProps?>((ref) {
  final platform = _currentAdPlatform();
  if (!kAdSdkPlatforms.contains(platform)) {
    return null;
  }
  final config = ref.watch(adsConfigStoreProvider).value;
  return adsNativePropsFor(config, platform);
});

/// 配置页底部 Banner 的生效配置；null = 不展示。与代理页位同一套裁决链，
/// 开关互相独立（远程 JSON v5 的 bannerProfilesAndroid 键）。
final adsProfilesBannerPlacementProvider = Provider<AdPlacementProps?>((ref) {
  final platform = _currentAdPlatform();
  if (!kAdSdkPlatforms.contains(platform)) {
    return null;
  }
  final config = ref.watch(adsConfigStoreProvider).value;
  return adsProfilesBannerPropsFor(config, platform);
});

/// 工具页底部 Banner 的生效配置；null = 不展示。同上（bannerToolsAndroid）。
final adsToolsBannerPlacementProvider = Provider<AdPlacementProps?>((ref) {
  final platform = _currentAdPlatform();
  if (!kAdSdkPlatforms.contains(platform)) {
    return null;
  }
  final config = ref.watch(adsConfigStoreProvider).value;
  return adsToolsBannerPropsFor(config, platform);
});

/// 当前平台「活动」入口的生效配置；null = 不渲染入口（非 Windows /
/// 总开关关 / 从未拉到配置 / url 无效）。
///
/// 活动页是引流位不是广告位（模型见 common/ads.dart），**不查
/// [kAdSdkPlatforms]** —— WebView 不依赖广告 SDK，Windows 现在就能用。
/// 平台裁决只放 Windows：Android 侧将来若复用（比如开屏活动页）再放开，
/// 批 1 不做没验证过的平台。
final promoWindowProvider = Provider<PromoWindowProps?>((ref) {
  if (!system.isWindows) {
    return null;
  }
  final config = ref.watch(adsConfigStoreProvider).value;
  return adsPromoPropsFor(config);
});
