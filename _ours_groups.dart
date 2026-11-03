import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/overwrite/overwrite.dart';
import 'package:fl_clash/models/models.dart' hide FileInfo;
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/profiles/overwrite/custom/proxy_providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'icon.dart';
import 'proxies.dart';

class CustomProxyGroupsView extends ConsumerStatefulWidget {
  final int profileId;

  /// 进入后自动打开「新建分组」表单。
  ///
  /// 「添加策略组」的入口用它把用户直接送到表单前：那个入口的语义就是「我要新建
  /// 一个组」，落到一个空列表页还要再找一次「新增」按钮是多余的一步。
  final bool autoAdd;

  const CustomProxyGroupsView(this.profileId, {super.key, this.autoAdd = false});

  @override
  ConsumerState createState() => _CustomProxyGroupsViewState();
}

class _CustomProxyGroupsViewState extends ConsumerState<CustomProxyGroupsView> {
  /// 展开的卡片 id 集合。
  ///
  /// **刻意放在页面而不是卡片自己身上**：列表是 builder 构造的，滚出屏幕就会被
  /// 回收，状态挂在卡片上会「滚动后自己收起来」；拖拽排序时 ReorderableListView
  /// 还会另建一个卡片做浮层，只有状态在页面上，浮层和原位才会是同一个展开态。
  final Set<int> _expandedIds = {};

  /// 坏数据只在进入页面时检查一次。
  bool _repairChecked = false;

  void _handleToggleExpanded(int id) {
    setState(() {
      if (!_expandedIds.remove(id)) {
        _expandedIds.add(id);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    // 存量坏数据检查。**必须是「监听」而不是「首帧去 read(future)」**：自定义分组
    // 来自数据库，首帧必然还没加载完；去 await 一个尚未就绪的异步 provider，会在
    // 页面被销毁时炸出「provider disposed during loading」。监听则天然等数据到齐。
    ref.listenManual(
      proxyGroupsProvider(widget.profileId).select(
        (state) =>
            state.value
                ?.where((group) => group.type == GroupType.Relay)
                .toList() ??
            const <ProxyGroup>[],
      ),
      (previous, next) {
        if (_repairChecked || next.isEmpty) return;
        _repairChecked = true;
        // 监听回调可能发生在构建期间，推弹窗要等这一帧结束。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_handleRepairRelayGroups(next));
        });
      },
      fireImmediately: true,
    );
    if (!widget.autoAdd) return;
    // 等首帧之后再弹表单：这时 OverwriteEditorPage 已经把自己挂好，
    // 立刻调用 showOverwriteNestedSheet 才能拿到正确的 context 与 profileId 作用域。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _handleAddOrUpdate();
      }
    });
  }

  /// 修掉存量数据里 `type: relay` 的分组。
  ///
  /// BiLoom 曾经把「添加链式代理」做成了 relay 分组，而那个类型在本内核里已被删除
  /// （`Clash.Meta/adapter/outboundgroup/parser.go:216`）—— 创建过的人，配置现在
  /// **整份都加载不了**，症状是连不上、而且看不出跟那个分组有关。这里直接给一键
  /// 修正，而不是让他自己去猜。
  ///
  /// 调用方保证 [groups] 非空、且整页只调用一次：用户在弹窗里选「取消」就是不想改，
  /// 不能因为列表重建就把同一个弹窗再推一遍。
  Future<void> _handleRepairRelayGroups(List<ProxyGroup> groups) async {
    final appLocalizations = context.appLocalizations;
    final confirmed = await dialogs.showMessage(
      message: TextSpan(
        text: appLocalizations.relayGroupRemovedConfirm(groups.length),
      ),
    );
    if (confirmed != true || !mounted) return;
    final notifier = ref.read(proxyGroupsProvider(widget.profileId).notifier);
    for (final group in groups) {
      notifier.put(group.copyWith(type: GroupType.Selector));
    }
    if (!mounted) return;
    unawaited(
      dialogs.showMessage(
        message: TextSpan(
          text: appLocalizations.relayGroupFixed(groups.length),
        ),
        cancelable: false,
      ),
    );
  }

  void _handleReorder(int oldIndex, int newIndex) {
    ref
        .read(proxyGroupsProvider(widget.profileId).notifier)
        .order(oldIndex, newIndex);
  }

  void _handleAddOrUpdate({ProxyGroup? proxyGroup}) {
    showOverwriteNestedSheet<ProxyGroup>(
      context: context,
      profileId: widget.profileId,
      overrides: [
        proxyGroupProvider.overrideWithBuild(
          (_, _) =>
              proxyGroup ??
              const ProxyGroup(
                id: -1,
                name: '',
                type: GroupType.Selector,
              ),
        ),
      ],
      currentOf: (ref) => ref.read(proxyGroupProvider),
      save: _handleSaveProxyGroup,
      formBuilder: (_) => const _EditProxyGroupView(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return OverwriteEditorPage<ProxyGroup>(
      title: appLocalizations.proxyGroup,
      idOf: (proxyGroup) => proxyGroup.id,
      itemsOf: (ref) {
        return ref
            .watch(
              customOverwriteDateProvider(
                widget.profileId,
              ).select((state) => SelectValue(state.proxyGroups)),
            )
            .value;
      },
      itemBuilder:
          (
            context,
            ref,
            proxyGroup,
            index,
            isEditing,
            isSelected,
            onToggleSelected,
          ) {
            return _ProxyGroupCard(
              key: ValueKey(proxyGroup.id),
              profileId: widget.profileId,
              proxyGroup: proxyGroup,
              index: index,
              isExpanded: _expandedIds.contains(proxyGroup.id),
              onToggleExpanded: () => _handleToggleExpanded(proxyGroup.id),
              onPressed: () {
                _handleAddOrUpdate(proxyGroup: proxyGroup);
              },
            );
          },
      onReorder: _handleReorder,
      onAdd: _handleAddOrUpdate,
      emptyLabel: appLocalizations.proxyGroupEmpty,
    );
  }
}

/// 从内核配置里取「这个组当前选中的那一项」。
///
/// `Proxy.now` 就是 Clash API 对策略组的当前选择 —— 选择器是用户点的，其余三类
/// 是内核自己算的，两种都落在这个字段里，不需要我们分情况处理。
/// 组不在配置里（覆写还没生效），或者内核没回传值时返回 null。
String? _currentOfGroup(AsyncValue<ClashConfig> state, String groupName) {
  for (final proxy in state.value?.proxies ?? const <Proxy>[]) {
    if (proxy.name != groupName) {
      continue;
    }
    final now = proxy.now;
    return (now == null || now.isEmpty) ? null : now;
  }
  return null;
}

IconData _groupTypeIcon(GroupType type) {
  return switch (type) {
    GroupType.Selector => Icons.touch_app_outlined,
    GroupType.URLTest => Icons.speed,
    GroupType.Fallback => Icons.alt_route,
    GroupType.LoadBalance => Icons.balance,
    GroupType.Relay => Icons.link,
  };
}

/// 一个策略组的卡片。
///
/// 信息层级对齐参考实现：**状态点 · 组图标 · 组名 · 类型 · 当前选中 · 节点数 · 展开**。
/// 但外观走 BiLoom 自己的一套，只有三条规矩：
///
/// - 品牌色只出现在「当前生效」那一处，不做整块高亮 —— 一屏十几个组的时候，
///   满屏高亮等于没有高亮；
/// - 状态点是**实测延迟**（复用「代理」页那套 `getDelayColor`），而不是只表类型
///   的圆点：用户真正想知道的是「这个组现在通不通」；
/// - 类型徽章、节点数、右侧动作一律中性色，不与「当前」抢视线。
class _ProxyGroupCard extends ConsumerWidget {
  /// 展开后最多预览这么多个节点。
  ///
  /// 一个组可以引用几百个节点（`include-all-proxies`），而展开态回答的是
  /// 「里面大概有些什么」，不是充当节点列表 —— 真实数量右侧那个徽章已经如实给了，
  /// 溢出部分用 `+N` 交代，不假装展示了全部。
  static const int _previewLimit = 12;

  final int profileId;
  final ProxyGroup proxyGroup;
  final int index;
  final bool isExpanded;
  final VoidCallback onPressed;
  final VoidCallback onToggleExpanded;

  const _ProxyGroupCard({
    super.key,
    required this.profileId,
    required this.proxyGroup,
    required this.index,
    required this.isExpanded,
    required this.onPressed,
    required this.onToggleExpanded,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final members = proxyGroup.proxies ?? const <String>[];
    final providers = proxyGroup.use ?? const <String>[];
    final includeAllProxies = proxyGroup.includeAllProxies ?? false;
    final isInvalid = ref.watch(
      invalidProxyGroupIdsProvider(
        profileId,
      ).select((state) => state.contains(proxyGroup.id)),
    );
    // 异常要说清是哪一种：`relay` 是**整份配置加载不了**，而成员引用不到只是这一组
    // 有问题。两者都说成「检测到异常」，用户没法判断该先修哪个。
    final invalidMessage = proxyGroup.type == GroupType.Relay
        ? appLocalizations.relayGroupRemovedTip
        : appLocalizations.proxyGroupDetectedAbnormal;
    // 内核里存在这个组、并且报出了当前选中项，才有得显示。配置还没加载完，
    // 或者这份覆写还没生效（标准 / 脚本模式）时就是 null ——
    // 那就**不显示这一项**，而不是编一个出来。
    final currentName = ref.watch(
      clashConfigProvider(
        profileId,
      ).select((state) => _currentOfGroup(state, proxyGroup.name)),
    );
    final expandable =
        includeAllProxies ||
        members.isNotEmpty ||
        providers.isNotEmpty ||
        (proxyGroup.filter?.isNotEmpty ?? false) ||
        (proxyGroup.excludeFilter?.isNotEmpty ?? false);
    return Padding(
      // 卡片之间留缝。原来是「分组列表 + 分隔线」，但展开态塞不进那种一行一条的
      // 分隔线结构里 —— 一行变高之后，分隔线会横在卡片中间。
      padding: const EdgeInsets.only(bottom: 8),
      child: CommonCard(
        type: CommonCardType.filled,
        isError: isInvalid,
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 2, 10),
              child: Row(
                children: [
                  _GroupStatusDot(
                    isInvalid: isInvalid,
                    currentName: currentName,
                  ),
                  const SizedBox(width: 10),
                  SizedBox.square(
                    dimension: 28,
                    child: IconTheme.merge(
                      data: const IconThemeData(size: 28),
                      child: CommonTargetIcon(src: proxyGroup.icon ?? ''),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TooltipText(
                          text: Text(
                            proxyGroup.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.textTheme.bodyLarge,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _GroupMetaRow(
                          type: proxyGroup.type,
                          currentName: currentName,
                          isInvalid: isInvalid,
                          invalidMessage: invalidMessage,
                          includeAllProxies: includeAllProxies,
                        ),
                      ],
                    ),
                  ),
                  if (!includeAllProxies) _NumberCard(number: members.length),
                  if (expandable)
                    IconButton(
                      tooltip: isExpanded
                          ? appLocalizations.showLess
                          : appLocalizations.showMore,
                      onPressed: onToggleExpanded,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 32,
                        height: 32,
                      ),
                      iconSize: 20,
                      icon: AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeInOut,
                        child: const Icon(Icons.expand_more),
                      ),
                    ),
                  CommonReorderableDragStartListener(
                    index: index,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 10,
                      ),
                      child: Icon(Icons.drag_handle),
                    ),
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: isExpanded && expandable
                  ? _buildExpanded(
                      context,
                      ref,
                      currentName: currentName,
                      members: members,
                      providers: providers,
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpanded(
    BuildContext context,
    WidgetRef ref, {
    required String? currentName,
    required List<String> members,
    required List<String> providers,
  }) {
    final appLocalizations = context.appLocalizations;
    final filter = proxyGroup.filter;
    final excludeFilter = proxyGroup.excludeFilter;
    final hasChips =
        providers.isNotEmpty ||
        (filter?.isNotEmpty ?? false) ||
        (excludeFilter?.isNotEmpty ?? false);
    final preview = members.take(_previewLimit).toList();
    // 节点协议类型来自覆写校验用的那份数据，不另外解析一遍 YAML。
    final proxyTypes = ref.watch(
      customOverwriteDateProvider(
        profileId,
      ).select((state) => state.proxyTypes),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1, indent: 14, endIndent: 14),
        if (hasChips)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final provider in providers)
                  _GroupChip(label: provider, icon: Icons.dns_outlined),
                if (filter != null && filter.isNotEmpty)
                  _GroupChip(
                    label: filter,
                    icon: Icons.filter_alt_outlined,
                    tooltip: appLocalizations.proxyFilter,
                  ),
                if (excludeFilter != null && excludeFilter.isNotEmpty)
                  _GroupChip(
                    label: excludeFilter,
                    icon: Icons.filter_alt_off_outlined,
                    tooltip: appLocalizations.excludeProxyFilter,
                  ),
              ],
            ),
          ),
        if (preview.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                // 340 这个上限是算出来的，不是拍的：一个节点块里「圆点 + 名称 +
                // 协议 + 延迟」有约 136px 是固定宽度，剩下的才给名称。上限取 260 时
                // 手机屏（可用宽度约 328）会被切成两列、每列 161，名称只剩 25px ——
                // 直接糊成省略号。取 340 之后手机是单列、平板/桌面是 2–3 列，
                // 最窄的一列也有 ~229px。
                maxCrossAxisExtent: 340,
                // 跟着文字缩放走。写死 34 的话，用户把字号调大就会在块里溢出。
                mainAxisExtent: globalState.measure.bodySmallHeight + 16,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
              ),
              itemCount: preview.length,
              itemBuilder: (_, i) {
                final name = preview[i];
                return _GroupNodeTile(
                  name: name,
                  type: proxyTypes[name],
                  isCurrent: name == currentName,
                );
              },
            ),
          ),
        if (members.length > _previewLimit)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                '+${members.length - _previewLimit}',
                style: context.textTheme.labelSmall,
              ),
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// 卡片左侧的状态点。
///
/// 三种语义，一眼可分：
/// - **红**：这个组引用了不存在的节点或代理集，配置是坏的（优先于一切）；
/// - **实心有色**：组在内核里、且已知当前节点 —— 颜色就是那个节点的实测延迟；
/// - **空心灰**：配置还没生效，或者还没测过速。不猜、不编颜色。
class _GroupStatusDot extends StatelessWidget {
  static const double _size = 9;

  final bool isInvalid;
  final String? currentName;

  const _GroupStatusDot({required this.isInvalid, required this.currentName});

  Widget _buildDot(Color color, {bool hollow = false, String? tooltip}) {
    final dot = Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hollow ? null : color,
        border: hollow ? Border.all(color: color, width: 1.5) : null,
      ),
    );
    if (tooltip == null) {
      return dot;
    }
    return Tooltip(message: tooltip, child: dot);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    if (isInvalid) {
      return _buildDot(colorScheme.error);
    }
    final idleColor = colorScheme.onSurfaceVariant.opacity38;
    final name = currentName;
    if (name == null) {
      return _buildDot(idleColor, hollow: true);
    }
    return Consumer(
      builder: (context, ref, _) {
        final value = ref.watch(delayProvider(proxyName: name, testUrl: null));
        final color = getDelayColor(value);
        if (value == null || color == null) {
          return _buildDot(idleColor, hollow: true);
        }
        return _buildDot(color, tooltip: value > 0 ? '$value ms' : 'Timeout');
      },
    );
  }
}

/// 卡片第二行：类型徽章 + 当前选中（+ 实测延迟）。
class _GroupMetaRow extends StatelessWidget {
  final GroupType type;
  final String? currentName;
  final bool isInvalid;

  /// 异常的原因，由调用方按类型给出（组类型废弃 / 成员引用不到是两回事）。
  final String invalidMessage;
  final bool includeAllProxies;

  const _GroupMetaRow({
    required this.type,
    required this.currentName,
    required this.isInvalid,
    required this.invalidMessage,
    required this.includeAllProxies,
  });

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final colorScheme = context.colorScheme;
    final textStyle = context.textTheme.labelSmall;
    final name = currentName;
    return Row(
      children: [
        _GroupChip(label: type.name, icon: _groupTypeIcon(type)),
        const SizedBox(width: 6),
        // 这一项不是装饰：引用了全部节点的组**没有**节点数可报（数量由内核在
        // 运行时决定），所以那个数字徽章会缺席 —— 原因得写在卡片上，
        // 否则用户只会看到「这个组比别人少一个数字」。
        if (includeAllProxies)
          _GroupChip(
            label: appLocalizations.includeAllProxies,
            icon: Icons.select_all,
          ),
        const SizedBox(width: 8),
        if (isInvalid)
          // 原来这里只有一个孤零零的 `!` 图标，现在换成说清楚哪不对。
          Flexible(
            child: TooltipText(
              text: Text(
                invalidMessage,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyle?.copyWith(color: colorScheme.error),
              ),
            ),
          )
        else if (name != null) ...[
          Text(appLocalizations.currentSelected, style: textStyle),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textStyle?.copyWith(color: colorScheme.primary),
            ),
          ),
          const SizedBox(width: 6),
          _GroupDelayText(proxyName: name),
        ],
      ],
    );
  }
}

/// 当前节点的实测延迟。
///
/// 没测过就什么都不显示 —— 不写「未知」、也不写 0，那两种都会让人以为测过了。
class _GroupDelayText extends ConsumerWidget {
  final String proxyName;

  const _GroupDelayText({required this.proxyName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(delayProvider(proxyName: proxyName, testUrl: null));
    if (value == null) {
      return const SizedBox.shrink();
    }
    return Text(
      value > 0 ? '$value ms' : 'Timeout',
      maxLines: 1,
      style: context.textTheme.labelSmall?.copyWith(
        color: getDelayColor(value),
      ),
    );
  }
}

/// 中性小胶囊，用来承载类型、代理集名、过滤条件这类**解释性**信息。
///
/// 底色刻意比卡片浅一档并带一圈描边：卡片本身已经是 `surfaceContainerHigh`，
/// 直接用 `surfaceContainerHighest` 做胶囊在浅色主题里几乎看不见边界。
class _GroupChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final String? tooltip;

  const _GroupChip({required this.label, this.icon, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final color = colorScheme.onSurfaceVariant;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.xs,
        border: Border.all(color: colorScheme.outlineVariant, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.labelSmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
    if (tooltip == null) {
      return chip;
    }
    return Tooltip(message: tooltip, child: chip);
  }
}

/// 展开态里的一个节点。
///
/// 只读：这里回答「组里有什么、通不通」，改成员关系要点卡片进编辑表单。
/// 所以那个圆点表达的是「是不是当前在用的那个」，不是可点的单选框。
class _GroupNodeTile extends ConsumerWidget {
  final String name;
  final String? type;
  final bool isCurrent;

  const _GroupNodeTile({
    required this.name,
    required this.isCurrent,
    this.type,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    final value = ref.watch(delayProvider(proxyName: name, testUrl: null));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.sm,
        border: Border.all(
          color: isCurrent ? colorScheme.primary : colorScheme.outlineVariant,
          width: isCurrent ? 1 : 0.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCurrent
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.bodySmall,
            ),
          ),
          if (type != null) ...[
            const SizedBox(width: 6),
            Text(
              type!,
              maxLines: 1,
              style: context.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(width: 8),
          Text(
            value == null ? '—' : (value > 0 ? '$value ms' : 'Timeout'),
            maxLines: 1,
            style: context.textTheme.labelSmall?.copyWith(
              color: getDelayColor(value) ?? colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

bool _handleSaveProxyGroup(BuildContext context, WidgetRef ref) {
  final appLocalizations = context.appLocalizations;
  final proxyGroup = ref.read(proxyGroupProvider);
  if (proxyGroup.name.isEmpty) {
    dialogs.showMessage(
      message: TextSpan(text: appLocalizations.proxyGroupNameEmpty),
      cancelable: false,
    );
    return false;
  }
  final profileId = ProfileIdProvider.of(context)!.profileId;
  final ProxyGroup newProxyGroup;
  if (proxyGroup.id == -1) {
    newProxyGroup = proxyGroup.copyWith(id: snowflake.id);
  } else {
    newProxyGroup = proxyGroup;
  }
  final isRepeat = ref
      .read(proxyGroupsProvider(profileId).notifier)
      .put(newProxyGroup);
  if (isRepeat == false) {
    dialogs.showMessage(
      message: TextSpan(text: appLocalizations.proxyGroupNameDuplicate),
      cancelable: false,
    );
    return false;
  } else {
    return true;
  }
}

class _EditProxyGroupView extends ConsumerStatefulWidget {
  const _EditProxyGroupView();

  @override
  ConsumerState createState() => _EditProxyGroupViewState();
}

class _EditProxyGroupViewState extends ConsumerState<_EditProxyGroupView> {
  /// 可选的策略组类型。
  ///
  /// **刻意排除 `GroupType.Relay`**：`relay` 这个分组类型在本内核里已被删除
  /// （`Clash.Meta/adapter/outboundgroup/parser.go:216` 直接返回错误），一旦存进
  /// 覆写数据，用户下一次切换配置时**整份配置都会加载失败**，而且报错是一句英文的
  /// 「relay type was removed」，没人能从中看出是自己刚才选的那个类型。既然它必然
  /// 导致坏配置，就不该出现在选项里。
  ///
  /// 链式代理的正路是代理级的 `dialer-proxy` 字段，入口在「代理」页的
  /// ⋮ → 添加链式代理（`views/proxies/add_chain.dart`）。
  static const List<GroupType> _selectableTypes = [
    GroupType.Selector,
    GroupType.URLTest,
    GroupType.Fallback,
    GroupType.LoadBalance,
  ];

  Future<void> _showTypeOptions(GroupType type) async {
    final value = await dialogs.showCommonDialog<GroupType>(
      child: OptionsDialog<GroupType>(
        title: context.appLocalizations.proxyType,
        options: _selectableTypes,
        textBuilder: (item) => item.name,
        // 存量数据里可能已经有 relay 的组（它其实是坏的）。这时 value 不在 options
        // 里，RadioGroup 一项都不会高亮 —— 比把一个坏类型显示成「已选中」诚实。
        value: type,
      ),
    );
    if (value == null) {
      return;
    }
    ref
        .read(proxyGroupProvider.notifier)
        .update((state) => state.copyWith(type: value));
  }

  Future<void> _showIconEdit(String? icon) async {
    final value = await Navigator.of(
      context,
    ).push<String>(PagedSheetRoute(builder: (context) => IconEditView(icon)));
    if (value == null) {
      return;
    }
    ref
        .read(proxyGroupProvider.notifier)
        .update((state) => state.copyWith(icon: value));
  }

  Widget _buildItem({
    required String title,
    TextStyle? titleStyle,
    Widget? trailing,
    final VoidCallback? onPressed,
    bool invalid = false,
  }) {
    return OverwriteFormRow(
      invalid: invalid,
      onPressed: onPressed,
      title: title,
      titleStyle: titleStyle,
      trailing: trailing,
    );
  }

  void _handleToProxiesView() {
    Navigator.of(
      context,
    ).push(PagedSheetRoute(builder: (context) => const EditProxiesView()));
  }

  void _handleToProvidersView() {
    Navigator.of(context).push(
      PagedSheetRoute(builder: (context) => const EditProxyProvidersView()),
    );
  }

  Widget _buildProvidersItem(bool includeAllProviders, List<String> use) {
    final appLocalizations = context.appLocalizations;
    final profileId = ProfileIdProvider.of(context)!.profileId;
    return Consumer(
      builder: (_, ref, _) {
        final invalid = !ref.watch(
          customOverwriteUseIsValidProvider(profileId, use),
        );
        return _buildItem(
          invalid: invalid,
          title: appLocalizations.selectProxyProviders,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 2,
            children: [
              invalid
                  ? InfoMessageButton(
                      message: appLocalizations.proxyProviderDetectedAbnormal,
                    )
                  : (!includeAllProviders
                        ? _NumberCard(number: use.length)
                        : const _CheckIcon()),
              const Icon(Icons.arrow_forward_ios),
            ],
          ),
          onPressed: _handleToProvidersView,
        );
      },
    );
  }

  Widget _buildFilterItem(String? filter) {
    final appLocalizations = context.appLocalizations;
    return _buildItem(
      title: appLocalizations.proxyFilter,
      trailing: TextFormField(
        textAlign: TextAlign.end,
        initialValue: filter,
        inputFormatters: TextInputLimits.limit(TextInputLimits.filter),
        onChanged: (value) {
          ref
              .read(proxyGroupProvider.notifier)
              .update((state) => state.copyWith(filter: value));
        },
        decoration: InputDecoration.collapsed(
          border: const NoInputBorder(),
          hintText: appLocalizations.optional,
        ),
      ),
    );
  }

  Widget _buildMaxFailedTimesItem(int? maxFailedTimes) {
    final appLocalizations = context.appLocalizations;
    return _buildItem(
      title: appLocalizations.maxFailedTimes,
      trailing: TextFormField(
        keyboardType: TextInputType.number,
        inputFormatters: TextInputLimits.digitsOnly(TextInputLimits.number),
        textAlign: TextAlign.end,
        initialValue: maxFailedTimes?.toString(),
        onChanged: (value) {
          ref
              .read(proxyGroupProvider.notifier)
              .update(
                (state) => state.copyWith(maxFailedTimes: int.tryParse(value)),
              );
        },
        decoration: InputDecoration.collapsed(
          border: const NoInputBorder(),
          hintText: appLocalizations.optional,
        ),
      ),
    );
  }

  Widget _buildUrlItem(String? url) {
    final appLocalizations = context.appLocalizations;
    return _buildItem(
      title: appLocalizations.testUrl,
      trailing: TextFormField(
        keyboardType: TextInputType.url,
        inputFormatters: TextInputLimits.limit(TextInputLimits.url),
        textAlign: TextAlign.end,
        initialValue: url,
        onChanged: (value) {
          ref
              .read(proxyGroupProvider.notifier)
              .update((state) => state.copyWith(url: value));
        },
        decoration: InputDecoration.collapsed(
          border: const NoInputBorder(),
          hintText: appLocalizations.optional,
        ),
      ),
    );
  }

  Widget _buildIntervalItem(int? interval) {
    final appLocalizations = context.appLocalizations;
    return _buildItem(
      title: appLocalizations.testInterval,
      trailing: TextFormField(
        keyboardType: TextInputType.number,
        inputFormatters: TextInputLimits.digitsOnly(TextInputLimits.interval),
        textAlign: TextAlign.end,
        initialValue: interval?.toString(),
        onChanged: (value) {
          ref
              .read(proxyGroupProvider.notifier)
              .update((state) => state.copyWith(interval: int.tryParse(value)));
        },
        decoration: InputDecoration.collapsed(
          border: const NoInputBorder(),
          hintText: appLocalizations.optional,
        ),
      ),
    );
  }

  Widget _buildExcludeFilterItem(String? excludeFilter) {
    final appLocalizations = context.appLocalizations;
    return _buildItem(
      title: appLocalizations.excludeProxyFilter,
      trailing: TextFormField(
        textAlign: TextAlign.end,
        initialValue: excludeFilter,
        inputFormatters: TextInputLimits.limit(TextInputLimits.filter),
        onChanged: (value) {
          ref
              .read(proxyGroupProvider.notifier)
              .update((state) => state.copyWith(excludeFilter: value));
        },
        decoration: InputDecoration.collapsed(
          border: const NoInputBorder(),
          hintText: appLocalizations.optional,
        ),
      ),
    );
  }

  Widget _buildExcludeTypeItem(String? type) {
    final appLocalizations = context.appLocalizations;
    return _buildItem(
      title: appLocalizations.excludeType,
      trailing: TextFormField(
        textAlign: TextAlign.end,
        initialValue: type,
        inputFormatters: TextInputLimits.limit(TextInputLimits.name),
        onChanged: (value) {
          ref
              .read(proxyGroupProvider.notifier)
              .update((state) => state.copyWith(excludeType: value));
        },
        decoration: InputDecoration.collapsed(
          border: const NoInputBorder(),
          hintText: appLocalizations.optional,
        ),
      ),
    );
  }

  Widget _buildExpectedStatusItem(String? expectedStatus) {
    final appLocalizations = context.appLocalizations;
    return _buildItem(
      title: appLocalizations.expectedStatus,
      trailing: TextFormField(
        textAlign: TextAlign.end,
        initialValue: expectedStatus,
        inputFormatters: TextInputLimits.limit(TextInputLimits.status),
        onChanged: (value) {
          ref
              .read(proxyGroupProvider.notifier)
              .update((state) => state.copyWith(expectedStatus: value));
        },
        decoration: InputDecoration.collapsed(
          border: const NoInputBorder(),
          hintText: appLocalizations.optional,
        ),
      ),
    );
  }

  Widget _buildProxiesItem(bool includeAllProxies, List<String> proxies) {
    final appLocalizations = context.appLocalizations;
    final profileId = ProfileIdProvider.of(context)!.profileId;
    return Consumer(
      builder: (_, ref, _) {
        final invalid = !ref.watch(
          customOverwriteProxiesIsValidProvider(profileId, proxies),
        );
        return _buildItem(
          invalid: invalid,
          title: appLocalizations.selectProxies,
          trailing: Row(
            spacing: 2,
            mainAxisSize: MainAxisSize.min,
            children: [
              invalid
                  ? InfoMessageButton(
                      message: appLocalizations.proxyDetectedAbnormal,
                    )
                  : (!includeAllProxies
                        ? _NumberCard(number: proxies.length)
                        : const _CheckIcon()),
              const Icon(Icons.arrow_forward_ios),
            ],
          ),
          onPressed: _handleToProxiesView,
        );
      },
    );
  }

  Widget _buildTypeItem(GroupType type) {
    final appLocalizations = context.appLocalizations;
    return _buildItem(
      title: appLocalizations.proxyType,
      onPressed: () {
        _showTypeOptions(type);
      },
      trailing: Text(type.name),
    );
  }

  Widget _buildIconItem(String? icon) {
    final appLocalizations = context.appLocalizations;
    return _buildItem(
      title: appLocalizations.icon,
      onPressed: () {
        _showIconEdit(icon);
      },
      trailing: TooltipText(
        text: Text(
          icon?.value ?? appLocalizations.optional,
          maxLines: 1,
          style: context.textTheme.bodyLarge?.copyWith(
            color: icon == null ? context.colorScheme.onSurfaceVariant : null,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  Widget _buildNameItem(String name) {
    final appLocalizations = context.appLocalizations;
    return _buildItem(
      title: appLocalizations.name,
      trailing: TextFormField(
        initialValue: name,
        keyboardType: TextInputType.name,
        inputFormatters: TextInputLimits.limit(TextInputLimits.groupName),
        onChanged: (value) {
          ref
              .read(proxyGroupProvider.notifier)
              .update((state) => state.copyWith(name: value));
        },
        onFieldSubmitted: (_) {
          _handleSave();
        },
        textAlign: TextAlign.end,
        decoration: InputDecoration.collapsed(
          border: const NoInputBorder(),
          hintText: appLocalizations.inputProxyGroupName,
        ),
      ),
    );
  }

  Widget _buildHiddenItem(bool? hidden) {
    final appLocalizations = context.appLocalizations;
    void handleChangeHidden() {
      ref
          .read(proxyGroupProvider.notifier)
          .update((state) => state.copyWith(hidden: !(hidden ?? false)));
    }

    return _buildItem(
      title: appLocalizations.hideFromList,
      onPressed: handleChangeHidden,
      trailing: Switch(
        value: hidden ?? false,
        onChanged: (_) {
          handleChangeHidden();
        },
      ),
    );
  }

  Widget _buildLazyItem(bool? lazy) {
    final appLocalizations = context.appLocalizations;
    void handleChangeLazy() {
      ref
          .read(proxyGroupProvider.notifier)
          .update((state) => state.copyWith(lazy: !(lazy ?? false)));
    }

    return _buildItem(
      title: appLocalizations.testWhenUsed,
      onPressed: handleChangeLazy,
      trailing: Switch(
        value: lazy ?? false,
        onChanged: (_) {
          handleChangeLazy();
        },
      ),
    );
  }

  Widget _buildDisableUDPItem(bool? disableUDP) {
    final appLocalizations = context.appLocalizations;
    void handleChangeDisableUDP() {
      ref
          .read(proxyGroupProvider.notifier)
          .update(
            (state) => state.copyWith(disableUDP: !(disableUDP ?? false)),
          );
    }

    return _buildItem(
      title: appLocalizations.disableUDP,
      onPressed: handleChangeDisableUDP,
      trailing: Switch(
        value: disableUDP ?? false,
        onChanged: (_) {
          handleChangeDisableUDP();
        },
      ),
    );
  }

  Widget _field<S>(
    S Function(ProxyGroup state) selector,
    Widget Function(S value) builder,
  ) {
    return Consumer(
      builder: (_, ref, _) =>
          builder(ref.watch(proxyGroupProvider.select(selector))),
    );
  }

  Future<void> _handleDelete(int profileId) async {
    final res = await dialogs.showMessage(
      message: TextSpan(text: context.appLocalizations.confirmDeleteProxyGroup),
    );
    if (res == true && mounted) {
      final name = ref.read(proxyGroupProvider).name;
      ref.read(proxyGroupsProvider(profileId).notifier).del(name);
      context.safeNestedPop();
    }
  }

  Future<void> _handleSave() async {
    if (_handleSaveProxyGroup(context, ref)) {
      context.safeNestedPop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final profileId = ProfileIdProvider.of(context)!.profileId;
    final id = ref.watch(proxyGroupProvider.select((state) => state.id));
    final height = ref.sheetHeight(context, 0.65);
    return AdaptiveSheetScaffold(
      sheetTransparentToolBar: true,
      actions: [
        IconButtonData(
          icon: Icons.check,
          onPressed: _handleSave,
          tooltip: context.appLocalizations.save,
        ),
      ],
      body: SizedBox(
        height: height,
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
          ).copyWith(bottom: 20, top: context.sheetTopPadding),
          children: [
            generateSectionV3(
              title: appLocalizations.general,
              items: [
                _field((state) => state.name, _buildNameItem),
                _field((state) => state.type, _buildTypeItem),
                _field((state) => state.icon, _buildIconItem),
                _field((state) => state.hidden, _buildHiddenItem),
                _field((state) => state.disableUDP, _buildDisableUDPItem),
              ],
            ),
            generateSectionV3(
              title: appLocalizations.proxies,
              items: [
                _field(
                  (state) => (
                    state.includeAllProxies ?? false,
                    state.proxies ?? const <String>[],
                  ),
                  (value) => _buildProxiesItem(value.$1, value.$2),
                ),
                _field(
                  (state) => (
                    state.includeAllProviders ?? false,
                    state.use ?? const <String>[],
                  ),
                  (value) => _buildProvidersItem(value.$1, value.$2),
                ),
                _field((state) => state.filter, _buildFilterItem),
                _field((state) => state.excludeFilter, _buildExcludeFilterItem),
                _field((state) => state.excludeType, _buildExcludeTypeItem),
                _field(
                  (state) => state.expectedStatus,
                  _buildExpectedStatusItem,
                ),
              ],
            ),
            generateSectionV3(
              title: appLocalizations.other,
              items: [
                _field((state) => state.url, _buildUrlItem),
                _field(
                  (state) => state.maxFailedTimes,
                  _buildMaxFailedTimesItem,
                ),
                _field((state) => state.lazy, _buildLazyItem),
                _field((state) => state.interval, _buildIntervalItem),
              ],
            ),
            generateSectionV3(
              title: appLocalizations.action,
              items: [
                if (id != -1)
                  _buildItem(
                    title: appLocalizations.delete,
                    titleStyle: TextStyle(color: context.colorScheme.error),
                    onPressed: () {
                      _handleDelete(profileId);
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
      title: id == -1
          ? appLocalizations.addProxyGroup
          : appLocalizations.editProxyGroup,
    );
  }
}

class _CheckIcon extends StatelessWidget {
  const _CheckIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      child: Icon(
        Icons.check_circle_outline,
        size: 20.ap,
        color: Colors.greenAccent.harmonizeWith(context.colorScheme.primary),
      ),
    );
  }
}

class _NumberCard extends StatelessWidget {
  final int number;

  const _NumberCard({required this.number});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: AppShape.md,
      child: Container(
        constraints: const BoxConstraints(minWidth: 32),
        alignment: Alignment.center,
        height: globalState.measure.bodySmallHeight + 6,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Text(
          textAlign: TextAlign.center,
          '$number',
          style: context.textTheme.bodySmall,
        ),
      ),
    );
  }
}
