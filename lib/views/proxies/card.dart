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

  Future<void> _changeProxy(WidgetRef ref) async {
    final isComputedSelected = groupType.isComputedSelected;
    final isSelector = groupType == GroupType.Selector;
    if (isComputedSelected || isSelector) {
      final currentProxyName = ref.read(proxyNameProvider(groupName));
      final nextProxyName = switch (isComputedSelected) {
        true => currentProxyName == proxy.name ? '' : proxy.name,
        false => proxy.name,
      };
      ref
          .read(proxiesActionProvider.notifier)
          .changeProxyDebounce(groupName, nextProxyName);
      return;
    }
    dialogs.showNotifier(
      currentAppLocalizations.notSelectedTip,
      level: MessageLevel.warning,
    );
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
        .removeProxyNodesFromProfile(profileId: profile.id, names: [proxy.name]);
    if (result == null || !context.mounted) return;
    context.showNotifier(
      result.missing.isNotEmpty
          ? appLocalizations.deleteNodeMissing
          : appLocalizations.deleteNodeSuccess,
      level: result.missing.isEmpty ? MessageLevel.success : MessageLevel.warning,
    );
  }

  /// 节点卡片的右键/长按菜单：测速、测落地、删除。
  ///
  /// 配置卡片一直有「⋯」菜单，节点卡片此前什么都没有 —— 删除做完之后入口却
  /// 只有「配置卡片 → 管理节点」一条路，对着要删的卡片反而没有动作。这里补上
  /// 与配置卡片同一套 [CommonPopupMenu]，桌面右键、移动端长按都能唤出。
  List<CommonPopupMenuItem> _buildMenuItems(
    BuildContext context,
    WidgetRef ref,
  ) {
    final appLocalizations = context.appLocalizations;
    return [
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
    return CommonPopupBox(
      popupBuilder: (_) => CommonPopupMenu(
        items: _buildMenuItems(context, ref),
      ),
      targetBuilder: (open) => GestureDetector(
        // offset 用指针落点：菜单锚定在右键位置附近，而不是整张卡片的角上。
        onSecondaryTapUp: (details) => open(offset: details.localPosition),
        onLongPressStart: (details) => open(offset: details.localPosition),
        child: Stack(
          children: [
            Consumer(
              builder: (_, ref, child) {
                final selectedProxyName = ref.watch(
                  selectedProxyNameProvider(groupName),
                );
                return CommonCard(
                  type: CommonCardType.filled,
                  radius: AppCorner.lg,
                  key: key,
                  onPressed: () {
                    _changeProxy(ref);
                  },
                  isSelected: selectedProxyName == proxy.name,
                  child: child!,
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    _ProxyStatusDot(proxyName: proxy.name, testUrl: testUrl),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
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
                            child: Row(
                              children: [
                                // 左边这一块（地区 + 协议）共用一层 `Align`：它负责把
                                // 整块顶到行首，同时把右侧剩余空间吃掉 —— 右下角的
                                // 测速按钮才能贴住卡片右边（`Row` 不会自动把最后一
                                // 个子项推到行尾）。
                                Flexible(
                                  child: Align(
                                    alignment: AlignmentDirectional.centerStart,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // 地区认不出就整块跳过。这里用 collection-if
                                        // 而不是让胶囊自己返回空盒子 —— 后者会把后面
                                        // 那 6px 间距留在行里。
                                        if (!region.isUnknown) ...[
                                          Flexible(
                                            child: _ProxyRegionChip(
                                              region: region,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                        Flexible(
                                          child: type == ProxyCardType.expand
                                              ? _ProxyDescChip(proxy: proxy)
                                              : _ProxyTypeChip(
                                                  label: proxy.type,
                                                ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _ProxyExitButton(
                                  proxyName: proxy.name,
                                ),
                                const SizedBox(width: 6),
                                _ProxyDelayButton(
                                  proxyName: proxy.name,
                                  testUrl: testUrl,
                                  onTest: () => _handleTestCurrentDelay(ref),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (groupType.isComputedSelected)
              Positioned(
                top: 0,
                right: 0,
                child: _ProxyComputedMark(groupName: groupName, proxy: proxy),
              ),
          ],
        ),
      ),
    );
  }
}

/// 卡片左侧的状态点：实心有色 = 这个节点测过速，颜色即 `getDelayColor`；
/// 空心灰 = 还没测过。**不猜颜色** —— 没测就画空心，不假装它通。
class _ProxyStatusDot extends ConsumerWidget {
  static const double _size = 8;

  final String proxyName;
  final String? testUrl;

  const _ProxyStatusDot({required this.proxyName, this.testUrl});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(
      delayProvider(proxyName: proxyName, testUrl: testUrl),
    );
    final color = getDelayColor(value);
    final dot = Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: color == null
            ? Border.all(
                color: context.colorScheme.onSurfaceVariant.opacity38,
                width: 1.5,
              )
            : null,
      ),
    );
    if (value == null) {
      return dot;
    }
    return Tooltip(message: value > 0 ? '$value ms' : 'Timeout', child: dot);
  }
}

/// 协议类型胶囊。中性色 + 一档浅底 + 一圈描边 —— 与策略组页的类型徽章同一套。
class _ProxyTypeChip extends StatelessWidget {
  final String label;

  const _ProxyTypeChip({required this.label});

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
/// ⛔ 高度必须继续走 `proxyCardMetaHeight`（就是 [_ProxyTypeChip] 自身的高度）——
/// `getItemHeight` 是按那个数字算的，这里要是自己有内边距，实机立刻
/// 「A RenderFlex overflowed」。
class _ProxyRegionChip extends StatelessWidget {
  final ProxyRegion region;

  const _ProxyRegionChip({required this.region});

  @override
  Widget build(BuildContext context) {
    return _ProxyTypeChip(label: '${region.emoji} ${region.label}');
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
class _ProxyDelayButton extends ConsumerWidget {
  final String proxyName;
  final String? testUrl;
  final VoidCallback onTest;

  const _ProxyDelayButton({
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
/// [_ProxyDelayButton] 同一套语言：没测过显示「测落地」带文字入口，测完
/// 显示 `→ 🇲🇾`；**实测地区与名字标注不一致时整颗按钮变警示色** —— 这正是
/// 用户点它的理由，不一致不该藏进 tooltip 里。
///
/// 结果两层：本次会话测的（含失败 —— 失败是「刚才测不出」，不能被旧记录盖住）
/// 优先；会话里没有就回退到落库的那份（[ProxyExitStore]，批量测落地写进去的）。
/// 所以重进页面、重启应用之后，测过的节点依然显示 `→ 🇲🇾` 而不是回到入口态。
/// 不一致的比较对象始终是**名字认出的地区** —— 卡片标签本身已跟随落地，
/// 拿标签比就永远一致，警示就永远不亮了。
class _ProxyExitButton extends ConsumerWidget {
  final String proxyName;

  const _ProxyExitButton({required this.proxyName});

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
                const SizedBox(width: 4),
                EmojiText(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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

/// 展开卡片的协议胶囊：标签用 `proxyDesc` —— 对普通节点就是协议名（`vless`），
/// 对策略组成员是 `Selector(香港01)` 这种带子节点的形式。所以它比 `proxy.type`
/// 多带一层信息，但仍旧用一个中性胶囊装下，不额外占行。
class _ProxyDescChip extends ConsumerWidget {
  final Proxy proxy;

  const _ProxyDescChip({required this.proxy});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _ProxyTypeChip(label: ref.watch(proxyDescProvider(proxy)));
  }
}

class _ProxyComputedMark extends ConsumerWidget {
  final String groupName;
  final Proxy proxy;

  const _ProxyComputedMark({required this.groupName, required this.proxy});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proxyName = ref.watch(proxyNameProvider(groupName));
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
          color: Theme.of(context).colorScheme.secondaryContainer,
        ),
        child: const SelectIcon(),
      ),
    );
  }
}
