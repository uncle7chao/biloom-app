import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/dashboard/widgets/start_button.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 首页顶部的**三态主卡**：未连接 / 连接中 / 已连接。
///
/// 它不做任何新事情 —— 点击就是和悬浮球同一个 [CommonAction.toggleRunning]，
/// 这里只是把「连接是件大事」这件事实放到首页第一眼能看到的位置：以前用户
/// 要从悬浮球的形状、代理页的开关里猜自己连没连上；现在一张卡说清楚。
///
/// 视觉跟着设计系统走：已连接 = `filled + selected`（secondaryContainer，
/// 与「当前生效」在其他页面的表达一致）+ 品牌色提亮的浅绿指示；未连接 =
/// 普通卡面 + 状态红指示。连接中不可点 —— 连接动作本身已经在飞，再点
/// 一次只会叠加请求。
/// 状态指示色（2026-10-10 用户拍板）：已连接 = 浅绿、未连接 = 红。
/// 浅绿由品牌种子色提亮派生（不引入第二套色板）；红与节点延迟测试的
/// 状态红同族（redAccent），在深色卡面上清晰可辨且不刺眼。
/// 「点按一键连接」只在有配置时显示：裸机（无订阅）状态点了只会弹
/// 「请先添加配置文件」，喊人连接是条死路（2026-10-10 用户拍板去掉）。
const _disconnectedColor = Color(0xFFFF5252);

class ConnectionHero extends ConsumerWidget {
  const ConnectionHero({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = ref.watch(connectionPhaseProvider);
    final appLocalizations = context.appLocalizations;
    final textTheme = context.textTheme;

    final Widget leading;
    final String title;
    final String? subtitle;
    Color? stateColor;
    // 刚安装还没有任何配置时，「点按一键连接」是条死路 —— 点下去只会弹
    // 「请先添加配置文件」。所以裸机状态不喊人连接（2026-10-10 用户拍板），
    // 等有了订阅这条引导才有意义。
    final hasProfile = ref.watch(
      profilesProvider.select((state) => state.isNotEmpty),
    );
    switch (phase) {
      case ConnectionPhase.connected:
        // ⚠️ 不要用 lighten()：它是 HSL 亮度直接 +amount%，深色主题的
        // primary（tone 80）亮度已高，+30% 会顶到纯白（01.00.37 翻车：
        // 图标标题全变白）。RGB 向白混 20% 才是「更浅但仍是绿」。
        stateColor = Color.lerp(
          context.colorScheme.primary,
          Colors.white,
          0.2,
        );
        leading = Icon(
          Icons.check_circle,
          color: stateColor,
          size: 28.ap,
        );
        title = appLocalizations.connectionStateConnected;
        subtitle = appLocalizations.connectionHeroTapToDisconnect;
      case ConnectionPhase.connecting:
        leading = SizedBox(
          width: 28.ap,
          height: 28.ap,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        );
        title = appLocalizations.connectionStateConnecting;
        subtitle = appLocalizations.connectionHeroTapToDisconnect;
      case ConnectionPhase.disconnected:
        stateColor = _disconnectedColor;
        leading = Icon(
          Icons.power_settings_new,
          color: stateColor,
          size: 28.ap,
        );
        title = appLocalizations.connectionStateDisconnected;
        subtitle = hasProfile
            ? appLocalizations.connectionHeroTapToConnect
            : null;
    }

    return CommonCard(
      type: phase == ConnectionPhase.connected
          ? CommonCardType.filled
          : CommonCardType.plain,
      isSelected: phase == ConnectionPhase.connected,
      radius: AppCorner.xl,
      // 连接中再点是无意义的叠加请求；其余两态点击 = 悬浮球的同一动作。
      onPressed: phase == ConnectionPhase.connecting
          ? null
          : () => ref.read(commonActionProvider.notifier).toggleRunning(),
      child: SizedBox(
        height: 84,
        // 渐变底只属于「已连接」态：从左侧品牌色 15% 渐到透明，让第一眼的
        // 状态判断不依赖读字。裁剪层与卡片同圆角，渐变不会溢出圆角外。
        child: ClipRSuperellipse(
          borderRadius: AppRadius.xl,
          child: Stack(
            children: [
              if (phase == ConnectionPhase.connected)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: AlignmentDirectional.centerStart,
                        end: AlignmentDirectional.centerEnd,
                        colors: [
                          context.colorScheme.primary.opacity15,
                          context.colorScheme.primary.opacity0,
                        ],
                      ),
                    ),
                  ),
                ),
              Positioned.fill(
                child: Row(
                  children: [
                    const SizedBox(width: 20),
                    leading,
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleMedium?.toSoftBold.copyWith(
                              color: stateColor,
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodyMedium?.copyWith(
                                color: context.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // 已连接时把运行时长直接亮出来 —— 用户关心的下一个问题
                    // 就是「连了多久了」，别让他再去悬浮球那里找。
                    if (phase == ConnectionPhase.connected)
                      Padding(
                        padding: const EdgeInsets.only(right: 20, left: 8),
                        child: RunTimeText(
                          timeStamp: ref.watch(runTimeProvider),
                        ),
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
