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
/// 与「当前生效」在其他页面的表达一致），未连接/连接中用普通卡面。连接中
/// 不可点 —— 连接动作本身已经在飞，再点一次只会叠加请求。
class ConnectionHero extends ConsumerWidget {
  const ConnectionHero({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = ref.watch(connectionPhaseProvider);
    final appLocalizations = context.appLocalizations;
    final textTheme = context.textTheme;

    final Widget leading;
    final String title;
    final String subtitle;
    switch (phase) {
      case ConnectionPhase.connected:
        leading = Icon(
          Icons.check_circle,
          color: context.colorScheme.primary,
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
        leading = Icon(
          Icons.power_settings_new,
          color: context.colorScheme.onSurfaceVariant,
          size: 28.ap,
        );
        title = appLocalizations.connectionStateDisconnected;
        subtitle = appLocalizations.connectionHeroTapToConnect;
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
                    style: textTheme.titleMedium?.toSoftBold,
                  ),
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
              ),
            ),
            // 已连接时把运行时长直接亮出来 —— 用户关心的下一个问题就是
            // 「连了多久了」，别让他再去悬浮球那里找。
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
    );
  }
}
