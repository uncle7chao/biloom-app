import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NetworkSpeed extends StatefulWidget {
  const NetworkSpeed({super.key});

  @override
  State<NetworkSpeed> createState() => _NetworkSpeedState();
}

class _NetworkSpeedState extends State<NetworkSpeed> {
  List<Point> initPoints = const [Point(0, 0), Point(1, 0)];

  List<Point> _getPoints(List<Traffic> traffics) {
    final List<Point> trafficPoints = traffics
        .toList()
        .asMap()
        .map(
          (index, e) => MapEntry(
            index,
            Point((index + initPoints.length).toDouble(), e.speed.toDouble()),
          ),
        )
        .values
        .toList();

    return [...initPoints, ...trafficPoints];
  }

  Traffic _getLastTraffic(List<Traffic> traffics) {
    if (traffics.isEmpty) return const Traffic();
    return traffics.last;
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return SizedBox(
      height: getWidgetHeight(2),
      child: RepaintBoundary(
        child: CommonCard(
          radius: AppCorner.xl,
          onPressed: () {},
          child: Consumer(
            builder: (_, ref, _) {
              final traffics = ref.watch(trafficsProvider).list;
              final traffic = _getLastTraffic(traffics);
              return Stack(
                fit: StackFit.expand,
                children: [
                  // 波形贴着卡片下缘铺开当背景，而不是缩在一个小方框里 —— 这张
                  // 卡是整块面板上唯一有实时数据的地方，让它整张都在「显示」。
                  Positioned(
                    top: 72.mAp,
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LineChart(
                      gradient: true,
                      color: Theme.of(context).colorScheme.primary,
                      points: _getPoints(traffics),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        InfoHeader(
                          padding: EdgeInsets.zero,
                          info: Info(
                            label: appLocalizations.networkSpeed,
                            iconData: Icons.speed_sharp,
                          ),
                        ),
                        const SizedBox(height: 10),
                        // 速度是这块面板上唯一「实时在动」的数字，让它当主角：
                        // 上下行各占一半、字号提到标题级，单位退成小字跟在后面。
                        // 原来这两个数挤在标题右边那行小字里，一眼扫过去读不出量级。
                        Row(
                          children: [
                            Expanded(
                              child: _SpeedReadout(
                                icon: Icons.arrow_upward_rounded,
                                show: traffic.up.traffic,
                              ),
                            ),
                            Expanded(
                              child: _SpeedReadout(
                                icon: Icons.arrow_downward_rounded,
                                show: traffic.down.traffic,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SpeedReadout extends StatelessWidget {
  const _SpeedReadout({required this.icon, required this.show});

  final IconData icon;
  final TrafficShow show;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final textTheme = context.textTheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            show.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.headlineSmall?.toLight,
          ),
        ),
        const SizedBox(width: 2),
        // 单位跟数字的底边走（大字旁边的小字浮在半空会显得很散）。
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(
            show.unit,
            maxLines: 1,
            style: textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
