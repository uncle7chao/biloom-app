import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';

/// Banner 挂载位置。每个位置对应远程 JSON 里独立的一个键（v4）：
/// - [home]：`bannerAndroid`，固定尺寸（320×50 标准位）
/// - [proxies]：`bannerProxiesAndroid`，锚定自适应（宽度随屏幕）
enum AdsBannerPlacement { home, proxies }

/// Android Banner 广告位（M3 批 2；v4 起多挂载点）。
///
/// **唯一的 UI 挂载规则**：只认对应位置的 placement provider —— null 即不
/// 渲染（平台没 SDK / 总开关关 / 位开关关 / 广告位 ID 空 / 从未拉到配置），
/// 挂载处不写任何平台判断，开关全在远程 JSON 与接缝常量里。
///
/// 生命周期：adUnitId 变化（远程换位）或自适应宽度变化（跨档）才重建
/// [BannerAd]；加载失败静默缩回 0 高度（广告链路任何异常不允许打扰主
/// 功能）；dispose 时释放。google_mobile_ads 只在 Android 注册插件，桌面
/// 端不会走到任何 SDK 调用（provider 在桌面端恒 null），本文件被桌面端
/// 编译仅是纯 Dart 符号引用。
class AdsBanner extends ConsumerStatefulWidget {
  const AdsBanner({super.key, this.placement = AdsBannerPlacement.home});

  /// 挂载位置，决定用哪个远程键与哪种尺寸策略。
  final AdsBannerPlacement placement;

  @override
  ConsumerState<AdsBanner> createState() => _AdsBannerState();
}

class _AdsBannerState extends ConsumerState<AdsBanner> {
  BannerAd? _ad;
  String? _loadedId;
  int? _loadedWidth;
  bool _loaded = false;
  bool _sdkInitialized = false;

  /// 自适应位是否按宽度定尺寸。
  bool get _isAdaptive => widget.placement == AdsBannerPlacement.proxies;

  @override
  void initState() {
    super.initState();
    // placement provider 是同步 provider，但它 watch 的配置 store 是异步
    // 的 —— 用 listenManual(fireImmediately) 跟随「无配置 → 有配置」与
    // 「换 ID」两种跳变，不在 build 里做副作用。自适应位此时还没有布局
    // 宽度，首次 load 由 build 里的 LayoutBuilder 触发。
    ref.listenManual(
      _placementProvider(),
      (_, AdPlacementProps? next) => _syncAd(next),
      fireImmediately: true,
    );
  }

  Provider<AdPlacementProps?> _placementProvider() => switch (widget.placement) {
    AdsBannerPlacement.home => adsBannerPlacementProvider,
    AdsBannerPlacement.proxies => adsProxiesBannerPlacementProvider,
  };

  void _syncAd(AdPlacementProps? props, [int? width]) {
    final id = props?.adUnitId ?? '';
    if (props == null || id.isEmpty || !system.isAndroid) {
      _disposeAd();
      return;
    }
    if (!_isAdaptive) {
      _createAd(props, AdSize.banner);
      return;
    }
    // 自适应位必须有宽度；build 首帧前拿不到，等 LayoutBuilder 再来。
    if (width == null || width <= 0 || width >= 10000) {
      return;
    }
    // 该 API 返回 Future（尺寸计算可能走平台通道），异步回来后同档 guard。
    AdSize.getLargeAnchoredAdaptiveBannerAdSize(width).then((adaptive) {
      if (!mounted) {
        return;
      }
      if (adaptive == null) {
        _disposeAd();
        return;
      }
      _createAd(props, adaptive);
    }).catchError((Object _) {
      // 尺寸计算失败也静默 —— 广告链路异常不允许打扰主功能。
    });
  }

  void _createAd(AdPlacementProps props, AdSize size) {
    final id = props.adUnitId;
    // 同 ID + 同尺寸（自适应的宽度跨档）不重建，避免每帧重建广告。
    if (_loadedId == id && _loadedWidth == size.width && _ad != null) {
      return;
    }
    _disposeAd();
    final ad = BannerAd(
      adUnitId: id,
      size: size,
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
              _loadedWidth = null;
              _loaded = false;
            });
          }
        },
      ),
    );
    _ad = ad;
    _loadedId = id;
    _loadedWidth = size.width;
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
    _loadedWidth = null;
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
    final props = ref.watch(_placementProvider());
    if (!system.isAndroid) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (_isAdaptive) {
          final width = constraints.maxWidth.floor();
          // 只在拿到真实宽度（非无限）时触发同步；内部有同档 guard。
          if (width > 0 && width < 10000) {
            _syncAd(props, width);
          }
        }
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
      },
    );
  }
}
