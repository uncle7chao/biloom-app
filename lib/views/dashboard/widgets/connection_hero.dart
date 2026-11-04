import 'dart:math' as math;

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
        // B 方案 B2-b：连接成功 = 三弧线外扩淡出 + 对勾弹入（品牌图形语言）。
        leading = _ConnectionMark(phase: phase, color: stateColor!);
        title = appLocalizations.connectionStateConnected;
        subtitle = appLocalizations.connectionHeroTapToDisconnect;
      case ConnectionPhase.connecting:
        // 连接中 = 三弧线旋转（与启动图标同源的 arcs 图形语言），取代
        // 通用 CircularProgressIndicator。
        leading = _ConnectionMark(
          phase: phase,
          color: context.colorScheme.primary,
        );
        title = appLocalizations.connectionStateConnecting;
        subtitle = appLocalizations.connectionHeroTapToDisconnect;
      case ConnectionPhase.disconnected:
        stateColor = _disconnectedColor;
        leading = _ConnectionMark(phase: phase, color: stateColor);
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

/// 连接主卡的状态标记（B 方案 B2-b）：三条信号弧线 + 对勾。
///
/// 图形语言与启动图标同源（design/logo 的 biloom-arcs）——连接中三弧线
/// 旋转，连接成功弧线外扩淡出、对勾弹入；未连接维持电源图标。颜色一律
/// 由调用方传（连接中 = primary、已连接 = primary 混白 20%、未连接 =
/// 状态红），本组件不引入新色。
class _ConnectionMark extends StatefulWidget {
  const _ConnectionMark({required this.phase, required this.color});

  final ConnectionPhase phase;
  final Color color;

  @override
  State<_ConnectionMark> createState() => _ConnectionMarkState();
}

class _ConnectionMarkState extends State<_ConnectionMark>
    with TickerProviderStateMixin {
  // 双动画控制器（spin + settle），必须用多 ticker 的 TickerProviderStateMixin；
  // 单 ticker 版在编辑态同时挂两张连接卡时会直接抛断言。
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  @override
  void initState() {
    super.initState();
    _applyPhase();
  }

  @override
  void didUpdateWidget(covariant _ConnectionMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase != widget.phase) {
      _applyPhase();
    }
  }

  void _applyPhase() {
    switch (widget.phase) {
      case ConnectionPhase.connecting:
        _settle.stop();
        _settle.value = 0;
        if (!_spin.isAnimating) {
          _spin.repeat();
        }
      case ConnectionPhase.connected:
        _spin.stop();
        _settle.forward(from: 0);
      case ConnectionPhase.disconnected:
        _spin.stop();
        _settle.stop();
        _settle.value = 0;
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _settle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = 28.ap;
    if (widget.phase == ConnectionPhase.disconnected) {
      return Icon(Icons.power_settings_new, color: widget.color, size: size);
    }
    return AnimatedBuilder(
      animation: Listenable.merge([_spin, _settle]),
      builder: (_, _) => CustomPaint(
        size: Size.square(size),
        painter: _ArcsCheckPainter(
          progress: widget.phase == ConnectionPhase.connected
              ? _settle.value
              : 0,
          spin: _spin.value,
          color: widget.color,
        ),
      ),
    );
  }
}

/// 三弧线 + 对勾的画笔：[progress] 0 = 连接中（弧线满 alpha 旋转），
/// 1 = 弧线完全外扩淡出、对勾落定；[spin] 是弧线相位（0~1 一圈）。
class _ArcsCheckPainter extends CustomPainter {
  const _ArcsCheckPainter({
    required this.progress,
    required this.spin,
    required this.color,
  });

  final double progress;
  final double spin;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    // 三条信号弧线：连接完成时半径外扩、alpha 走零 —— 信号「发出去了」。
    final radius = size.shortestSide * 0.42 * (1 + 0.55 * progress);
    final arcAlpha = (1 - progress).clamp(0.0, 1.0);
    if (arcAlpha > 0) {
      final arcPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: arcAlpha);
      const sweep = 64 * math.pi / 180;
      const gap = (2 * math.pi - 3 * sweep) / 3;
      for (var i = 0; i < 3; i++) {
        final start =
            -math.pi / 2 + spin * 2 * math.pi + i * (sweep + gap);
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          start,
          sweep,
          false,
          arcPaint,
        );
      }
    }
    // 对勾：随进度放大弹入（easeOutBack 的回弹感用轻量近似）。
    if (progress > 0) {
      final t = Curves.easeOutBack.transform(progress.clamp(0.0, 1.0));
      final checkPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color.withValues(alpha: progress.clamp(0.0, 1.0));
      final path = Path()
        ..moveTo(center.dx - 5.5, center.dy + 0.5)
        ..lineTo(center.dx - 1.5, center.dy + 4.5)
        ..lineTo(center.dx + 6, center.dy - 4.5);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(0.5 + 0.5 * t);
      canvas.translate(-center.dx, -center.dy);
      canvas.drawPath(path, checkPaint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ArcsCheckPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.spin != spin ||
      oldDelegate.color != color;
}
