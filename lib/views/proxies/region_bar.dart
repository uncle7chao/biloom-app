import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'common.dart';

/// 筛选芯片的高度。
///
/// 比卡片上那排元信息胶囊（[proxyCardMetaHeight]）**高 8**：这里是**要点的**，
/// 比纯展示的标签大一圈才显得出来能点；顺带把点击区域做大了一点。
/// 横向内边距（10）比卡片胶囊（6）也宽，理由相同。
double get _chipHeight => proxyCardMetaHeight + 8;

/// 「代理」页页签底下那条**地区筛选栏**。
///
/// 它解决的是这一页最实际的麻烦：机场订阅给的节点动辄两三百个，名字又长
/// （`移动-HKG-443-WS-TLS`），想在「香港」里挑一个只能靠翻。这一栏把当前策略组
/// 的节点按**出口地区**归好，一次点选就把列表收窄到那个地区。
///
/// 三条设计取舍：
///
/// - **地区是从节点名现算的，不落盘、不进配置**。订阅一更新，这一栏跟着变，
///   不存在「分组过期」这回事；也绝不会因为分组引用了已经不存在的节点而让配置
///   加载失败。代价是它只在界面上「归组」，不改内核里真正生效的那份 `proxy-groups`。
/// - **筛选按页签分开记**（见 `proxyRegionFilterProvider`）：切到别的页签不会
///   把这一页的筛选带过去，也就不会切过去看到一片空白。
/// - **只有一类地区时不出现**：一条只有一个选项的筛选栏除了占地方没别的用。
///
/// 「认不出地区的节点」也有一颗「❔ 其他」芯片（排在最后）—— 实测 224 个真实节点里
/// 有 34 个纯域名名字给不出任何落地线索，它们照样得有个入口，不能被筛选栏吞掉。
///
/// ⛔ 别把这一栏做成「新建策略组」的入口。它的每一个动作都必须能被再一次点击
/// 撤销（「全部」就是那个撤销键），而写配置是不可撤销的。
class ProxyRegionFilterBar extends ConsumerWidget {
  /// 当前页签（策略组）名 —— 筛选状态的键。
  final String groupName;

  /// 当前页签里的节点。地区就是从这些名字里认出来的。
  final List<Proxy> proxies;

  const ProxyRegionFilterBar({
    super.key,
    required this.groupName,
    required this.proxies,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buckets = groupProxyNamesByRegion(proxies.map((proxy) => proxy.name));
    if (buckets.groups.length < 2) {
      return const SizedBox.shrink();
    }
    // 收敛一次：筛选键可能指向一个这批节点里已经没有的地区（例如订阅刚更新过），
    // 那种情况下按「不筛」显示 —— 与列表侧的判断必须用同一个函数，否则会出现
    // 「芯片上标着香港、列表却是全部」这种自相矛盾的状态。
    final selectedKey = resolveEffectiveRegionFilter(
      buckets: buckets,
      key: ref.watch(
        proxyRegionFilterProvider.select((state) => state[groupName]),
      ),
    );
    return Semantics(
      label: context.appLocalizations.proxyRegionFilter,
      container: true,
      child: SizedBox(
        height: _chipHeight + 8,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          children: [
            _RegionFilterChip(
              label: context.appLocalizations.proxyRegionAll,
              isSelected: selectedKey == null,
              onPressed: () => _select(ref, null),
            ),
            for (final group in buckets.groups)
              _RegionFilterChip(
                label: '${group.region.emoji} ${group.region.label}',
                isSelected: selectedKey == group.region.key,
                onPressed: () => _select(ref, group.region.key),
              ),
          ],
        ),
      ),
    );
  }

  void _select(WidgetRef ref, String? regionKey) {
    ref.read(proxyRegionFilterProvider.notifier).set(groupName, regionKey);
  }
}

/// 一颗筛选芯片。
///
/// 视觉与卡片上的元信息胶囊同源（同圆角、同 0.5 描边、同 `labelSmall` 字号），
/// 只有**选中态**不一样：选中的走 `secondaryContainer` 底 + `primary` 描边，
/// 与列表卡片「当前生效」的那套颜色是同一套 —— 不新增配色。
class _RegionFilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onPressed;

  const _RegionFilterChip({
    required this.label,
    required this.isSelected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      // 选中态不能只靠颜色说 —— 读屏的人看不到颜色。`Semantics.selected` 让
      // TalkBack / VoiceOver 把「已选中」念出来。
      child: Semantics(
        selected: isSelected,
        child: Material(
          color: isSelected
              ? colorScheme.secondaryContainer
              : colorScheme.surfaceContainerLow,
          borderRadius: AppRadius.xs,
          child: InkWell(
            onTap: onPressed,
            borderRadius: AppRadius.xs,
            child: Container(
              height: _chipHeight,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: AppRadius.xs,
                border: Border.all(
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.outlineVariant,
                  width: 0.5,
                ),
              ),
              child: EmojiText(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.labelSmall?.copyWith(
                  color: isSelected
                      ? colorScheme.onSecondaryContainer
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
