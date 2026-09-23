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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proxyNameText = _buildProxyNameText(context);
    return Stack(
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
                      // 第二行统一成「协议胶囊 + 测速按钮」一行 —— 三种卡片
                      // 类型都用同一套语言。展开卡片原来多占一整行放描述文字
                      // （`vless` / `Selector(香港01)`），那行现在并进胶囊里，
                      // 信息一点没少，只是不再单占一行。
                      SizedBox(
                        height: proxyCardMetaHeight,
                        child: Row(
                          children: [
                            Flexible(
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: type == ProxyCardType.expand
                                    ? _ProxyDescChip(proxy: proxy)
                                    : _ProxyTypeChip(label: proxy.type),
                              ),
                            ),
                            const SizedBox(width: 8),
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
    return Tooltip(
      message: value > 0 ? '$value ms' : 'Timeout',
      child: dot,
    );
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
