import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/proxies/dashboard.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

void main() {
  late ProviderContainer container;

  Group selectorGroup(List<Proxy> proxies, {String now = ''}) {
    return Group(
      type: GroupType.Selector,
      name: kPrimarySelectorGroupName,
      now: now,
      all: proxies,
    );
  }

  Future<void> pumpDashboard(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          child: const ProxyExitDashboard(),
          homeBuilder: (child) => Scaffold(body: child),
        ),
      ),
    );
    await tester.pump();
  }

  tearDown(() {
    container.dispose();
  });

  testWidgets('shows the effective exit of the primary selector', (
    tester,
  ) async {
    final profile = Profile.normal();
    container = ProviderContainer(
      overrides: [
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        profilesProvider.overrideWith(() => TestProfiles([profile])),
        groupsProvider.overrideWithValue([
          selectorGroup(
            [Proxy(name: 'HK-01', type: 'Trojan')],
            now: 'HK-01',
          ),
        ]),
      ],
    );
    globalState.container = container;

    await pumpDashboard(tester);

    // 出口大卡亮出来：名字 + 协议胶囊都能找到。
    // 名字用 EmojiText 渲染（内部是 RichText），必须 findRichText 找得到。
    expect(find.byType(ProxyExitDashboard), findsOneWidget);
    expect(find.text('HK-01', findRichText: true), findsOneWidget);
    expect(find.text('Trojan', findRichText: true), findsOneWidget);
  });

  testWidgets('lays out inside a page Column (unbounded height)', (
    tester,
  ) async {
    // 01.00.29 实锤回归：仪表卡挂在 ProxiesTabView 的 Column 下，Column 给
    // 子项无界高度 —— 当年 Row + CrossAxisAlignment.stretch 在这里直接炸
    // 「BoxConstraints forces an infinite height」，release 下整页空白。
    // Scaffold body 是有界高度，测不出这个坑，必须按页面真实挂法测。
    final profile = Profile.normal();
    container = ProviderContainer(
      overrides: [
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        profilesProvider.overrideWith(() => TestProfiles([profile])),
        groupsProvider.overrideWithValue([
          selectorGroup(
            [Proxy(name: 'HK-01', type: 'Trojan')],
            now: 'HK-01',
          ),
        ]),
      ],
    );
    globalState.container = container;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          child: Column(
            children: [
              const ProxyExitDashboard(),
              const Expanded(child: SizedBox.shrink()),
            ],
          ),
          homeBuilder: (child) => Scaffold(body: child),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('HK-01', findRichText: true), findsOneWidget);
  });

  testWidgets('hides when the effective selector does not exist', (
    tester,
  ) async {
    final profile = Profile.normal();
    container = ProviderContainer(
      overrides: [
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        profilesProvider.overrideWith(() => TestProfiles([profile])),
        groupsProvider.overrideWithValue(const []),
      ],
    );
    globalState.container = container;

    await pumpDashboard(tester);

    // 没有生效选择器（没有配置）就整卡隐藏，不显示半截信息。
    // 注意：SizedBox.shrink 只是渲染为空，ProxyExitDashboard 这个 widget
    // 仍挂在树上，find.byType 永远找得到 —— 所以这里断言「没有卡片内容」。
    expect(find.byType(CommonCard), findsNothing);
    expect(find.text('HK-01', findRichText: true), findsNothing);
  });
}
