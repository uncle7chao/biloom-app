import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/state.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/dashboard/widgets/start_button.dart';
import 'package:fl_clash/views/profiles/overwrite/custom/groups.dart';
import 'package:fl_clash/views/proxies/list.dart';
import 'package:fl_clash/views/proxies/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'add_chain.dart';
import 'add_node.dart';
import 'region_groups.dart';
import 'setting.dart';
import 'tab.dart';

class ProxiesView extends ConsumerStatefulWidget {
  const ProxiesView({super.key});

  @override
  ConsumerState<ProxiesView> createState() => _ProxiesViewState();
}

class _ProxiesViewState extends ConsumerState<ProxiesView> {
  final GlobalKey<ProxiesTabViewState> _proxiesTabKey = GlobalKey();
  bool _hasProviders = false;
  bool _isTab = false;

  List<Widget> _buildActions(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return [
      if (_isTab)
        IconButton(
          tooltip: context.appLocalizations.scrollToSelected,
          onPressed: () {
            _proxiesTabKey.currentState?.scrollToGroupSelected();
          },
          icon: const Icon(Icons.adjust, weight: 1),
        ),
      CommonPopupBox(
        targetBuilder: (open) {
          return IconButton(
            tooltip: context.appLocalizations.more,
            onPressed: () {
              final isMobile = ref.read(isMobileViewProvider);
              open(offset: Offset(0, isMobile ? 0 : 20));
            },
            icon: const Icon(Icons.more_vert),
          );
        },
        popupBuilder: (_) => CommonPopupMenu(
          items: [
            CommonPopupMenuItem(
              icon: Icons.add_circle_outline,
              label: appLocalizations.addProxyNode,
              onPressed: () {
                _handleAddProxyNode(context);
              },
            ),
            CommonPopupMenuItem(
              icon: Icons.account_tree_outlined,
              label: appLocalizations.addProxyGroup,
              onPressed: () {
                _handleOpenProxyGroups(context);
              },
            ),
            CommonPopupMenuItem(
              icon: Icons.link,
              label: appLocalizations.addProxyChain,
              onPressed: () {
                _handleAddProxyChain(context);
              },
            ),
            CommonPopupMenuItem(
              icon: Icons.category_outlined,
              label: appLocalizations.generateRegionGroups,
              onPressed: () {
                _handleGenerateRegionGroups(context);
              },
            ),
            CommonPopupMenuItem(
              icon: Icons.tune,
              label: appLocalizations.settings,
              onPressed: () {
                showSheet(
                  context: context,
                  props: const SheetProps(isScrollControlled: true),
                  builder: (_) {
                    return AdaptiveSheetScaffold(
                      body: const ProxiesSetting(),
                      title: appLocalizations.settings,
                    );
                  },
                );
              },
            ),
            if (_hasProviders)
              CommonPopupMenuItem(
                icon: Icons.poll_outlined,
                label: appLocalizations.providers,
                onPressed: () {
                  showExtend(
                    context,
                    builder: (_) {
                      return const ProvidersView();
                    },
                  );
                },
              ),
          ],
        ),
      ),
    ];
  }

  /// 右下角的悬浮按钮区。
  ///
  /// **启动按钮在下、整组测速在上** —— 挑节点和连接是同一件事的两半，
  /// 挑完就在这一页连上，不用再退回仪表盘。启动按钮直接复用仪表盘那颗
  /// [StartButton]（自带运行时长、没有订阅时会说清缺什么），不另造一套。
  ///
  /// tab 布局下两颗叠起来有 106 高，比 `BottomInsetScope` 假设的多 50，
  /// 所以列表底部额外补了 `proxiesExtraFabInset`（见 `common.dart`）。
  Widget? _buildFAB() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_isTab) ...[
          DelayTestButton(
            onClick: () async {
              await _proxiesTabKey.currentState?.delayTestCurrentGroup();
            },
          ),
          const SizedBox(height: 10),
        ],
        const StartButton(),
      ],
    );
  }

  /// 打开「新增节点」面板。
  ///
  /// 面板作用于**当前选中的配置**：节点属于配置，没有配置就没有可写的地方。
  /// 当前没有配置时直接不弹 —— 弹出来也只能报「找不到这份配置」。
  void _handleAddProxyNode(BuildContext context) {
    final profileId = ref.read(currentProfileIdProvider);
    if (profileId == null) return;
    showSheet(
      context: context,
      props: const SheetProps(isScrollControlled: true),
      builder: (_) => AddProxyNodeView(profileId: profileId),
    );
  }

  /// 打开「添加链式代理」面板。
  ///
  /// **不能用上游那个带 `relay` 类型的策略组编辑页**：`relay` 组类型在本内核里已被
  /// 删除（`Clash.Meta/adapter/outboundgroup/parser.go:216`），存进去会让整份配置
  /// 加载失败。链式代理现在的形态是代理级的 `dialer-proxy` 字段，所以走这个专用面板。
  void _handleAddProxyChain(BuildContext context) {
    final profileId = ref.read(currentProfileIdProvider);
    if (profileId == null) return;
    showSheet(
      context: context,
      props: const SheetProps(isScrollControlled: true),
      builder: (_) => AddProxyChainView(profileId: profileId),
    );
  }

  /// 打开策略组编辑页。
  ///
  /// 这里刻意不另做一套策略组 UI：自定义分组存在**覆写数据**里（订阅更新冲不掉），
  /// 而覆写数据只在「自定义」模式下生效 —— 所以先把模式切过去并同步当前分组，
  /// 再把用户送到上游那个功能完整的现成编辑页。
  ///
  /// 切模式会改变配置的生成方式（覆写是一份快照，之后订阅带来的新分组不会自动
  /// 出现），所以必须先问过用户，不能默默改。
  Future<void> _handleOpenProxyGroups(BuildContext context) async {
    final appLocalizations = context.appLocalizations;
    final profileId = ref.read(currentProfileIdProvider);
    if (profileId == null) return;
    final profile = ref.read(profileProvider(profileId));
    if (profile == null) return;
    if (profile.overwriteType != OverwriteType.custom) {
      final confirmed = await dialogs.showMessage(
        message: TextSpan(text: appLocalizations.customOverwriteRequired),
      );
      if (confirmed != true || !context.mounted) return;
      await ref
          .read(profilesActionProvider.notifier)
          .ensureCustomOverwrite(profileId);
      if (!context.mounted) return;
    }
    await BaseNavigator.push(
      context,
      CustomProxyGroupsView(profileId, autoAdd: true),
    );
  }

  /// 打开「按地区生成分组」面板。
  ///
  /// 生成出来的分组存在**覆写数据**里，所以和 [CustomProxyGroupsView] 是同一个前提：
  /// 配置得先在「自定义覆写」模式下，写进去的分组才真的生效。切模式会改变配置的
  /// 生成方式，必须先问过用户 —— 直接照搬上面那段确认流程，不另造一套说法。
  ///
  /// 面板自己是「现算计划」的（只读），所以这里不需要先把计划算好再打开；关掉面板
  /// 就什么都不会发生。
  Future<void> _handleGenerateRegionGroups(BuildContext context) async {
    final appLocalizations = context.appLocalizations;
    final profileId = ref.read(currentProfileIdProvider);
    if (profileId == null) return;
    final profile = ref.read(profileProvider(profileId));
    if (profile == null) return;
    if (profile.overwriteType != OverwriteType.custom) {
      final confirmed = await dialogs.showMessage(
        message: TextSpan(text: appLocalizations.customOverwriteRequired),
      );
      if (confirmed != true || !context.mounted) return;
      await ref
          .read(profilesActionProvider.notifier)
          .ensureCustomOverwrite(profileId);
      if (!context.mounted) return;
    }
    await showSheet(
      context: context,
      props: const SheetProps(isScrollControlled: true),
      builder: (_) => RegionGroupPlanView(profileId: profileId),
    );
  }

  void _onSearch(String value) {
    ref.read(queryProvider(QueryTag.proxies).notifier).value = value;
  }

  @override
  void initState() {
    super.initState();
    ref.listenManual(providersProvider.select((state) => state.isNotEmpty), (
      prev,
      next,
    ) {
      if (prev != next) {
        setState(() {
          _hasProviders = next;
        });
      }
    }, fireImmediately: true);
    ref.listenManual(
      proxiesStyleSettingProvider.select(
        (state) => state.type == ProxiesType.tab,
      ),
      (prev, next) {
        if (prev != next) {
          setState(() {
            _isTab = next;
          });
        }
      },
      fireImmediately: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final proxiesType = ref.watch(
      proxiesStyleSettingProvider.select((state) => state.type),
    );
    final isLoading = ref.watch(loadingProvider(LoadingTag.proxies));
    return CommonScaffold(
      isLoading: isLoading,
      resizeToAvoidBottomInset: false,
      floatingActionButton: _buildFAB(),
      actions: _buildActions(context),
      title: context.appLocalizations.proxies,
      searchState: AppBarSearchState(onSearch: _onSearch),
      body: switch (proxiesType) {
        ProxiesType.tab => ProxiesTabView(key: _proxiesTabKey),
        ProxiesType.list => const ProxiesListView(),
      },
    );
  }
}
