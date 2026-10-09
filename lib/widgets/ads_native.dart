import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';

/// Android 原生广告卡片（v4）：代理页列表内嵌，平台视图由 Android 侧
/// 注册的 NativeAdFactory（factoryId: [kNativeAdFactoryId]）绘制。
///
/// **唯一的 UI 挂载规则**：只认 [adsNativePlacementProvider] —— null 即不
/// 渲染，挂载处不写任何平台判断。
///
/// 加载失败静默缩回 0 高度；配置热更新（换 ID）才重建；dispose 释放。
class AdsNativeCard extends ConsumerStatefulWidget {
  const AdsNativeCard({super.key});

  @override
  ConsumerState<AdsNativeCard> createState() => _AdsNativeCardState();
}

class _AdsNativeCardState extends ConsumerState<AdsNativeCard> {
  NativeAd? _ad;
  String? _loadedId;
  bool _loaded = false;
  bool _sdkInitialized = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      adsNativePlacementProvider,
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
    final ad = NativeAd(
      adUnitId: id,
      factoryId: kNativeAdFactoryId,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (mounted) {
            setState(() => _loaded = true);
          }
        },
        onAdFailedToLoad: (ad, error) {
          commonPrint.log(
            'ads native failed to load: ${error.message}',
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
    ref.watch(adsNativePlacementProvider);
    final ad = _ad;
    if (ad == null || !_loaded) {
      return const SizedBox.shrink();
    }
    final height = _kNativeCardHeight;
    return SizedBox(
      height: height,
      child: ColoredBox(
        color: context.colorScheme.surface,
        child: AdWidget(ad: ad),
      ),
    );
  }
}

/// 原生卡片的固定高度：与 Android 侧工厂布局（单行图文）对齐。
/// 工厂布局改动时同步这里。
const double _kNativeCardHeight = 72;

/// Android 侧 NativeAdFactory 的注册 ID，两端必须一致。
const String kNativeAdFactoryId = 'biloomNative';
