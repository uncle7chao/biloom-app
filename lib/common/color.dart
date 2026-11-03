import 'package:flutter/material.dart';

/// fork 兼容 shim：v0.9.2 上游把 common/color.dart 迁到 ui/color.dart（超集）。
export 'package:fl_clash/ui/color.dart';

/// fork 兼容：延迟分档配色（上游 ui/color.dart 未包含）。
Color? getDelayColor(int? delay) {
  if (delay == null) return null;
  if (delay < 0) return Colors.red;
  if (delay < 600) return Colors.green;
  return const Color(0xFFC57F0A);
}
