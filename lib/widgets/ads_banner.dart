import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';

/// Banner 挂载位置。每个位置对应远程 JSON 里独立的一个键（v4/v5）：
/// - [home]：`bannerAndroid`，固定尺寸（320×50 标准位），挂在全局壳层
/// - [proxies]：`bannerProxiesAndroid`，锚定自适应（宽度随屏幕）
/// - [profiles]：`bannerProfilesAndroid`（v5），配置页底部固定位
/// - [tools]：`bannerToolsAndroid`（v5），工具页底部固定位
enum AdsBannerPlacement { home, proxies, profiles, tools }

/// Android Banner 广告位（M3 批 2；v4 起多挂载点；01.00.35 轮修生命周期）。
///
/// **唯一的 UI 挂载规则**：只认对应位置的 placement provider —— null 即不
/// 渲染（平台没 SDK / 总开关关 / 位开关关 / 广告位 ID 空 / 从未拉到配置），
/// 挂载处不写任何平台判断，开关全在远程 JSON 与接缝常量里。
///
/// 生命周期（01.00.35 修复，教训来自首页位 34 版请求量恒 0）：
/// - **load 前必须等 `MobileAds.instance.initialize()` 完成**。34 版在启动
///   即触发（配置有 SP 缓存，listenManual fireImmediately 立刻建 ad），SDK
///   尚未初始化就 load 必失败 —— 而自适应位是用户切页才触发，SDK 早已就绪，
///   所以同一个包里代理位正常、首页位从未发出过请求。
/// - **失败指数退避重试**。34 版失败一次就永久躺平且无任何再触发路径；
///   现在失败后退避重试（5s/15s/45s/60s…封顶 [_maxRetries] 次），防止
///   no-fill 之类瞬时故障把位置打死，也防止无限重试造成请求风暴。
/// - dispose / 配置热更新（换 ID）时清空重试状态重新来过。
///
/// google_mobile_ads 只在 Android 注册插件，桌面端不会走到任何 SDK 调用
/// （provider 在桌面端恒 null），本文件被桌面端编译仅是纯 Dart 符号引用。
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
  Future<void>? _sdkInitFuture;

  /// 最近一次想展示的配置与尺寸：重试定时器按它重建广告。
  AdPlacementProps? _pendingProps;
  AdSize? _pendingSize;
  int _failures = 0;
  Timer? _retryTimer;

  /// 失败重试上限与退避序列（秒）。no-fill 冷启动通常在几分钟内自愈，
  /// 5 次退避大约覆盖 2 分钟；之后保持暗置，等配置热更新或重建组件再试。
  static const _maxRetries = 5;
  static const _retryDelays = [5, 15, 45, 60, 60];

  /// 自适应位是否按宽度定尺寸。只有代理页是自适应；其余均为固定位。
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
    AdsBannerPlacement.profiles => adsProfilesBannerPlacementProvider,
    AdsBannerPlacement.tools => adsToolsBannerPlacementProvider,
  };

  /// SDK 初始化只发一次（MobileAds.initialize 幂等，这里再 memo 一层省
  /// 重复平台通道调用），返回的 Future 完成后才允许 load。
  Future<void> _ensureSdkInitialized() =>
      _sdkInitFuture ??= MobileAds.instance.initialize();

  void _syncAd(AdPlacementProps? props, [int? width]) {
    final id = props?.adUnitId ?? '';
    if (props == null || id.isEmpty || !system.isAndroid) {
      _cancelRetry();
      _disposeAd();
      return;
    }
    // 换了广告单元 = 全新一轮，失败计数清零。
    if (_loadedId != id) {
      _failures = 0;
    }
    _pendingProps = props;
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
    _pendingProps = props;
    _pendingSize = size;
    // 同 ID + 同尺寸（自适应的宽度跨档）且已有实例：正在加载或已加载，不动。
    if (_loadedId == id && _loadedWidth == size.width && _ad != null) {
      return;
    }
    // 已有重试在排队：等定时器触发，不在 build 路径上叠加请求。
    if (_retryTimer?.isActive ?? false) {
      return;
    }
    _disposeAd();
    final ad = BannerAd(
      adUnitId: id,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          commonPrint.log(
            'ads banner loaded: $id (${size.width}x${size.height})',
            logLevel: LogLevel.debug,
          );
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
          _clearAd();
          _scheduleRetry();
        },
      ),
    );
    _ad = ad;
    _loadedId = id;
    _loadedWidth = size.width;
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
        'ads banner load error: $e',
        logLevel: LogLevel.debug,
      );
      _clearAd();
      _scheduleRetry();
    });
  }

  /// 失败后按退避序列排一次重试。退避期间 build 里再怎么触发 _syncAd
  /// 都被 _createAd 的重试 guard 拦住，不会产生请求风暴。
  void _scheduleRetry() {
    if (!mounted) {
      return;
    }
    _failures++;
    if (_failures > _maxRetries) {
      commonPrint.log(
        'ads banner give up after $_maxRetries failures '
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
      final size = _pendingSize;
      if (props == null || size == null || !mounted) {
        return;
      }
      _createAd(props, size);
    });
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  /// 只清广告实例状态，不动重试节奏。
  void _clearAd() {
    _ad = null;
    _loadedId = null;
    _loadedWidth = null;
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
    // 依赖 provider 保持联动（配置热更新时 rebuild），实际展示只看加载态。
    final props = ref.watch(_placementProvider());
    if (!system.isAndroid) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (_isAdaptive) {
          final width = constraints.maxWidth.floor();
          // 只在拿到真实宽度（非无限）时触发同步；内部有同档 guard 与
          // 重试 guard，no-fill 不会在这里变成请求风暴。
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
