import 'dart:async';
import 'dart:io' show Platform;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/manager/app_manager.dart';
import 'package:fl_clash/models/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart' hide
      ActivateBox,
      AnimatedVisibility,
      AppBarSearchStateBuilder,
      BackLayerScope,
      BaseScaffold,
      BottomInsetScope,
      CloseContainerActionCallback,
      CloseContainerBuilder,
      ClosedCallback,
      CommonCard,
      CommonCheckBox,
      CommonChip,
      CommonCircleLoading,
      CommonDialog,
      CommonExpandIcon,
      CommonMinFilledButtonTheme,
      CommonMinIconButtonTheme,
      CommonPopScope,
      CommonPopupBox,
      CommonPopupMenu,
      CommonPopupMenuItem,
      CommonPopupRoute,
      CommonScaffold,
      CommonScaffoldState,
      CommonScrollBar,
      DecorationListItem,
      DisabledMask,
      EmojiText,
      ExtendProps,
      FadeBox,
      FadeScaleBox,
      FadeScaleEnterBox,
      FadeScaleEnterTransition,
      FadeSlideEnterTransition,
      FadeThroughBox,
      FloatingScrollbar,
      Info,
      InfoHeader,
      InputDialog,
      ItemPositionProvider,
      KeepScope,
      KeyedAnimatedList,
      LineChart,
      ListHeader,
      ListItem,
      MetaChip,
      ModalSideSheetRoute,
      MoreActionButton,
      NullStatus,
      NullStatusIllustration,
      NullStatusSwitcher,
      OnKeywordsUpdateCallback,
      OpenContainer,
      OpenContainerBuilder,
      PageActivityScope,
      PageFocusScope,
      PageTraversalPolicy,
      PagedSheet,
      PagedSheetRoute,
      PopupAnchorResolver,
      PopupOpen,
      ProfileIdProvider,
      ProxyDecoratorProvider,
      ScrollToEndBox,
      SelectedDecorationListItem,
      SettingTextCard,
      SheetProps,
      SheetProvider,
      SheetType,
      SideSheet,
      SliderDefaultsM3,
      TooltipLabel,
      TooltipText,
      commonProxyDecorator,
      genActions,
      generateSection,
      showExtend,
      showModalSideSheet,
      showSheet;
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasViewSize = ref.watch(
      viewSizeProvider.select((size) => !size.isEmpty),
    );
    if (!hasViewSize) {
      return const SizedBox.shrink();
    }
    // 冷启动品牌页（B 方案 B1-b）：内容树就绪时盖一层 B 标 + 字标，
    // ~0.8s 后淡出。双端同源 —— Windows 窗口期与 Android 引擎首帧后
    // 各自都从系统层（原生启动屏）无缝接进来。
    return _BrandSplashHost(
      child: HomeBackScopeContainer(
      child: AppSidebarContainer(
        child: _HomeShell(
          child: Consumer(
            builder: (_, ref, _) {
              final navigationItems = ref
                  .watch(currentNavigationItemsStateProvider)
                  .value;
              final isMobile = ref.watch(isMobileViewProvider);
              return _HomePageView(
                navigationItems: navigationItems,
                pageBuilder: (_, index) {
                  final navigationItem = navigationItems[index];
                  return _NavigationPage(
                    key: ValueKey(navigationItem.label),
                    item: navigationItem,
                    isMobile: isMobile,
                    view: navigationItem.builder(context),
                  );
                },
              );
            },
          ),
        ),
      ),
      ),
    );
  }
}

/// 冷启动品牌页的宿主：包住整个主页，首帧显示品牌层，短暂停留后淡出并
/// 从树上移除自己（不占任何后续帧）。品牌底恒定炭黑 `#101010`，B 标与
/// 字标用品牌绿 —— 这是品牌时刻，不跟随亮色主题（也符合「不引入第二套
/// 配色」铁律：只有 #101010 与 colorScheme.primary）。
class _BrandSplashHost extends StatefulWidget {
  const _BrandSplashHost({required this.child});

  final Widget child;

  @override
  State<_BrandSplashHost> createState() => _BrandSplashHostState();
}

class _BrandSplashHostState extends State<_BrandSplashHost> {
  static const _holdDuration = Duration(milliseconds: 800);
  static const _fadeDuration = Duration(milliseconds: 400);

  /// flutter test 会注入 FLUTTER_TEST；品牌层是纯启动视觉，测试里跳过，
  /// 否则 hold 期会吃掉用例的 tap 并留下 pending timer。
  static final bool _skipInTest = Platform.environment
      .containsKey('FLUTTER_TEST');

  bool _visible = true;
  bool _disposed = false;
  Timer? _holdTimer;

  @override
  void initState() {
    super.initState();
    if (_skipInTest) {
      return;
    }
    _holdTimer = Timer(_holdDuration, () {
      if (mounted) {
        setState(() => _visible = false);
      }
    });
  }

  @override
  void dispose() {
    // 树拆掉时收掉品牌层计时器，避免测试环境报 pending timer。
    _holdTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_skipInTest) {
      return widget.child;
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (!_disposed)
          IgnorePointer(
            ignoring: !_visible,
            child: AnimatedOpacity(
              opacity: _visible ? 1 : 0,
              duration: _fadeDuration,
              curve: Curves.easeOut,
              onEnd: () {
                if (!_visible && mounted) {
                  setState(() => _disposed = true);
                }
              },
              child: Material(
                // Text 没有 Material 祖先时框架会画黄色双下划线（fallback
                // 样式标记），品牌层包一层透明 Material 消掉它。
                type: MaterialType.transparency,
                child: ColoredBox(
                  color: const Color(0xFF101010),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _BrandMark(),
                        SizedBox(height: 18),
                        _BrandWordmark(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// B 标（assets/images/biloom-mark.svg，与启动图标同一份矢量源）。
class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (_, value, child) => Opacity(
        opacity: value.clamp(0, 1),
        child: Transform.scale(scale: 0.9 + 0.1 * value, child: child),
      ),
      child: SvgPicture.asset(
        'assets/images/biloom-mark.svg',
        width: 64,
        height: 64,
      ),
    );
  }
}

/// BiLoom 字标。
class _BrandWordmark extends StatelessWidget {
  const _BrandWordmark();

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (_, value, child) => Opacity(
        opacity: value.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, 6 * (1 - value)),
          child: child,
        ),
      ),
      child: const Text(
        'BiLoom',
        style: TextStyle(
          color: Color(0xFF00E5AF),
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _HomeShell extends ConsumerWidget {
  const _HomeShell({required this.child});

  final Widget child;

  void _handleToPage(PageLabel pageLabel, WidgetRef ref) {
    ref.read(currentPageLabelProvider.notifier).toPage(pageLabel);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(navigationStateProvider);
    final isMobile = state.viewMode == ViewMode.mobile;
    final navigationItems = state.navigationItems;
    // v5 去重：全局 Banner（home 位）挂在壳层，所有页签底部都带；但代理/
    // 配置/工具三页有自己的页面级 Banner（各自独立开关）。当前页若自带
    // Banner 就把全局位收起（保持状态不销毁，切回来不用重新加载广告），
    // 任何时刻底部只有一条广告，不做双条叠加。
    final pageLabel = ref.watch(currentPageLabelProvider);
    final hasPageBanner = switch (pageLabel) {
      PageLabel.proxies => ref.watch(adsProxiesBannerPlacementProvider) != null,
      PageLabel.profiles =>
        ref.watch(adsProfilesBannerPlacementProvider) != null,
      PageLabel.tools => ref.watch(adsToolsBannerPlacementProvider) != null,
      _ => false,
    };
    final floating = ref.watch(
      appSettingProvider.select((state) => state.floatingNavigationBar),
    );
    return Material(
      color: SurfaceLevel.page.colorOf(context.colorScheme),
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: FocusTraversalGroup(
                    policy: PageTraversalPolicy(),
                    child: BottomInsetScope(
                      inset: isMobile && floating
                          ? NavigationDock.insetOf(context)
                          : 0,
                      child: _BodyPadding(isMobile: isMobile, child: child),
                    ),
                  ),
                ),
                PositionedDirectional(
                  start: 0,
                  end: 0,
                  bottom: 0,
                  child: AnimatedVisibility.bottomNavigation(
                    visible: isMobile && floating,
                    child: _NavigationPadding(
                      child: NavigationDock(
                        destinations: [
                          for (final item in navigationItems)
                            NavigationDockDestination(
                              glyph: item.glyph,
                              label: item.label.label,
                            ),
                        ],
                        selectedIndex: state.currentIndex,
                        onSelected: (index) {
                          _handleToPage(navigationItems[index].label, ref);
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Android Banner 广告位（M3 批 2）：只认 adsBannerPlacementProvider，
          // 平台/开关/ID 的裁决全在 provider 与远程 JSON —— 非 Android 恒
          // SizedBox.shrink，不占布局。
          Visibility(
            visible: !hasPageBanner,
            maintainState: true,
            child: const AdsBanner(),
          ),
          AnimatedVisibility.bottomNavigation(
            visible: isMobile && !floating,
            child: _NavigationPadding(
              child: NavigationBar(
                destinations: [
                  for (final (index, item) in navigationItems.indexed)
                    NavigationDestination(
                      icon: AnimatedGlyph(
                        glyph: item.glyph,
                        filled: index == state.currentIndex,
                      ),
                      label: item.label.label,
                    ),
                ],
                selectedIndex: state.currentIndex,
                onDestinationSelected: (index) {
                  _handleToPage(navigationItems[index].label, ref);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BodyPadding extends StatelessWidget {
  const _BodyPadding({required this.isMobile, required this.child});

  final bool isMobile;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.removePadding(
      removeTop: false,
      removeBottom: isMobile,
      removeLeft: isMobile,
      removeRight: isMobile,
      context: context,
      child: child,
    );
  }
}

class _NavigationPadding extends StatelessWidget {
  const _NavigationPadding({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.removePadding(
      removeTop: true,
      removeBottom: false,
      removeLeft: true,
      removeRight: true,
      context: context,
      child: child,
    );
  }
}

class _NavigationPage extends StatelessWidget {
  const _NavigationPage({
    super.key,
    required this.item,
    required this.isMobile,
    required this.view,
  });

  final NavigationItem item;
  final bool isMobile;
  final Widget view;

  @override
  Widget build(BuildContext context) {
    final scopedView = PageFocusScope(child: view);
    final keptView = KeepScope(
      key: ValueKey(item.label),
      child: isMobile
          ? scopedView
          : Navigator(
              key: ValueKey('${item.label.name}_navigator'),
              pages: [MaterialPage(child: scopedView)],
              onDidRemovePage: (_) {},
            ),
    );
    return Consumer(
      builder: (_, ref, child) {
        final isActive = ref.watch(
          shownPageLabelProvider.select((label) => label == item.label),
        );
        // A kept-alive page off screen still ticks its animations, and
        // each tick asks for a frame.
        return PageActivityScope(
          isActive: isActive,
          child: TickerMode(
            enabled: isActive,
            child: ExcludeFocus(
              excluding: !isActive,
              child: KeyboardInsetHold(child: child!),
            ),
          ),
        );
      },
      child: keptView,
    );
  }
}

class _HomePageView extends ConsumerStatefulWidget {
  final IndexedWidgetBuilder pageBuilder;
  final List<NavigationItem> navigationItems;

  const _HomePageView({
    required this.pageBuilder,
    required this.navigationItems,
  });

  @override
  ConsumerState createState() => _HomePageViewState();
}

class _HomePageViewState extends ConsumerState<_HomePageView> {
  late PageController _pageController;

  List<int>? _order;
  int _slide = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _pageIndex);
    ref.listenManual(currentPageLabelProvider, (prev, next) {
      if (prev != next) {
        _toPage(next);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _HomePageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(
      _labelsOf(oldWidget.navigationItems),
      _labelsOf(widget.navigationItems),
    )) {
      _order = null;
      _updatePageController();
    }
  }

  static List<PageLabel> _labelsOf(List<NavigationItem> items) => [
    for (final item in items) item.label,
  ];

  int get _pageIndex => _indexOf(ref.read(currentPageLabelProvider));

  int _indexOf(PageLabel pageLabel) {
    final shown = shownPageLabelOf(pageLabel, widget.navigationItems);
    return widget.navigationItems.indexWhere((item) => item.label == shown);
  }

  Future<void> _toPage(
    PageLabel pageLabel, [
    bool ignoreAnimateTo = false,
  ]) async {
    if (!mounted) {
      return;
    }
    final index = _indexOf(pageLabel);
    if (index == -1) {
      return;
    }
    final tabAnimation = ref.read(appSettingProvider).tabAnimation;
    final isMobile = ref.read(isMobileViewProvider);
    final slide = ++_slide;
    final page = _pageController.hasClients
        ? _pageController.page?.round() ?? index
        : index;
    final current = _order?[page] ?? page;
    if (_order != null) {
      setState(() => _order = null);
      _pageController.jumpToPage(current);
    }
    if (!isMobile || ignoreAnimateTo) {
      _pageController.jumpToPage(index);
      return;
    }
    // As TabBarView does, so no page between is built and painted on the way.
    if ((index - current).abs() > 1) {
      final adjacent = index > current ? index - 1 : index + 1;
      setState(() {
        _order = List.generate(widget.navigationItems.length, (item) => item)
          ..[adjacent] = current
          ..[current] = adjacent;
      });
      _pageController.jumpToPage(adjacent);
    }
    final fade = tabAnimation == TabAnimation.fade;
    await _pageController.animateToPage(
      index,
      duration: fade ? fadeTabDuration : kTabScrollDuration,
      curve: fade ? fadeTabCurve : Curves.easeOut,
    );
    if (mounted && slide == _slide && _order != null) {
      setState(() => _order = null);
    }
  }

  void _updatePageController() {
    final pageLabel = ref.read(currentPageLabelProvider);
    _toPage(pageLabel, true);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final itemCount = ref.watch(
      currentNavigationItemsStateProvider.select((state) => state.value.length),
    );
    final fade = ref.watch(
      appSettingProvider.select(
        (state) => state.tabAnimation == TabAnimation.fade,
      ),
    );
    return PageView.builder(
      controller: _pageController,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      findChildIndexCallback: (key) {
        if (key is! ValueKey<PageLabel>) {
          return null;
        }
        final index = widget.navigationItems.indexWhere(
          (item) => item.label == key.value,
        );
        if (index == -1) {
          return null;
        }
        return _order?.indexOf(index) ?? index;
      },
      itemBuilder: (context, index) {
        final page = widget.pageBuilder(context, _order?[index] ?? index);
        return _FadeTabPage(
          key: page.key,
          controller: _pageController,
          position: index,
          enabled: fade,
          child: page,
        );
      },
    );
  }
}

/// Cancels the page view's slide so a tab switch cross-fades in place, and
/// wraps every page even when off so switching the setting keeps their state.
class _FadeTabPage extends StatelessWidget {
  const _FadeTabPage({
    super.key,
    required this.controller,
    required this.position,
    required this.enabled,
    required this.child,
  });

  final PageController controller;
  final int position;
  final bool enabled;
  final Widget child;

  double get _delta {
    if (!controller.hasClients || !controller.position.hasContentDimensions) {
      return 0;
    }
    final page = controller.page ?? position.toDouble();
    return (position - page).clamp(-1.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, child) {
        final offset = _delta;
        final delta = enabled ? offset : 0.0;
        return FractionalTranslation(
          translation: Offset(-delta, 0),
          child: Opacity(opacity: 1 - delta.abs(), child: child),
        );
      },
      child: child,
    );
  }
}

class HomeBackScopeContainer extends ConsumerWidget {
  final Widget child;

  const HomeBackScopeContainer({super.key, required this.child});

  @override
  Widget build(BuildContext context, ref) {
    return CommonPopScope(
      onPop: (context) async {
        final pageLabel = ref.read(shownPageLabelProvider);
        final realContext =
            GlobalObjectKey(pageLabel).currentContext ?? context;
        final canPop = Navigator.canPop(realContext);
        if (canPop) {
          Navigator.of(realContext).pop();
        } else if (system.isTV && pageLabel != PageLabel.dashboard) {
          ref
              .read(currentPageLabelProvider.notifier)
              .toPage(PageLabel.dashboard);
        } else {
          await ref.read(systemActionProvider.notifier).handleClose();
        }
        return false;
      },
      child: child,
    );
  }
}
