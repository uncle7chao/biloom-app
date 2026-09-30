import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/proxies/dashboard.dart';
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
    expect(find.byType(ProxyExitDashboard), findsOneWidget);
    expect(find.text('HK-01'), findsOneWidget);
    expect(find.text('Trojan'), findsOneWidget);
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
    expect(find.byType(ProxyExitDashboard), findsNothing);
  });
}
