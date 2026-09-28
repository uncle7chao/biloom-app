import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// 连接统计卡片：活动连接数、累计上下行流量、流量最大的目标主机。
/// 数据与连接页同源（内核连接快照），仅在本卡可见时按秒轮询。
class ConnectionsStat extends ConsumerStatefulWidget {
  const ConnectionsStat({super.key});

  @override
  ConsumerState<ConnectionsStat> createState() => _ConnectionsStatState();
}

class _ConnectionsStatState extends ConsumerState<ConnectionsStat>
    with WidgetsBindingObserver, ActivePollingMixin<ConnectionsStat> {
  CoreController get _core => ref.read(coreHandlerProvider);

  List<TrackerInfo>? _trackers;

  @override
  Duration get pollInterval => const Duration(seconds: 1);

  @override
  Future<void> poll(PollGuard isCurrent) async {
    List<TrackerInfo>? trackers;
    try {
      trackers = await _core.getConnections();
    } catch (_) {
      // 内核未运行或桥接失败：按无数据显示，卡片不打扰用户。
      trackers = null;
    }
    if (!isCurrent() || !mounted) {
      return;
    }
    setState(() {
      _trackers = trackers;
    });
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final trackers = _trackers;
    var count = 0;
    var up = 0;
    var down = 0;
    var topHost = '';
    var topHostTotal = 0;
    if (trackers != null) {
      count = trackers.length;
      for (final trackerInfo in trackers) {
        up += trackerInfo.upload;
        down += trackerInfo.download;
        final total = trackerInfo.upload + trackerInfo.download;
        if (total > topHostTotal) {
          topHostTotal = total;
          topHost = trackerInfo.metadata.host;
        }
      }
    }
    final upColor = globalState.theme.darken3PrimaryContainer;
    final downColor = globalState.theme.darken2SecondaryContainer;
    return SizedBox(
      height: getWidgetHeight(2),
      child: RepaintBoundary(
        child: CommonCard(
          radius: AppCorner.xl,
          info: Info(
            label: appLocalizations.connectionsStat,
            iconData: Icons.lan_outlined,
          ),
          onPressed: () {},
          child: Padding(
            padding: baseInfoEdgeInsets.copyWith(top: 0),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('$count', style: context.textTheme.titleLarge?.toLight),
                    const SizedBox(width: 8),
                    Flexible(
                      child: TooltipText(
                        text: Text(
                          appLocalizations.activeConnections,
                          style: context.textTheme.bodySmall?.toLighter,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _StatItem(icon: Icons.arrow_upward, color: upColor, value: up),
                const SizedBox(height: 4),
                _StatItem(
                  icon: Icons.arrow_downward,
                  color: downColor,
                  value: down,
                ),
                if (topHost.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.language,
                        size: 14,
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TooltipText(
                          text: Text(
                            topHost,
                            style: context.textTheme.bodySmall?.toLighter,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
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

class _StatItem extends StatelessWidget {
  const _StatItem({required this.icon, required this.color, required this.value});

  final IconData icon;
  final Color color;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 8),
            Text(
              value.traffic.value,
              style: context.textTheme.titleMedium?.toLight,
            ),
          ],
        ),
        Text(value.traffic.unit, style: context.textTheme.bodySmall?.toLighter),
      ],
    );
  }
}
