import 'dart:async';

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
/// 生命周期与 [AdsBanner] 同一套（01.00.35 统一）：load 前等 SDK 初始化
/// 完成；失败指数退避重试（封顶 5 次，防请求风暴）；配置热更新（换 ID）
/// 才重置失败计数；dispose 释放。加载失败静默缩回 0 高度。
class AdsNativeCard extends ConsumerStatefulWidget {
  const AdsNativeCard({super.key});

  @override
  ConsumerState<AdsNativeCard> createState() => _AdsNativeCardState();
}

class _AdsNativeCardState extends ConsumerState<AdsNativeCard> {
  NativeAd? _ad;
  String? _loadedId;
  bool _loaded = false;
  Future<void>? _sdkInitFuture;
  AdPlacementProps? _pendingProps;
  int _failures = 0;
  Timer? _retryTimer;

  /// 与 AdsBanner 同一套退避参数，两处改动需同步。
  static const _maxRetries = 5;
  static const _retryDelays = [5, 15, 45, 60, 60];

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      adsNativePlacementProvider,
      (_, next) => _syncAd(next),
      fireImmediately: true,
    );
  }

  Future<void> _ensureSdkInitialized() =>
      _sdkInitFuture ??= MobileAds.instance.initialize();

  void _syncAd(AdPlacementProps? props) {
    final id = props?.adUnitId ?? '';
    if (props == null || id.isEmpty || !system.isAndroid) {
      _cancelRetry();
      _disposeAd();
      return;
    }
    if (_loadedId != id) {
      _failures = 0;
    }
    _pendingProps = props;
    if (_loadedId == id && _ad != null) {
      return;
    }
    if (_retryTimer?.isActive ?? false) {
      return;
    }
    _createAd(props);
  }

  void _createAd(AdPlacementProps props) {
    final id = props.adUnitId;
    _pendingProps = props;
    _disposeAd();
    final ad = NativeAd(
      adUnitId: id,
      factoryId: kNativeAdFactoryId,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          commonPrint.log(
            'ads native loaded: $id',
            logLevel: LogLevel.debug,
          );
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
          _clearAd();
          _scheduleRetry();
        },
      ),
    );
    _ad = ad;
    _loadedId = id;
    _loaded = false;
    _ensureSdkInitialized().then((_) {
      if (!mounted) {
        ad.dispose();
        return;
      }
      // 本插件版本 load() 返回 void（结果走 listener 回调），这里只负责
      // 等 SDK 就绪后发起；初始化异常走 catchError 退避。
      ad.load();
    }).catchError((Object e) {
      commonPrint.log(
        'ads native load error: $e',
        logLevel: LogLevel.debug,
      );
      _clearAd();
      _scheduleRetry();
    });
  }

  void _scheduleRetry() {
    if (!mounted) {
      return;
    }
    _failures++;
    if (_failures > _maxRetries) {
      commonPrint.log(
        'ads native give up after $_maxRetries failures '
        '(id: ${_pendingProps?.adUnitId})',
        logLevel: LogLevel.debug,
      );
      return;
    }
    final delay = _retryDelays[(_failures - 1).clamp(
      0,
      _retryDelays.length - 1,
    )];
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: delay), () {
      final props = _pendingProps;
      if (props == null || !mounted) {
        return;
      }
      _createAd(props);
    });
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _clearAd() {
    _ad = null;
    _loadedId = null;
    if (_loaded && mounted) {
      setState(() => _loaded = false);
    } else {
      _loaded = false;
    }
  }

  void _disposeAd() {
    _ad?.dispose();
    _clearAd();
  }

  @override
  void dispose() {
    _cancelRetry();
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
