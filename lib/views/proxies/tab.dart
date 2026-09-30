import 'dart:async';
import 'dart:math';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/clash_config.dart';
import 'package:fl_clash/models/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'card.dart';
import 'common.dart';
import 'dashboard.dart';
import 'region_bar.dart';

typedef ProxyGroupViewKeyMap =
    Map<String, GlobalObjectKey<_ProxyGroupViewState>>;

class ProxiesTabView extends ConsumerStatefulWidget {
  const ProxiesTabView({super.key});

  static Map<String, PageStorageKey> pageListStoreMap = {};

  @override
  ConsumerState<ProxiesTabView> createState() => ProxiesTabViewState();
}

class ProxiesTabViewState extends ConsumerState<ProxiesTabView>
    with TickerProviderStateMixin {
  TabController? _tabController;
  final _hasMoreButtonNotifier = ValueNotifier<bool>(false);
  ProxyGroupViewKeyMap _keyMap = {};

  @override
  void initState() {
    super.initState();
    ref.listenManual(proxiesTabControllerStateProvider, (prev, next) {
      if (prev == next) {
        return;
      }
      if (!stringListEquality.equals(prev?.groupNames, next.groupNames)) {
        final groupNames = next.groupNames;
        final currentGroupName = next.currentGroupName;
        final index = groupNames.indexWhere((item) => item == currentGroupName);
        _updateTabController(groupNames.length, index);
      }
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _destroyTabController();
    _hasMoreButtonNotifier.dispose();
    super.dispose();
  }

  void scrollToGroupSelected() {
    final group = currentGroup;
    if (group == null) {
      return;
    }
    _keyMap[group.name]?.currentState?.scrollToSelected();
  }

  Future<void> delayTestCurrentGroup() async {
    final group = currentGroup;
    if (group == null) {
      return;
    }
    await ref
        .read(proxiesActionProvider.notifier)
        .delayTest(group.all, group.testUrl);
  }

  Group? get currentGroup {
    return _getGroup(_tabController?.index);
  }

  Group? _getGroup(int? index) {
    final groups = ref.read(proxiesTabStateProvider).groups;
    if (index == null || index < 0 || index >= groups.length) {
      return null;
    }
    return groups[index];
  }

  Widget _buildMoreButton() {
    return Consumer(
      builder: (_, ref, _) {
        final isMobileView = ref.watch(isMobileViewProvider);
        return IconButton(
          tooltip: context.appLocalizations.more,
          onPressed: _showMoreMenu,
          icon: isMobileView
              ? const Icon(Icons.expand_more)
              : const Icon(Icons.chevron_right),
        );
      },
    );
  }

  void _showMoreMenu() {
    showSheet(
      context: context,
      props: const SheetProps(isScrollControlled: false),
      builder: (_) {
        return AdaptiveSheetScaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Consumer(
              builder: (_, ref, _) {
                final state = ref.watch(proxiesTabControllerStateProvider);
                final groupNames = state.groupNames;
                final currentGroupName = state.currentGroupName;
                return SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    runSpacing: 8,
                    spacing: 8,
                    children: [
                      for (final groupName in groupNames)
                        SettingTextCard(
                          groupName,
                          onPressed: () {
                            final index = groupNames.indexWhere(
                              (item) => item == groupName,
                            );
                            if (index == -1) return;
                            _tabController?.animateTo(index);
                            ref
                                .read(proxiesActionProvider.notifier)
                                .updateCurrentGroupName(groupName);
                            Navigator.of(context).pop();
                          },
                          isSelected: groupName == currentGroupName,
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          title: context.appLocalizations.proxyGroup,
        );
      },
    );
  }

  void _tabControllerListener([int? index]) {
    final group = _getGroup(index ?? _tabController?.index);
    if (group == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref
          .read(proxiesActionProvider.notifier)
          .updateCurrentGroupName(group.name);
    });
  }

  void _destroyTabController() {
    _tabController?.removeListener(_tabControllerListener);
    _tabController?.dispose();
    _tabController = null;
  }

  // An empty group list keeps the previous controller: the outgoing tab bar
  // still drives it while the empty state animates in.
  void _updateTabController(int length, int index) {
    if (length == 0) {
      return;
    }
    _destroyTabController();
    final realIndex = index == -1 ? 0 : index;
    final controller = TabController(
      length: length,
      initialIndex: realIndex,
      vsync: this,
    );
    _tabController = controller;
    _tabControllerListener(realIndex);
    controller.addListener(_tabControllerListener);
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    ref.watch(themeSettingProvider.select((state) => state.textScale));
    final state = ref.watch(proxiesTabStateProvider.select((state) => state));
    final proxiesLayout = ref.watch(
      proxiesStyleSettingProvider.select((state) => state.layout),
    );
    final groups = state.groups;
    // 页签下标是「屏幕上正在显示哪个组」的唯一真相（`currentGroupName` 只是它的
    // 一份延后一帧的镜像）。地区筛选栏挂在当前页签上，所以用它取当前组。
    final tabIndex = _tabController?.index ?? 0;
    final currentGroup = (tabIndex >= 0 && tabIndex < groups.length)
        ? groups[tabIndex]
        : null;
    _keyMap = {};
    return NullStatusSwitcher(
      isEmpty: groups.isEmpty || _tabController == null,
      nullStatus: NullStatus(
        illustration: NullStatusIllustration.proxies,
        label: appLocalizations.nullTip(appLocalizations.proxies),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NotificationListener<ScrollMetricsNotification>(
            onNotification: (scrollNotification) {
              _hasMoreButtonNotifier.value =
                  scrollNotification.metrics.maxScrollExtent > 0;
              return false;
            },
            child: ValueListenableBuilder(
              valueListenable: _hasMoreButtonNotifier,
              builder: (_, value, child) {
                return Stack(
                  alignment: AlignmentDirectional.centerStart,
                  children: [
                    AnimatedBuilder(
                      animation: _tabController!,
                      builder: (_, _) {
                        return TabBar(
                          controller: _tabController,
                          padding: EdgeInsets.only(
                            left: 16,
                            right: 16 + (value ? 16 : 0),
                          ),
                          dividerColor: Colors.transparent,
                          // 选中态交给页签自己的胶囊（与地区筛选 chip 同一套
                          // 语言），内核下划线指示器整个撤掉。
                          indicator: const BoxDecoration(),
                          isScrollable: true,
                          tabAlignment: TabAlignment.start,
                          labelPadding: const EdgeInsets.symmetric(
                            horizontal: 3,
                          ),
                          tabs: [
                            for (var i = 0; i < groups.length; i++)
                              Tab(
                                child: _ProxyTabPill(
                                  name: groups[i].name,
                                  selected: i == _tabController!.index,
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    if (value) Positioned(right: 0, child: child!),
                  ],
                );
              },
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      context.colorScheme.surface.opacity10,
                      context.colorScheme.surface,
                    ],
                    // 渐变带拉宽：「更多」按钮不再从一条硬边上突然冒出来。
                    stops: const [0.0, 0.25],
                  ),
                ),
                child: _buildMoreButton(),
              ),
            ),
          ),
          // 「当前出口」仪表卡（2026-09-30 改版 A 档）：固定在页签与地区筛选
          // 之间，不随页签切换 —— 翻到任何页签都先看到现在走的是谁。没配置 /
          // 找不到生效选择器时组件自己隐藏，这里无需判空。
          const ProxyExitDashboard(),
          // 地区筛选栏：把当前页签的节点按出口地区归好，一次点选收窄列表。
          // 它贴在页签底下、列表之上 —— 换页签换内容，不用回来重新点。
          if (currentGroup != null)
            ProxyRegionFilterBar(
              groupName: currentGroup.name,
              proxies: currentGroup.all,
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (_, constraints) {
                final columns = getProxiesColumns(
                  max(constraints.maxWidth - 32, 0),
                  proxiesLayout,
                );
                return TabBarView(
                  controller: _tabController,
                  children: [
                    for (final group in groups)
                      ProxyGroupView(
                        key: _keyMap.updateCacheValue(
                          group.name,
                          () =>
                              GlobalObjectKey<_ProxyGroupViewState>(group.name),
                        ),
                        group: group,
                        columns: columns,
                        cardType: state.proxyCardType,
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ProxyGroupView extends ConsumerStatefulWidget {
  final Group group;
  final int columns;
  final ProxyCardType cardType;

  const ProxyGroupView({
    super.key,
    required this.group,
    required this.columns,
    required this.cardType,
  });

  @override
  ConsumerState<ProxyGroupView> createState() => _ProxyGroupViewState();
}

/// 按地区收窄节点列表。
///
/// 收敛不成立时（没选地区 / 选的地区这一组里已经没有了）**原样返回** —— 与
/// `ProxyRegionFilterBar` 的高亮判断共用 [resolveEffectiveRegionFilter]，
/// 两侧必须给出同一个答案，否则会出现「芯片标着香港、列表却是全部」。
/// [landingByProxy] 与筛选栏传的是同一份实测落地 —— 两侧对同一个节点必须
/// 归到同一个地区，否则会出现「芯片在『其他』里、列表却被筛进『🇲🇾』」。
List<Proxy> _applyRegionFilter(
  List<Proxy> proxies,
  String? regionKey,
  Map<String, String> landingByProxy,
) {
  final effective = resolveEffectiveRegionFilter(
    buckets: groupProxyNamesByRegion(
      proxies.map((proxy) => proxy.name),
      landingByProxy: landingByProxy,
    ),
    key: regionKey,
  );
  if (effective == null) {
    return proxies;
  }
  return proxies
      .where(
        (proxy) =>
            resolveProxyRegionWithLanding(proxy.name, landingByProxy).key ==
            effective,
      )
      .toList();
}

class _ProxyGroupViewState extends ConsumerState<ProxyGroupView> {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
  }

  PageStorageKey _getPageStorageKey() {
    final profile = ref.read(currentProfileProvider);
    final key =
        '${profile?.id}_${ScrollPositionCacheKey.proxiesTabList.name}_${widget.group.name}';
    return ProxiesTabView.pageListStoreMap.updateCacheValue(
      key,
      () => PageStorageKey(key),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void scrollToSelected() {
    if (_controller.position.maxScrollExtent == 0) {
      return;
    }
    _controller.animateTo(
      min(
        16 +
            getScrollToSelectedOffset(
              ref: ref,
              groupName: widget.group.name,
              // 用**筛选之后**的列表算下标：当前生效的那个节点在筛选后的列表里，
              // 拿未筛选的列表算出来的位置会偏出去。
              proxies: _applyRegionFilter(
                widget.group.all,
                ref.read(proxyRegionFilterProvider)[widget.group.name],
                ref.read(proxyLandingCodesProvider),
              ),
              columns: widget.columns,
            ),
        _controller.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeIn,
    );
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    // 收藏置顶：与列表布局同一套稳定分区（common.dart 的 orderFavoritesFirst），
    // 页签布局与列表布局看到的顺序必须一致。
    final profileId = ref.watch(currentProfileIdProvider);
    final favorites = ref.watch(
      proxyFavoritesProvider.select(
        (value) => profileId == null
            ? null
            : value.value?[profileId.toString()]?.toSet(),
      ),
    );
    final proxies = orderFavoritesFirst(
      _applyRegionFilter(
        group.all,
        // 用 `read` 拿不到变化 —— 必须先 `watch` 起来，筛选一改这一页才会重建。
        ref.watch(
          proxyRegionFilterProvider.select((state) => state[group.name]),
        ),
        ref.watch(proxyLandingCodesProvider),
      ),
      favorites,
    );
    return CommonScrollBar(
      controller: _controller,
      child: GridView.builder(
        key: _getPageStorageKey(),
        controller: _controller,
        padding: EdgeInsets.only(
          top: 16,
          left: 16,
          right: 16,
          // `BottomInsetScope` 只按「一颗 56 高的 FAB」给了 72，而右下角现在
          // 叠了两颗（测速 + 启动），差出来的那一截得自己补上，否则滚到底时
          // 最后一排节点会被按钮压住。
          bottom: 16 + BottomInsetScope.of(context) + proxiesExtraFabInset,
        ),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: widget.columns,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          mainAxisExtent: getItemHeight(widget.cardType),
        ),
        itemCount: proxies.length,
        itemBuilder: (_, index) {
          final proxy = proxies[index];
          return ProxyCard(
            testUrl: group.testUrl,
            groupType: group.type,
            type: widget.cardType,
            proxy: proxy,
            groupName: group.name,
          );
        },
      ),
    );
  }
}

class DelayTestButton extends StatefulWidget {
  final Future Function() onClick;

  const DelayTestButton({super.key, required this.onClick});

  @override
  State<DelayTestButton> createState() => _DelayTestButtonState();
}

class _DelayTestButtonState extends State<DelayTestButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  bool _running = false;

  Future<void> _healthcheck() async {
    if (_running) {
      return;
    }
    _running = true;
    unawaited(_controller.forward());
    try {
      await widget.onClick();
    } finally {
      _running = false;
      if (mounted) {
        unawaited(_controller.reverse());
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _animation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutBack),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final colorScheme = context.colorScheme;
    return AnimatedBuilder(
      animation: _controller.view,
      builder: (_, child) {
        return FadeTransition(
          opacity: _animation,
          child: ScaleTransition(scale: _animation, child: child),
        );
      },
      // 这一颗从「带文字的 extended」降级成小圆按钮：右下角的主位让给「启动」，
      // 整组测速是次级操作（**单节点**的测速入口现在直接画在每张卡片上，
      // 分组头里那颗 `Icons.network_ping` 也还在）。颜色刻意不跟启动按钮抢主题色。
      child: FloatingActionButton.small(
        heroTag: null,
        tooltip: appLocalizations.delayTest,
        onPressed: _healthcheck,
        backgroundColor: colorScheme.surfaceContainerHigh,
        foregroundColor: colorScheme.onSurfaceVariant,
        child: const Icon(Icons.network_ping),
      ),
    );
  }
}

/// 分组页签胶囊：选中 = secondaryContainer 底 + primary 细描边，与地区筛选
/// chip、节点卡「当前生效」是同一套选中语言（不引入第二套配色）。
/// 未选中 = 透明底 + 中性字。整体高度压在 TabBar 自身高度内，不改页签条
/// 的布局尺寸。
class _ProxyTabPill extends StatelessWidget {
  final String name;
  final bool selected;

  const _ProxyTabPill({required this.name, required this.selected});

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: AlignmentDirectional.center,
      decoration: BoxDecoration(
        color: selected ? colorScheme.secondaryContainer : Colors.transparent,
        borderRadius: AppRadius.full,
        border: Border.all(
          color: selected ? colorScheme.primary : Colors.transparent,
          width: 0.5,
        ),
      ),
      child: EmojiText(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.textTheme.labelLarge?.copyWith(
          color: selected
              ? colorScheme.onSecondaryContainer
              : colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
