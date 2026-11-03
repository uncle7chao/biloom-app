import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'card.dart';
import 'common.dart';

/// 「当前出口」仪表卡（2026-09-30 代理页改版 A 档）。
///
/// 把「现在走的是谁」从节点网格里提出来，固定横在页签下方：不管用户翻到
/// 哪个页签（GLOBAL / 链式代理 / 地区组），第一眼先看到生效出口。数据源与
/// 节点卡片同一套 provider —— 选中语义仍然只有一份（生效选择器），这里
/// 只是把它放大展示，**不产生任何新的选中入口**。
///
/// - 出口判定与 `ProxyCard._effectiveChainSelectorName` 同款：规则模式看
///   [kPrimarySelectorGroupName]，全局模式看 GLOBAL；
/// - 选中的名字在组里找不到对应成员时（比如 GLOBAL 指向了已消失的组）
///   整卡隐藏，不显示半截信息；
/// - 延迟/落地沿用节点卡的按钮组件（已公开），测过的数据直接亮出来；
/// - 右侧测速按钮是整卡唯一的可点动作（tooltip 齐备），卡片本体不可点 ——
///   「看得出来能点」的入口只有这一个，不制造假按钮。
class ProxyExitDashboard extends ConsumerWidget {
  const ProxyExitDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(
      patchClashConfigProvider.select((state) => state.mode),
    );
    final selectorName = mode == Mode.global
        ? GroupName.GLOBAL.name
        : kPrimarySelectorGroupName;
    final group = ref.watch(
      groupsProvider.select((groups) => groups.getGroup(selectorName)),
    );
    if (group == null) {
      return const SizedBox.shrink();
    }
    final selectedName = ref
        .watch(selectedProxyNameProvider(group.name))
        .takeFirstValid([]);
    if (selectedName.isEmpty) {
      return const SizedBox.shrink();
    }
    Proxy? proxy;
    for (final item in group.all) {
      if (item.name == selectedName) {
        proxy = item;
        break;
      }
    }
    if (proxy == null) {
      return const SizedBox.shrink();
    }
    // 提升成 final 局部量：后面的 LayoutBuilder / onPressed 闭包要捕获它，
    // 非 final 变量在闭包里不会保持非空提升。
    final exitProxy = proxy;
    final region = ref.watch(proxyRegionProvider(exitProxy));
    final colorScheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: CommonCard(
        type: CommonCardType.filled,
        radius: AppCorner.xl,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          // ⛔ 这里不能用 `Row + CrossAxisAlignment.stretch`：本卡挂在页面的
          // Column 下，Column 给子项的是**无界高度**，stretch 会把子项约束
          // 成 h=Infinity 直接炸掉整页布局（release 下表现为代理页整页空白，
          // 01.00.29 实锤）。改用 Stack：高度由内容行（非 Positioned 子项）
          // 自然决定，竖条用 Positioned 上下贴满 —— 不依赖外部约束有界。
          child: Stack(
            children: [
              // 品牌色竖条：这张卡的「当前生效」标记，与选中节点卡的
              // primary 描边同一套语言。
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 18),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.appLocalizations.currentExit,
                            style: context.textTheme.labelSmall?.toLight,
                          ),
                          const SizedBox(height: 2),
                          EmojiText(
                            exitProxy.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          // 元信息行与节点卡第二行同一套胶囊语言：地区 + 协议在左，
                          // 测落地 / 测速两个按钮贴右。窄屏放不下时地区块自动让位。
                          SizedBox(
                            height: proxyCardMetaHeight,
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final isCompact = constraints.maxWidth < 300;
                                return Row(
                                  children: [
                                    Flexible(
                                      child: Align(
                                        alignment:
                                            AlignmentDirectional.centerStart,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (!region.isUnknown) ...[
                                              Flexible(
                                                child: ProxyRegionChip(
                                                  region: region,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                            ],
                                            Flexible(
                                              child: ProxyTypeChip(
                                                label: exitProxy.type,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (!isCompact) ...[
                                      ProxyExitButton(
                                        proxyName: exitProxy.name,
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                    ProxyDelayButton(
                                      proxyName: exitProxy.name,
                                      testUrl: group.testUrl,
                                      onTest: () {
                                        ref
                                            .read(proxiesActionProvider.notifier)
                                            .proxyDelayTest(
                                              exitProxy,
                                              group.testUrl,
                                            );
                                      },
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 整卡唯一的显式动作：重测当前出口的延迟。图标按钮带 tooltip。
                    IconButton(
                      tooltip: context.appLocalizations.delayTest,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(2),
                      iconSize: 20,
                      onPressed: () {
                        ref
                            .read(proxiesActionProvider.notifier)
                            .proxyDelayTest(exitProxy, group.testUrl);
                      },
                      icon: const Icon(Icons.network_ping),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
