import 'package:fl_clash/ui/measure.dart';
import 'package:fl_clash/ui/typography.dart';

/// fork 兼容扩展：v0.9.2 上游 Measure 改为 AppTextStyle 度量制，
/// 这里把 fork 代码仍在用的 Material 风格文本高度 getter 映射过去
/// （尺寸就近对应：titleSmall→footnote、bodyMedium→subheadline 等）。
extension ForkMeasureCompat on Measure {
  double get titleSmallHeight => textHeight(AppTextStyle.footnote);

  double get titleMediumHeight => textHeight(AppTextStyle.subheadline);

  double get bodyLargeHeight => textHeight(AppTextStyle.callout);

  double get bodyMediumHeight => textHeight(AppTextStyle.subheadline);

  double get bodySmallHeight => textHeight(AppTextStyle.caption1);

  double get labelSmallHeight => textHeight(AppTextStyle.caption2);
}
