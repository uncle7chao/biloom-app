import 'package:material_ui/material_ui.dart';

/// fork 兼容扩展：v0.9.2 上游 TextStyleExtension（ui/text_style.dart）删掉了
/// 这几个成员，fork 页面仍在用。toLight/toLighter/toJetBrainsMono 上游仍在，
/// 由 common.dart re-export ui/text_style.dart 提供，这里绝不重复声明。
extension ForkTextStyleCompat on TextStyle {
  TextStyle get toSoftBold => copyWith(fontWeight: FontWeight.w500);

  TextStyle get toBold => copyWith(fontWeight: FontWeight.bold);

  TextStyle adjustSize(int size) => copyWith(fontSize: fontSize! + size);
}
