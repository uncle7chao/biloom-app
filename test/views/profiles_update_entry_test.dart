import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/profiles/profiles.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

/// 「更新订阅」入口的可发现性。
///
/// 用户反馈「没看到订阅更新按钮」，所以这里把**入口到底在哪、长什么样**钉住：
///
///   - 页头有一个全局「更新」，更新列表里所有订阅（图标 + 文字标签，不是纯图标）；
///   - 每张订阅卡片自己的「更新订阅」在 ⋮ 菜单里 —— 只有订阅类型才有这一项。
///
/// 这些用例是「入口存在且可被找到」的守卫，不是视觉回归：用户点不到入口，
/// 功能做得再对也没用。
void main() {
  void setViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(700, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<ProviderContainer> pumpProfiles(
    WidgetTester tester,
    List<Profile> profiles,
  ) async {
    setViewport(tester);
    final container = ProviderContainer(
      overrides: [profilesProvider.overrideWith(() => TestProfiles(profiles))],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(locale: Locale('zh'), child: ProfilesView()),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('页头有一个带文字标签的「更新」按钮', (tester) async {
    await pumpProfiles(tester, [Profile.normal(label: '机场', url: 'https://a/b')]);

    // 关键约束：这个入口**不能是纯图标**。之前它是右上角一个没有文字的 ↻，
    // 用户看不懂那是「更新订阅」，才会出现「没看到更新按钮」。
    expect(
      find.widgetWithText(FilledButton, '更新'),
      findsOneWidget,
      reason: '页头的全局更新入口必须是带文字的按钮，纯图标会被当成装饰',
    );
  });

  testWidgets('订阅卡片的 ⋮ 菜单里有「更新订阅」', (tester) async {
    await pumpProfiles(tester, [Profile.normal(label: '机场', url: 'https://a/b')]);

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();

    expect(
      find.text('更新订阅'),
      findsOneWidget,
      reason: '订阅配置必须能从卡片上直接更新，不必先进编辑页',
    );
  });

  testWidgets('本地配置的菜单里没有「更新订阅」', (tester) async {
    // 本地配置没有可拉取的来源，给它一个「更新订阅」只会点了没反应。
    await pumpProfiles(tester, [Profile.normal(label: '本地')]);

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();

    expect(find.text('更新订阅'), findsNothing);
  });

  testWidgets('没有配置时不显示更新按钮', (tester) async {
    await pumpProfiles(tester, const []);

    expect(find.widgetWithText(FilledButton, '更新'), findsNothing);
  });
}
