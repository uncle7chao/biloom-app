import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/proxies/tab.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

/// 复现 01.00.29「代理页整页空白」的用户场景：
/// 页签布局 + 一个 160+ 成员的真实规模分组 + 更新订阅前后的状态往返。
/// 既有 proxies_tab_test 的组全都没有成员，卡片网格这条路在测试里没走过。
final _tabStateProvider = NotifierProvider<_TabStateNotifier, ProxiesTabState>(
  _TabStateNotifier.new,
);

class _TabStateNotifier extends Notifier<ProxiesTabState> {
  @override
  ProxiesTabState build() => _tabState(_realGroups());

  void set(ProxiesTabState value) => state = value;
}

const _groupNames = [
  '节点选择',
  '自动选择',
  '链式代理',
  '故障转移',
  '全球直连',
  '漏网之鱼',
];

List<Proxy> _nodes({int count = 162}) {
  const regions = ['🇺🇸', '🇭🇰', '🇸🇬', '🇩🇪', '🇫🇮', '🇬🇧', '☁️'];
  return [
    for (var i = 0; i < count; i++)
      Proxy(
        name: '${regions[i % regions.length]} 节点${i.toString().padLeft(2, '0')}',
        type: i % 3 == 0 ? 'Vless' : 'Trojan',
      ),
  ];
}

List<Group> _realGroups() {
  final nodes = _nodes();
  // 组名每次造**新字符串实例**（真实 app 里组名来自每次 JSON 解码，绝不相
  // 同一）。GlobalObjectKey 的相等性是 identical(value)—— 若共用 const 字符串，
  // 「空→回填」过渡帧里新旧两棵子树的 key 会相等，人为撞出 Duplicate GlobalKey，
  // 那是测试失真，不是 app 行为。
  final names = [
    for (final name in _groupNames) String.fromCharCodes(name.runes),
  ];
  return [
    Group(
      type: GroupType.Selector,
      name: names[0],
      now: nodes.first.name,
      all: nodes,
    ),
    Group(
      type: GroupType.URLTest,
      name: names[1],
      now: nodes.last.name,
      all: nodes,
    ),
    Group(
      type: GroupType.Selector,
      name: names[2],
      now: '☁️ 谷歌vps',
      all: [Proxy(name: '☁️ 谷歌vps', type: 'Hysteria2')],
    ),
    Group(
      type: GroupType.Fallback,
      name: names[3],
      now: nodes.first.name,
      all: nodes.take(8).toList(),
    ),
    Group(
      type: GroupType.Selector,
      name: names[4],
      now: 'DIRECT',
      all: [Proxy(name: 'DIRECT', type: 'Direct')],
    ),
    Group(
      type: GroupType.Selector,
      name: names[5],
      now: 'DIRECT',
      all: [Proxy(name: 'DIRECT', type: 'Direct')],
    ),
  ];
}

ProxiesTabState _tabState(List<Group> groups) {
  return ProxiesTabState(
    groups: groups,
    currentGroupName: _groupNames[0],
    proxyCardType: ProxyCardType.expand,
  );
}

void main() {
  late ProviderContainer container;
  late ProviderSubscription<Profile?> currentProfileSubscription;

  setUp(() {
    final profile = Profile.normal().copyWith(
      currentGroupName: _groupNames[0],
    );
    container = ProviderContainer(
      overrides: [
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        profilesProvider.overrideWith(() => TestProfiles([profile])),
        currentGroupsStateProvider.overrideWithValue(
          GroupsState(value: _realGroups()),
        ),
        groupsProvider.overrideWithValue(_realGroups()),
        proxiesTabStateProvider.overrideWith(
          (ref) => ref.watch(_tabStateProvider),
        ),
      ],
    );
    globalState.container = container;
    currentProfileSubscription = container.listen(currentProfileProvider, (_, _) {});
  });

  tearDown(() {
    currentProfileSubscription.close();
    container.dispose();
  });

  Future<void> pumpTabView(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          // 断言里要找中文文案（'全部'），不指定 locale 会走英文（'All'）。
          locale: const Locale('zh'),
          child: const ProxiesTabView(),
          homeBuilder: (child) => Scaffold(body: child),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders the card grid for a populated group', (tester) async {
    await pumpTabView(tester);

    // 页签胶囊（组名）可见。
    expect(find.text('节点选择', findRichText: true), findsWidgets);
    // 地区筛选栏可见。
    expect(find.text('全部', findRichText: true), findsOneWidget);
    // 节点卡片网格：成员节点名能找到（EmojiText 渲染 RichText）。
    expect(
      find.textContaining('节点', findRichText: true),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('survives the update-subscription round trip', (tester) async {
    await pumpTabView(tester);

    // 更新订阅：内核重启瞬间 groups 清空，随后带新实例回来（组名不变）。
    container.read(_tabStateProvider.notifier).set(_tabState(const []));
    await tester.pump();

    container.read(_tabStateProvider.notifier).set(_tabState(_realGroups()));
    await tester.pumpAndSettle();

    expect(find.text('全部', findRichText: true), findsOneWidget);
    expect(find.textContaining('节点', findRichText: true), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('survives rapid group instance replacement', (tester) async {
    await pumpTabView(tester);

    // 连续三轮「更新订阅」：每轮都是新实例、组名不变（Controller 不重建的分支）。
    for (var round = 0; round < 3; round++) {
      container
          .read(_tabStateProvider.notifier)
          .set(_tabState(_realGroups()));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.textContaining('节点', findRichText: true), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
