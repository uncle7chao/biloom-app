import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import 'list.dart';
import 'text.dart';

const _expireGap = 12.0;

/// 流量进度条的警示档位（与延迟读数的三档语义一致：绿 = 从容、琥珀 = 该看了、
/// 红 = 快没了）：用量过 75% 转琥珀、过 90% 转错误色。null = 主题默认色。
Color? _trafficBarColor(BuildContext context, double progress) {
  if (progress >= 0.9) {
    return context.colorScheme.error;
  }
  if (progress >= 0.75) {
    return const Color(0xFFC57F0A);
  }
  return null;
}

class SubscriptionInfoView extends StatelessWidget {
  final SubscriptionInfo? subscriptionInfo;

  const SubscriptionInfoView({super.key, this.subscriptionInfo});

  double _textWidth(BuildContext context, String text, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final info = subscriptionInfo;
    if (info == null || info.total == 0) {
      return const SizedBox.shrink();
    }
    final use = info.upload + info.download;
    final total = info.total;
    final progress = (use / total).clamp(0.0, 1.0).toDouble();

    final useShow = use.traffic.show;
    final totalShow = total.traffic.show;
    final expireDate = info.expire != 0
        ? DateTime.fromMillisecondsSinceEpoch(info.expire * 1000)
        : null;
    final expireShow = expireDate != null
        ? expireDate.show
        : context.appLocalizations.infiniteTime;
    // 窄卡兜底：完整日期放不下时压成短格式（MM/dd），而不是直接把到期时间
    // 整个丢掉 —— 到期是用户最关心的信息，宁可挤也不藏。
    final expireShort = expireDate != null
        ? DateFormat('MM/dd').format(expireDate)
        : null;
    final valueStyle = context.textTheme.bodyMedium?.toSoftBold.copyWith(
      color: context.colorScheme.onSurfaceVariant,
    );
    final metaStyle = context.textTheme.bodySmall?.toLight;
    final trafficLabel = '$useShow / $totalShow';
    final trafficText = Text(
      trafficLabel,
      style: valueStyle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final expireText = Text(
      expireShow,
      style: metaStyle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final expireShortText = expireShort == null
        ? null
        : Text(
            expireShort,
            style: metaStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final trafficWidth = _textWidth(context, trafficLabel, valueStyle);
            Widget? finalExpireWidget;
            if (trafficWidth +
                    _expireGap +
                    _textWidth(context, expireShow, metaStyle) <=
                constraints.maxWidth) {
              finalExpireWidget = expireText;
            } else if (expireShort != null &&
                trafficWidth +
                        _expireGap +
                        _textWidth(context, expireShort, metaStyle) <=
                    constraints.maxWidth) {
              finalExpireWidget = expireShortText;
            }
            return Row(
              children: [
                Expanded(child: trafficText),
                if (finalExpireWidget != null) ...[
                  const SizedBox(width: _expireGap),
                  finalExpireWidget,
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          minHeight: 4,
          value: progress,
          color: _trafficBarColor(context, progress),
          backgroundColor: context.colorScheme.primary.opacity15,
        ),
      ],
    );
  }
}

class SubscriptionInfoDetailView extends StatelessWidget {
  final SubscriptionInfo subscriptionInfo;

  const SubscriptionInfoDetailView({super.key, required this.subscriptionInfo});

  Widget _buildItem({String? label, required String value}) {
    return DecorationListItem(
      title: Text(label ?? value),
      subtitle: label == null ? null : TooltipLabel(value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final used = subscriptionInfo.upload + subscriptionInfo.download;
    final expire = subscriptionInfo.expire != 0
        ? DateTime.fromMillisecondsSinceEpoch(
            subscriptionInfo.expire * 1000,
          ).show
        : appLocalizations.infiniteTime;
    return SelectionArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          generateSectionV3(
            title: appLocalizations.trafficUsage,
            items: [
              _buildItem(
                label: appLocalizations.usedTraffic,
                value: used.traffic.show,
              ),
              _buildItem(
                label: appLocalizations.totalTraffic,
                value: subscriptionInfo.total.traffic.show,
              ),
            ],
          ),
          const SizedBox(height: 12),
          generateSectionV3(
            title: appLocalizations.expireTime,
            items: [_buildItem(value: expire)],
          ),
        ],
      ),
    );
  }
}
