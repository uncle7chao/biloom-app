import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';

/// Android Banner 广告位（M3 批 2）。
///
/// **唯一的 UI 挂载规则**：只认 [adsBannerPlacementProvider] —— null 即不
/// 渲染（平台没 SDK / 总开关关 / 位开关关 / 广告位 ID 空 / 从未拉到配置），
/// 挂载处不写任何平台判断，开关全在远程 JSON 与接缝常量里。
///
/// 生命周期：adUnitId 变化（远程换位）才重建 [BannerAd]；加载失败静默
/// 缩回 0 高度（广告链路任何异常不允许打扰主功能）；dispose 时释放。
/// google_mobile_ads 只在 Android 注册插件，桌面端不会走到任何 SDK 调用
/// （provider 在桌面端恒 null），本文件被桌面端编译仅是纯 Dart 符号引用。
class AdsBanner extends ConsumerStatefulWidget {
  const AdsBanner({super.key});

  @override
  ConsumerState<AdsBanner> createState() => _AdsBannerState();
}

class _AdsBannerState extends ConsumerState<AdsBanner> {
  BannerAd? _ad;
  String? _loadedId;
  bool _loaded = false;
  bool _sdkInitialized = false;

  @override
  void initState() {
    super.initState();
    // adsBannerPlacementProvider 是同步 provider，但它 watch 的配置 store
    // 是异步的 —— 用 listenManual(fireImmediately) 跟随「无配置 → 有配置」
    // 与「换 ID」两种跳变，不在 build 里做副作用。
    ref.listenManual(
      adsBannerPlacementProvider,
      (_, next) => _syncAd(next),
      fireImmediately: true,
    );
  }

  void _syncAd(AdPlacementProps? props) {
    final id = props?.adUnitId ?? '';
    if (props == null || id.isEmpty || !system.isAndroid) {
      _disposeAd();
      return;
    }
    if (_loadedId == id && _ad != null) {
      return;
    }
    _disposeAd();
    final ad = BannerAd(
      adUnitId: id,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) {
            setState(() => _loaded = true);
          }
        },
        onAdFailedToLoad: (ad, error) {
          commonPrint.log(
            'ads banner failed to load: ${error.message}',
            logLevel: LogLevel.debug,
          );
          ad.dispose();
          if (mounted) {
            setState(() {
              _ad = null;
              _loadedId = null;
              _loaded = false;
            });
          }
        },
      ),
    );
    _ad = ad;
    _loadedId = id;
    _loaded = false;
    if (!_sdkInitialized) {
      _sdkInitialized = true;
      MobileAds.instance.initialize();
    }
    ad.load();
  }

  void _disposeAd() {
    _ad?.dispose();
    _ad = null;
    _loadedId = null;
    if (_loaded && mounted) {
      setState(() => _loaded = false);
    } else {
      _loaded = false;
    }
  }

  @override
  void dispose() {
    _ad?.dispose();
    _ad = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 依赖 provider 保持联动（配置热更新时 rebuild），实际展示只看加载态。
    ref.watch(adsBannerPlacementProvider);
    final ad = _ad;
    if (ad == null || !_loaded) {
      return const SizedBox.shrink();
    }
    return SafeArea(
      top: false,
      child: ColoredBox(
        color: context.colorScheme.surface,
        child: SizedBox(
          width: ad.size.width.toDouble(),
          height: ad.size.height.toDouble(),
          child: AdWidget(ad: ad),
        ),
      ),
    );
  }
}
