import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// 按平台挑「把条目抓起来」的门槛。
///
/// Flutter 自带的 [ReorderableDelayedDragStartListener] 用的是
/// `DelayedMultiDragGestureRecognizer`，要求**按住约 500ms** 才算开始拖动。
/// 那是给触屏设计的：手机上整行都是拖动区，不延迟就没法和「按住下滑 = 滚动
/// 列表」区分开。
///
/// 桌面端没有这个冲突（鼠标拖动本来就不会滚动列表），但沿用这套门槛的结果
/// 就是：用户按住往下一拖，什么也没发生 —— 他不知道自己还差半秒。所以桌面
/// 换成按下即抓的 [ReorderableDragStartListener]。
///
/// 移动端的门槛一个字没改，仍然是长按。
class CommonReorderableDragStartListener extends StatelessWidget {
  final int index;
  final Widget child;
  final bool enabled;

  const CommonReorderableDragStartListener({
    super.key,
    required this.index,
    required this.child,
    this.enabled = true,
  });

  /// 桌面 = 鼠标优先。用 `defaultTargetPlatform` 而不是窗口宽度：窗口很窄的
  /// 桌面窗口仍然是鼠标在操作，宽度判断会把它误判成手机。
  static bool get _isDesktopPlatform => switch (defaultTargetPlatform) {
    TargetPlatform.windows ||
    TargetPlatform.linux ||
    TargetPlatform.macOS => true,
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia => false,
  };

  @override
  Widget build(BuildContext context) {
    if (_isDesktopPlatform) {
      return ReorderableDragStartListener(
        index: index,
        enabled: enabled,
        child: child,
      );
    }
    return ReorderableDelayedDragStartListener(
      index: index,
      enabled: enabled,
      child: child,
    );
  }
}
