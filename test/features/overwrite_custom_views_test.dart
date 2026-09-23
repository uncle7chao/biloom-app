import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/overwrite/overwrite.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/profiles/overwrite/custom/groups.dart';
import 'package:fl_clash/views/profiles/overwrite/custom/rules.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

class _TestProfileCustomRules extends ProfileCustomRules {
  final List<Rule> initial;

  _TestProfileCustomRules(this.initial);

  @override
  Stream<List<Rule>> build(int profileId) => Stream.value(initial);

  @override
  void order(int oldIndex, int newIndex) {}
}

class _TestProxyGroups extends ProxyGroups {
  final List<ProxyGroup> initial;

  _TestProxyGroups(this.initial);

  @override
  Stream<List<ProxyGroup>> build(int profileId) => Stream.value(initial);

  @override
  void order(int oldIndex, int newIndex) {}
}

class _TestOverwriteData extends Notifier<CustomOverwriteDate> {
  @override
  CustomOverwriteDate build() {
    return const CustomOverwriteDate(
      loaded: true,
      ruleTargets: {'DIRECT'},
      proxyNames: ['DIRECT'],
      proxyTypes: {'DIRECT': 'Direct'},
    );
  }

  void setRuleTargets(Set<String> ruleTargets) {
    state = state.copyWith(ruleTargets: ruleTargets);
  }
}

final _testOverwriteDataProvider =
    NotifierProvider<_TestOverwriteData, CustomOverwriteDate>(
      _TestOverwriteData.new,
    );

void _setViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('each group is its own card and the node preview expands', (
    tester,
  ) async {
    _setViewport(tester);
    final profile = Profile.normal().copyWith(
      overwriteType: OverwriteType.custom,
    );
    // 三个普通分组各带两个节点，外加一个「引用全部节点」的分组。最后那个刻意
    // 没有节点数可报，用来钉住「徽章缺席时卡片要把原因写在脸上」。
    final proxyGroups = [
      for (var index = 0; index < 3; index++)
        ProxyGroup(
          id: 100 + index,
          profileId: profile.id,
          name: 'Group $index',
          type: GroupType.Selector,
          proxies: ['N$index-a', 'N$index-b'],
        ),
      ProxyGroup(
        id: 200,
        profileId: profile.id,
        name: 'Group all',
        type: GroupType.URLTest,
        includeAllProxies: true,
      ),
    ];
    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles([profile])),
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        proxyGroupsProvider.overrideWith2((_) => _TestProxyGroups(proxyGroups)),
        customOverwriteDateProvider(profile.id).overrideWithValue(
          CustomOverwriteDate(
            loaded: true,
            proxyNames: const ['N0-a', 'N0-b'],
            proxyTypes: const {'N0-a': 'vmess', 'N0-b': 'trojan'},
            proxyGroups: proxyGroups,
            proxyProviders: const {'provider'},
            ruleTargets: {
              ...RuleTarget.baseTargets,
              // 成员名必须在 ruleTargets 里，否则这个组会被判成「引用了不存在的
              // 节点」而变红 —— 那是另一条路径，不该混进这条用例。
              ...proxyGroups.expand(
                (group) => group.proxies ?? const <String>[],
              ),
              ...proxyGroups.map((group) => group.name),
            },
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container
        .read(viewSizeProvider.notifier)
        .update((_) => const Size(1400, 1000));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(child: CustomProxyGroupsView(profile.id)),
      ),
    );
    await tester.pump();

    // 每个组一张独立卡片。原来铺的是「整块列表 + 行尾分隔线」，展开态塞不进
    // 那种结构，所以这两条断言反过来了：卡片数等于分组数、分隔线一条都没有。
    expect(find.byType(CommonCard), findsNWidgets(4));
    expect(find.byType(DecorationListItem), findsNothing);
    expect(find.byType(Divider), findsNothing);

    // 类型徽章人人一份；节点数徽章只有「不引用全部节点」的那三个才有，
    // 「引用全部节点」用一枚中性胶囊交代原因。
    expect(find.text('Selector'), findsNWidgets(3));
    expect(find.text('URLTest'), findsOneWidget);
    expect(find.text('2'), findsNWidgets(3));
    expect(find.byIcon(Icons.select_all), findsOneWidget);

    // 折叠时只出摘要，节点一个都不露面。
    expect(find.text('N0-a'), findsNothing);
    expect(find.text('N1-a'), findsNothing);

    await tester.tap(find.byIcon(Icons.expand_more).first);
    await tester.pumpAndSettle();

    // 只展开了第一个：它自己的两个节点出来，后面的组不受影响 ——
    // 展开状态在页面上、不在卡片里，这条断言就是钉它的。
    expect(find.text('N0-a'), findsOneWidget);
    expect(find.text('N0-b'), findsOneWidget);
    expect(find.text('N1-a'), findsNothing);
    expect(find.byType(Divider), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('group editor keeps long values inside its rows', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final profile = Profile.normal().copyWith(
      overwriteType: OverwriteType.custom,
    );
    final proxyGroups = [
      ProxyGroup(
        id: 100,
        profileId: profile.id,
        name: 'a-very-long-proxy-group-name-that-goes-on-and-on',
        type: GroupType.URLTest,
        icon: 'https://example.com/a/very/long/path/to/an/icon/file/name.png',
        filter: '(?i)hk|hong ?kong|an extremely long filter expression here',
        url: 'https://www.gstatic.com/generate_204/a/very/long/url/path',
      ),
    ];
    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles([profile])),
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        proxyGroupsProvider.overrideWith2((_) => _TestProxyGroups(proxyGroups)),
        customOverwriteDateProvider(profile.id).overrideWithValue(
          CustomOverwriteDate(
            loaded: true,
            proxyNames: const ['DIRECT'],
            proxyTypes: const {'DIRECT': 'Direct'},
            proxyGroups: proxyGroups,
            ruleTargets: RuleTarget.baseTargets,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container
        .read(viewSizeProvider.notifier)
        .update((_) => const Size(360, 800));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(child: CustomProxyGroupsView(profile.id)),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text(proxyGroups.single.name));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(OverwriteFormRow), findsWidgets);

    await tester.enterText(find.byType(TextFormField).first, 'y' * 400);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('rule invalid state refreshes when rule targets change', (
    tester,
  ) async {
    _setViewport(tester);
    final profile = Profile.normal().copyWith(
      overwriteType: OverwriteType.custom,
    );
    final rules = [
      const Rule(
        id: 1,
        content: 'example.com',
        ruleTarget: 'missing',
        order: '1',
      ),
    ];
    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles([profile])),
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        profileCustomRulesProvider.overrideWith2(
          (_) => _TestProfileCustomRules(rules),
        ),
        customOverwriteDateProvider(profile.id).overrideWith((ref) {
          return ref.watch(_testOverwriteDataProvider);
        }),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container
        .read(viewSizeProvider.notifier)
        .update((_) => const Size(1400, 1000));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(child: CustomRulesView(profile.id)),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.info), findsOneWidget);

    container.read(_testOverwriteDataProvider.notifier).setRuleTargets({
      ...container.read(_testOverwriteDataProvider).ruleTargets,
      'missing',
    });
    await tester.pump();

    expect(find.byIcon(Icons.info), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
