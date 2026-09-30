import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'common.dart';

/// 「代理」页的一个节点卡片。
///
/// 视觉语言与「策略组」页的 `_ProxyGroupCard` 保持一致（同一套卡片底色 / 圆角 /
/// 中性胶囊 / 实测延迟配色），只保留三条规矩：
///
/// - 左侧状态点是**实测延迟**（`getDelayColor`）：实心有色 = 测过，空心灰 = 没测过。
///   用户在这一页真正想知道的就一件事 —— 哪个节点现在通；
/// - 协议类型是中性胶囊，不与「当前在用」抢视线；
/// - 右下角那个延迟区域是**按钮**，不是标签。这里踩过坑：改版前有延迟时它只是
///   一行 `87 ms` 纯文字，既没有图标也没有描边，用户据此认为「单节点测速功能丢了」。
///   功能一直在（`proxyDelayTest`），缺的是「看得出来能点」。
class ProxyCard extends ConsumerWidget {
  final String groupName;
  final Proxy proxy;
  final GroupType groupType;
  final ProxyCardType type;
  final String? testUrl;

  const ProxyCard({
    super.key,
    required this.groupName,
    required this.testUrl,
    required this.proxy,
    required this.groupType,
    required this.type,
  });

  Measure get measure => globalState.measure;

  void _handleTestCurrentDelay(WidgetRef ref) {
    ref.read(proxiesActionProvider.notifier).proxyDelayTest(proxy, testUrl);
  }

  Widget _buildProxyNameText(BuildContext context) {
    final maxLines = type == ProxyCardType.min ? 1 : 2;
    return SizedBox(
      height: measure.bodyMediumHeight * maxLines,
      child: EmojiText(
        proxy.name,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: context.textTheme.bodyMedium,
      ),
    );
  }

  Future<void> _changeProxy(WidgetRef ref, String selectionSource) async {
    final isComputedSelected = groupType.isComputedSelected;
    final isSelector = groupType == GroupType.Selector;
    if (isComputedSelected || isSelector) {
      final currentProxyName = ref.read(proxyNameProvider(selectionSource));
      final nextProxyName = switch (isComputedSelected) {
        true => currentProxyName == proxy.name ? '' : proxy.name,
        false => proxy.name,
      };
      ref
          .read(proxiesActionProvider.notifier)
          .changeProxyDebounce(selectionSource, nextProxyName);
      return;
    }
    dialogs.showNotifier(
      currentAppLocalizations.notSelectedTip,
      level: MessageLevel.warning,
    );
  }

  /// 「链式代理」组是管理视图，它自己的选中记录不产生流量效果 —— 真正的
  /// 出口选择在 [kPrimarySelectorGroupName]（规则模式）或 GLOBAL（全局模式）。
  /// 链卡片的选中态与点击都改道到那个生效选择器，保证全应用「选中 = 生效」
  /// 只有一份：链被主选择器选中时这里亮 + 打勾，普通节点被选中时链不亮。
  /// 返回 null = 不是链卡片（或空链的 DIRECT 占位、生效选择器不存在），
  /// 按普通组行为处理。
  String? _effectiveChainSelectorName(WidgetRef ref) {
    if (groupName != kProxyChainGroupName || proxy.name == 'DIRECT') {
      return null;
    }
    final mode = ref.watch(
      patchClashConfigProvider.select((state) => state.mode),
    );
    final candidate = mode == Mode.global
        ? GroupName.GLOBAL.name
        : kPrimarySelectorGroupName;
    final exists = ref.watch(
      groupsProvider.select(
        (groups) => groups.any((group) => group.name == candidate),
      ),
    );
    return exists ? candidate : null;
  }

  Future<void> _handleDelete(BuildContext context, WidgetRef ref) async {
    final profile = ref.read(currentProfileProvider);
    if (profile == null) {
      return;
    }
    final appLocalizations = context.appLocalizations;
    // 订阅配置删了也会被下一次「更新订阅」整份盖回来 —— 确认弹窗里先说清楚，
    // 与「管理节点」面板顶部的提示同一句话。
    final isSubscription = profile.url.isNotEmpty;
    final confirmed = await dialogs.showMessage(
      message: TextSpan(
        text: [
          proxy.name,
          if (isSubscription) '\n${appLocalizations.subscribeOverwriteWarning}',
          '\n${appLocalizations.deleteNodeConfirm}',
        ].join(),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final result = await ref
        .read(profilesActionProvider.notifier)
        .removeProxyNodesFromProfile(
          profileId: profile.id,
          names: [proxy.name],
        );
    if (result == null || !context.mounted) return;
    context.showNotifier(
      result.missing.isNotEmpty
          ? appLocalizations.deleteNodeMissing
          : appLocalizations.deleteNodeSuccess,
      level: result.missing.isEmpty
          ? MessageLevel.success
          : MessageLevel.warning,
    );
  }

  /// 节点卡片的右键/长按菜单：收藏、测速、测落地、删除。
  ///
  /// 配置卡片一直有「⋯」菜单，节点卡片此前什么都没有 —— 删除做完之后入口却
  /// 只有「配置卡片 → 管理节点」一条路，对着要删的卡片反而没有动作。这里补上
  /// 与配置卡片同一套 [CommonPopupMenu]，桌面右键、移动端长按都能唤出。
  List<CommonPopupMenuItem> _buildMenuItems(
    BuildContext context,
    WidgetRef ref, {
    required bool isFavorite,
  }) {
    final appLocalizations = context.appLocalizations;
    return [
      CommonPopupMenuItem(
        icon: isFavorite ? Icons.star : Icons.star_border,
        label: isFavorite
            ? appLocalizations.unfavoriteNode
            : appLocalizations.favoriteNode,
        onPressed: () {
          final profile = ref.read(currentProfileProvider);
          if (profile == null) return;
          ref
              .read(proxyFavoritesProvider.notifier)
              .toggle(profile.id, proxy.name);
        },
      ),
      CommonPopupMenuItem(
        icon: Icons.bolt,
        label: appLocalizations.proxyDelayTestNow,
        onPressed: () => _handleTestCurrentDelay(ref),
      ),
      CommonPopupMenuItem(
        icon: Icons.travel_explore,
        label: appLocalizations.proxyExitTest,
        onPressed: () {
          ref.read(proxyExitProvider.notifier).test(proxy.name);
        },
      ),
      CommonPopupMenuItem(
        danger: true,
        icon: Icons.delete_outline,
        label: appLocalizations.deleteNode,
        onPressed: () => _handleDelete(context, ref),
      ),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proxyNameText = _buildProxyNameText(context);
    final region = ref.watch(proxyRegionProvider(proxy));
    // 链卡片（链式代理页签）的选中语义挂在生效选择器上，其余卡片用自己组。
    final selectionSource = _effectiveChainSelectorName(ref) ?? groupName;
    final profileId = ref.watch(currentProfileIdProvider);
    final isFavorite =
        profileId != null &&
        (ref.watch(
              proxyFavoritesProvider.select(
                (value) =>
                    value.value?[profileId.toString()]?.contains(proxy.name),
              ),
            ) ??
            false);
    return CommonPopupBox(
      popupBuilder: (_) => CommonPopupMenu(
        items: _buildMenuItems(context, ref, isFavorite: isFavorite),
      ),
      targetBuilder: (open) => GestureDetector(
        // offset 用指针落点：菜单锚定在右键位置附近，而不是整张卡片的角上。
        onSecondaryTapUp: (details) => open(offset: details.localPosition),
        onLongPressStart: (details) => open(offset: details.localPosition),
        child: Stack(
          children: [
            // 收藏角标：小星标钉在左上角（右上角是「计算选中」标记的位置）。
            // 只是叠一层图标，不占行高 —— 高度由 getItemHeight 统一管。
            if (isFavorite)
              Positioned(
                top: 1,
                left: 2,
                child: Icon(
                  Icons.star,
                  size: 14,
                  // 收藏星用琥珀色：灰色星和状态点/胶囊挤在一起几乎看不见，
                  // 功能色在延迟色环里本来就有（绿黄红），琥珀是它的自然延伸。
                  color: Colors.amber.shade400,
                ),
              ),
            Consumer(
              builder: (_, ref, child) {
                final selectedProxyName = ref.watch(
                  selectedProxyNameProvider(selectionSource),
                );
                return CommonCard(
                  type: CommonCardType.filled,
                  radius: AppCorner.lg,
                  key: key,
                  highlightSelected: true,
                  onPressed: () {
                    _changeProxy(ref, selectionSource);
                  },
                  isSelected: selectedProxyName == proxy.name,
                  child: child!,
                );
              },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              // stretch 让左侧延迟色条自动长到与内容列同高（名称 + 第二行），
              // 不用自己算高度 —— 也就不用碰 getItemHeight。
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ProxyDelayBar(proxyName: proxy.name, testUrl: testUrl),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          proxyNameText,
                          const SizedBox(height: 6),
                          // 第二行统一成「地区胶囊 + 协议胶囊 … 测速按钮」一行 —— 三种
                          // 卡片类型都用同一套语言。展开卡片原来多占一整行放描述文字
                          // （`vless` / `Selector(香港01)`），那行现在并进胶囊里，
                          // 信息一点没少，只是不再单占一行。
                          SizedBox(
                            height: proxyCardMetaHeight,
                            // 窄卡降级：行宽不足时「测落地」只留图标，语义靠
                            // tooltip 和警示色兜底，入口不丢。
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final isCompact = constraints.maxWidth < 240;
                                return Row(
                                  children: [
                                    // 左边这一块（地区 + 协议）共用一层 `Align`：它负责把
                                    // 整块顶到行首，同时把右侧剩余空间吃掉 —— 右下角的
                                    // 测速按钮才能贴住卡片右边（`Row` 不会自动把最后一
                                    // 个子项推到行尾）。
                                    Flexible(
                                      child: Align(
                                        alignment:
                                            AlignmentDirectional.centerStart,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // 地区认不出就整块跳过。这里用 collection-if
                                            // 而不是让胶囊自己返回空盒子 —— 后者会把后面
                                            // 那 6px 间距留在行里。
                                            if (!region.isUnknown) ...[
                                              Flexible(
                                                child: ProxyRegionChip(
                                                  region: region,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                            ],
                                            Flexible(
                                              child:
                                                  type == ProxyCardType.expand
                                                  ? _ProxyDescChip(proxy: proxy)
                                                  : ProxyTypeChip(
                                                      label: proxy.type,
                                                    ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ProxyExitButton(
                                      proxyName: proxy.name,
                                      compact: isCompact,
                                    ),
                                    const SizedBox(width: 6),
                                    ProxyDelayButton(
                                      proxyName: proxy.name,
                                      testUrl: testUrl,
                                      onTest: () =>
                                          _handleTestCurrentDelay(ref),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 选中标记：卡片右上角打勾。**所有组类型都显示** —— 用户反馈
            // 「之前选中节点卡片右上角有打勾，现在没了」：select 组选中此前只有
            // 底色/描边变化，深色主题下几乎认不出，用户据此以为选中没生效
            // （链式代理「无法使用」的误报正源于此）。computed 组（URLTest/
            // Fallback）保持上游原语义 —— 勾标记的是计算出的实际出口；select
            // 组标记的是用户选中的节点。名字不匹配时组件自己返回空盒子。
            Positioned(
              top: 0,
              right: 0,
              child: _ProxyComputedMark(
                groupName: selectionSource,
                proxy: proxy,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 卡片左侧的延迟色条：实心有色 = 这个节点测过速，颜色即 `getDelayColor`；
/// 中性灰 = 还没测过。**不猜颜色** —— 没测就画灰条，不假装它通。
///
/// 前身是 8px 状态点（2026-09-30 改版 B 档换竖条）：点是零散的装饰，条是
/// 卡片自己的视觉骨架 —— 扫一列卡片时色条连成一条「延迟图谱」，通不通一眼
/// 扫出来。外层 Row 用 stretch，条高自动等于内容列高，`getItemHeight` 不受影响。
class _ProxyDelayBar extends ConsumerWidget {
  static const double _width = 3;

  final String proxyName;
  final String? testUrl;

  const _ProxyDelayBar({required this.proxyName, this.testUrl});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(
      delayProvider(proxyName: proxyName, testUrl: testUrl),
    );
    final color =
        getDelayColor(value) ?? context.colorScheme.outlineVariant;
    final bar = Container(
      width: _width,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(_width / 2),
      ),
    );
    if (value == null) {
      return bar;
    }
    return Tooltip(message: value > 0 ? '$value ms' : 'Timeout', child: bar);
  }
}

/// 协议类型胶囊。中性色 + 一档浅底 + 一圈描边 —— 与策略组页的类型徽章同一套。
class ProxyTypeChip extends StatelessWidget {
  final String label;

  const ProxyTypeChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.xs,
        border: Border.all(color: colorScheme.outlineVariant, width: 0.5),
      ),
      child: EmojiText(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 节点所属地区的胶囊（`🇭🇰 中国香港` / `🇺🇸 美国` / `☁️ CF 中转`）。
///
/// 外观刻意与协议胶囊**完全同一套**（同一档浅底 + 同一圈描边 + 同一个圆角）：
/// 两个胶囊是「这一行里的两段中性信息」，不该有一个跳出来抢视线。区分度靠名字
/// 前缀的国旗 emoji —— 一眼扫过去先认旗、再认字，不用读文字。
///
/// 认不出地区的节点由调用方整块跳过（`ProxyRegionKind.unknown`），这里不做兜底：
/// 一个写着「其他」的胶囊对挑节点毫无帮助，只是噪音。
///
/// ⛔ 高度必须继续走 `proxyCardMetaHeight`（就是 [ProxyTypeChip] 自身的高度）——
/// `getItemHeight` 是按那个数字算的，这里要是自己有内边距，实机立刻
/// 「A RenderFlex overflowed」。
class ProxyRegionChip extends StatelessWidget {
  final ProxyRegion region;

  const ProxyRegionChip({required this.region});

  @override
  Widget build(BuildContext context) {
    return ProxyTypeChip(label: '${region.emoji} ${region.label}');
  }
}

/// 单个节点的测速按钮。
///
/// 三种状态都有明确外观，且**始终可点**：
/// - 没测过：`⚡ 测速`（未测时也把入口画出来，而不是只剩一个没头没脑的闪电图标）；
/// - 测速中：圆圈加载，此时禁用点击，避免重复请求；
/// - 有结果：`⚡ 87 ms` / `⚡ Timeout`，颜色走 `getDelayColor`，点一下重测。
///
/// 外层的 `Tooltip` 是给鼠标/读屏用的：这个控件不是 `IconButton`，所以
/// `icon_button_tooltip_test` 覆盖不到它，得自己带上说明。
class ProxyDelayButton extends ConsumerWidget {
  final String proxyName;
  final String? testUrl;
  final VoidCallback onTest;

  const ProxyDelayButton({
    required this.proxyName,
    required this.onTest,
    this.testUrl,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final colorScheme = context.colorScheme;
    final delay = ref.watch(
      delayProvider(proxyName: proxyName, testUrl: testUrl),
    );
    final pending = ref.watch(
      delayTestPendingProvider(proxyName: proxyName, testUrl: testUrl),
    );
    final color = getDelayColor(delay) ?? colorScheme.onSurfaceVariant;
    final label = switch (delay) {
      null => appLocalizations.proxyDelayTestNow,
      final value when value > 0 => '$value ms',
      _ => 'Timeout',
    };
    return Tooltip(
      message: appLocalizations.proxyDelayTestHint,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: pending ? null : onTest,
          borderRadius: AppRadius.xs,
          child: Container(
            height: proxyCardMetaHeight,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: AppRadius.xs,
              border: Border.all(
                color: pending
                    ? colorScheme.primary
                    : colorScheme.outlineVariant,
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (pending)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CommonCircleLoading(),
                  )
                else
                  Icon(Icons.bolt, size: 12, color: color),
                const SizedBox(width: 4),
                Text(
                  label,
                  maxLines: 1,
                  style: context.textTheme.labelSmall?.copyWith(color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 单个节点的「测落地」按钮。
///
/// 名字里的地区是机场随手写的（实测本订阅 `US-*` 落在吉隆坡、`SG-*` 落在
/// 马尼拉），要知道真实落地只有把请求从节点里发出去看出口 IP。与
/// [ProxyDelayButton] 同一套语言：没测过显示「测落地」带文字入口，测完
/// 显示 `→ 🇲🇾`；**实测地区与名字标注不一致时整颗按钮变警示色** —— 这正是
/// 用户点它的理由，不一致不该藏进 tooltip 里。
///
/// 结果两层：本次会话测的（含失败 —— 失败是「刚才测不出」，不能被旧记录盖住）
/// 优先；会话里没有就回退到落库的那份（[ProxyExitStore]，批量测落地写进去的）。
/// 所以重进页面、重启应用之后，测过的节点依然显示 `→ 🇲🇾` 而不是回到入口态。
/// 不一致的比较对象始终是**名字认出的地区** —— 卡片标签本身已跟随落地，
/// 拿标签比就永远一致，警示就永远不亮了。
class ProxyExitButton extends ConsumerWidget {
  final String proxyName;

  /// 窄卡模式：只显示图标，不显示文字标签。测试中仍显示转圈，
  /// 失败/不一致的警示色不变 —— 语义由 tooltip 兜底。
  final bool compact;

  const ProxyExitButton({required this.proxyName, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final colorScheme = context.colorScheme;
    final isTesting = ref.watch(
      proxyExitProvider.select((state) => state.testing.contains(proxyName)),
    );
    // 会话里测过（含失败）就用会话的，否则回退落库记录。
    final hasSessionResult = ref.watch(
      proxyExitProvider.select((state) => state.results.containsKey(proxyName)),
    );
    final sessionResult = hasSessionResult
        ? ref.watch(
            proxyExitProvider.select((state) => state.results[proxyName]),
          )
        : null;
    final storedResult = ref.watch(
      proxyExitStoreProvider.select((state) => state.value?[proxyName]),
    );
    final result = hasSessionResult ? sessionResult : storedResult;
    // 只在「名字标了国家」时才判不一致：CF 中转没有可对照的地区，认不出
    // 更没有 —— 拿它们比只会永远显示警示色，把真问题淹没。
    final nameRegion = resolveProxyRegion(proxyName);
    final mismatch =
        result != null &&
        nameRegion.isCountry &&
        result.countryCode.isNotEmpty &&
        result.countryCode != nameRegion.code;
    final color = mismatch ? colorScheme.error : colorScheme.onSurfaceVariant;

    final String label;
    if (isTesting) {
      label = appLocalizations.proxyExitTest;
    } else if (result == null) {
      label = appLocalizations.proxyExitTest;
    } else if (result.countryCode.isEmpty) {
      label = appLocalizations.proxyExitFailed;
    } else {
      label = '→ ${countryCodeToEmoji(result.countryCode)}';
    }

    final tooltipMessage = switch ((isTesting, result)) {
      (true, _) => appLocalizations.proxyExitTestHint,
      (false, null) => appLocalizations.proxyExitTestHint,
      (false, ProxyExitInfo(countryCode: '', ip: _)) =>
        appLocalizations.proxyExitFailed,
      (false, ProxyExitInfo(countryCode: final code, ip: final ip)) =>
        '${countryCodeToEmoji(code)} '
            '${localizedRegionName(code, Localizations.localeOf(context).languageCode) ?? code}'
            ' · $ip'
            '${mismatch ? '\n${appLocalizations.proxyExitMismatch}' : ''}',
    };

    return Tooltip(
      message: tooltipMessage,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isTesting
              ? null
              : () => ref.read(proxyExitProvider.notifier).test(proxyName),
          borderRadius: AppRadius.xs,
          child: Container(
            height: proxyCardMetaHeight,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: AppRadius.xs,
              border: Border.all(
                color: mismatch
                    ? colorScheme.error
                    : isTesting
                    ? colorScheme.primary
                    : colorScheme.outlineVariant,
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isTesting)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CommonCircleLoading(),
                  )
                else
                  Icon(Icons.travel_explore, size: 12, color: color),
                if (!compact) ...[
                  const SizedBox(width: 4),
                  EmojiText(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.labelSmall?.copyWith(color: color),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 展开卡片的协议胶囊：标签用 `proxyDesc` —— 对普通节点就是协议名（`vless`），
/// 对策略组成员是 `Selector(香港01)` 这种带子节点的形式。所以它比 `proxy.type`
/// 多带一层信息，但仍旧用一个中性胶囊装下，不额外占行。
class _ProxyDescChip extends ConsumerWidget {
  final Proxy proxy;

  const _ProxyDescChip({required this.proxy});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ProxyTypeChip(label: ref.watch(proxyDescProvider(proxy)));
  }
}

class _ProxyComputedMark extends ConsumerWidget {
  final String groupName;
  final Proxy proxy;

  const _ProxyComputedMark({required this.groupName, required this.proxy});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // selectedProxyName = 用户选中（selectedMap），没点过时回退内核上报的
    // 组当前实际选中（now）—— 进页面就能看到「当前生效」的勾，不用先点一次。
    final proxyName = ref.watch(selectedProxyNameProvider(groupName));
    if (proxyName != proxy.name) {
      return const SizedBox();
    }
    return Container(
      alignment: Alignment.topRight,
      margin: const EdgeInsets.all(8),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // 选中勾走品牌色实心圆（2026-09-30 改版 B 档）：原来的
          // secondaryContainer 底 + inversePrimary 勾在深色主题下对比太弱，
          // 「选中了没有」要一眼可辨 —— 选中语言统一到 primary 上。
          color: Theme.of(context).colorScheme.primary,
        ),
        child: Icon(
          Icons.check,
          size: 14,
          color: Theme.of(context).colorScheme.onPrimary,
        ),
      ),
    );
  }
}
