import 'package:flutter/material.dart';

/// fork 兼容：v0.9.2 上游 ui/color.dart 未包含的 Color 扩展成员。
extension ForkColorCompat on Color {
  Color blendDarken(BuildContext context, {double factor = 0.1}) {
    final brightness = Theme.of(context).brightness;
    return Color.lerp(
      this,
      brightness == Brightness.dark ? Colors.white : Colors.black,
      factor,
    )!;
  }
}
