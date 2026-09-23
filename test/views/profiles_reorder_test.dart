import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/profiles/profiles.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

/// 配置排序页的拖拽门槛。
///
/// 原来的实现用 `ReorderableDelayedDragStartListener` —— 那个识别器要求
/// **按住约 500ms** 才能抓起条目（它是给触屏设计的：移动端整行都是拖动区，
/// 不延迟就没法和「拖动即滚动列表」区分开）。桌面鼠标用户按住就拖、不等这
/// 半秒，看到的就是「拖不动」。这里的用例把两个平台的门槛分别钉住。
void main() {
  Future<void> pumpSheet(WidgetTester tester, List<Profile> profiles) async {
    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles(profiles)),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        // 桌面端 showSheet 走的是侧边弹层，排序页本体因此要求 SheetProvider
        // 在位（它靠这个决定顶部留白）。
        child: TestApp(
          child: SheetProvider(
            type: SheetType.sideSheet,
            child: ReorderableProfilesSheet(profiles: profiles),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  List<String> visibleLabels(WidgetTester tester) {
    return tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(DecorationListItem),
            matching: find.byType(Text),
          ),
        )
        .map((text) => text.data ?? '')
        .where((label) => label.isNotEmpty)
        .toList();
  }

  List<Profile> buildProfiles() => [
    Profile.normal(label: 'first'),
    Profile.normal(label: 'second'),
    Profile.normal(label: 'third'),
  ];

  void setViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// 手动走一遍拖拽，好把「先按住多久」和「怎么移动」拆开控制 ——
  /// 用 `tester.drag` 就只能得到一个笼统的结果，分不清是门槛没过还是别的地方
  /// 把手势吃掉了。
  Future<void> dragItem(
    WidgetTester tester,
    Finder target, {
    required PointerDeviceKind kind,
    Duration? holdBefore,
  }) async {
    final gesture = await tester.startGesture(
      tester.getCenter(target),
      kind: kind,
    );
    if (holdBefore != null) {
      await tester.pump(holdBefore);
    }
    // 先过 touch slop，再走完剩下的距离，和真实拖动的手感一致。
    for (final step in const [Offset(0, 40), Offset(0, 90)]) {
      await gesture.moveBy(step);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('桌面端鼠标直接拖动即可重排，不需要长按', (tester) async {
    // 这个 debug 开关必须在本用例体内复位：框架在 body 结束后立刻校验，
    // addTearDown 跑得太晚，会被判成「测试改动了 foundation 调试变量」。
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      setViewport(tester);
      final profiles = buildProfiles();
      await pumpSheet(tester, profiles);

      expect(visibleLabels(tester), ['first', 'second', 'third']);

      await dragItem(
        tester,
        find.text('first'),
        kind: PointerDeviceKind.mouse,
      );

      expect(
        visibleLabels(tester).indexOf('first'),
        greaterThan(0),
        reason: '鼠标直接拖动应当把 first 挪走；顺序没变说明拖拽没被识别',
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('移动端长按拖动仍然有效', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      setViewport(tester);
      final profiles = buildProfiles();
      await pumpSheet(tester, profiles);

      await dragItem(
        tester,
        find.text('first'),
        kind: PointerDeviceKind.touch,
        holdBefore: const Duration(milliseconds: 600),
      );

      expect(visibleLabels(tester).indexOf('first'), greaterThan(0));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
