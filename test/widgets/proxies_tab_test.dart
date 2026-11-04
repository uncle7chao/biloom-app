import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/proxies/card.dart';
import 'package:fl_clash/views/proxies/proxies.dart';
import 'package:fl_clash/views/proxies/tab.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

final _tabStateProvider = NotifierProvider<_TabStateNotifier, ProxiesTabState>(
  _TabStateNotifier.new,
);

class _TabStateNotifier extends Notifier<ProxiesTabState> {
  @override
  ProxiesTabState build() => _tabState([_group('B'), _group('C')]);

  void set(ProxiesTabState value) => state = value;
}

void main() {
  late ProviderContainer globalContainer;
  late ProviderSubscription<Profile?> currentProfileSubscription;

  setUp(() {
    final profile = Profile.normal().copyWith(currentGroupName: 'B');
    globalContainer = ProviderContainer(
      overrides: [
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        profilesProvider.overrideWith(() => TestProfiles([profile])),
        currentGroupsStateProvider.overrideWithValue(
          GroupsState(value: [_group('A'), _group('B'), _group('C')]),
        ),
        proxiesTabStateProvider.overrideWith(
          (ref) => ref.watch(_tabStateProvider),
        ),
      ],
    );
    globalState.container = globalContainer;
    currentProfileSubscription = globalContainer.listen(
      currentProfileProvider,
      (_, _) {},
    );
  });

  tearDown(() {
    currentProfileSubscription.close();
    globalContainer.dispose();
  });

  Future<GlobalKey<ProxiesTabViewState>> pumpTabView(
    WidgetTester tester,
  ) async {
    final key = GlobalKey<ProxiesTabViewState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: globalContainer,
        child: TestApp(
          child: ProxiesTabView(key: key),
          homeBuilder: (child) => Scaffold(body: child),
        ),
      ),
    );
    await tester.pump();
    return key;
  }

  testWidgets('current group follows the tapped tab', (tester) async {
    final key = await pumpTabView(tester);

    expect(key.currentState?.currentGroup?.name, 'B');
    expect(isTabSelected(tester, 'B'), isTrue);

    await tester.tap(_pill('C'));
    await tester.pumpAndSettle();

    expect(key.currentState?.currentGroup?.name, 'C');
    expect(globalContainer.read(currentProfileProvider)?.currentGroupName, 'C');
    expect(isTabSelected(tester, 'C'), isTrue);
    expect(isTabSelected(tester, 'B'), isFalse);
  });

  testWidgets('a swipe between pages moves the selected tab', (tester) async {
    final key = await pumpTabView(tester);

    await tester.drag(find.byType(TabBarView), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(key.currentState?.currentGroup?.name, 'C');
    expect(isTabSelected(tester, 'C'), isTrue);
    expect(isTabSelected(tester, 'B'), isFalse);
  });

  testWidgets('keeps the outgoing tabs usable while the empty state enters', (
    tester,
  ) async {
    final key = await pumpTabView(tester);

    globalContainer.read(_tabStateProvider.notifier).set(_tabState([]));
    await tester.pump();

    expect(_pill('C'), findsOneWidget);
    await tester.tap(_pill('C'), warnIfMissed: false);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(key.currentState?.currentGroup, isNull);

    await tester.pumpAndSettle();

    expect(_pill('C'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the more button shows only once the tabs overflow', (
    tester,
  ) async {
    await pumpTabView(tester);

    expect(_moreButton(), findsNothing);

    globalContainer
        .read(_tabStateProvider.notifier)
        .set(_tabState([for (var i = 0; i < 12; i++) _group('Group $i')]));
    await tester.pumpAndSettle();

    expect(_moreButton(), findsOneWidget);
  });

  testWidgets('opens with the current tab in view beside the more button', (
    tester,
  ) async {
    globalContainer
        .read(_tabStateProvider.notifier)
        .set(
          _tabState([
            for (var i = 0; i < 12; i++) _group('Group $i'),
          ], current: 'Group 11'),
        );
    await pumpTabView(tester);
    await tester.pump();
    await tester.pump();

    final current = tester.getRect(tabOf('Group 11'));
    final more = tester.getRect(_moreButton());
    expect(isTabSelected(tester, 'Group 11'), isTrue);
    // fork 保证当前页签滚入视口；渐变「更多」按钮悬浮在条尾，不承诺完全避开。
    expect(current.right, lessThan(tester.view.physicalSize.width));
    expect(more.left, lessThan(tester.view.physicalSize.width));
  });

  testWidgets('the last tab scrolls clear of the more button', (tester) async {
    globalContainer
        .read(_tabStateProvider.notifier)
        .set(_tabState([for (var i = 0; i < 12; i++) _group('Group $i')]));
    await pumpTabView(tester);
    await tester.pump();

    final tabs = find.descendant(
      of: find.byType(TabBar),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(tabs).position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();

    final last = tester.getRect(tabOf('Group 11'));
    // fork：页签条右侧留 32 内边距，页签本体不超出条；渐变按钮悬浮其上。
    expect(last.right, lessThan(tester.view.physicalSize.width - 16));
  });

  testWidgets('the more menu stays short, opens on the checked current group '
      'and switches to the picked one', (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    globalContainer
        .read(_tabStateProvider.notifier)
        .set(
          _tabState([
            for (var i = 0; i < 20; i++) _group('Group $i'),
          ], current: 'Group 12'),
        );
    final key = await pumpTabView(tester);
    await tester.pump();

    // fork 的「更多」菜单是底部弹层（AdaptiveSheetScaffold + SettingTextCard
    // 列表），不是上游的 CommonPopupMenu 浮层。
    await tester.tap(_moreButton());
    await tester.pumpAndSettle();

    // SettingTextCard build 出 CommonCard（是其后代不是祖先），从条目文本往上找。
    final currentCard = find.ancestor(
      of: find.text('Group 12'),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget.runtimeType.toString() == 'CommonCard' &&
            (widget as dynamic).isSelected == true,
      ),
    );
    expect(currentCard, findsOneWidget);

    await tester.tap(_settingCard('Group 15'));
    await tester.pumpAndSettle();

    expect(_settingCard('Group 15'), findsNothing);
    expect(key.currentState?.currentGroup?.name, 'Group 15');
    expect(isTabSelected(tester, 'Group 15'), isTrue);
    final picked = tester.getRect(tabOf('Group 15'));
    final more = tester.getRect(_moreButton());
    expect(picked.left, greaterThanOrEqualTo(0));
    expect(picked.right, lessThan(more.left));
  });

  testWidgets('scroll to selected brings the row to the top of the grid', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final group = Group(
      type: GroupType.Selector,
      name: 'B',
      all: [for (var i = 0; i < 80; i++) Proxy(name: 'B-$i', type: 'ss')],
    );
    globalContainer.read(groupsProvider.notifier).value = [group];
    final profile = globalContainer.read(currentProfileProvider)!;
    globalContainer
        .read(profilesProvider.notifier)
        .put(profile.copyWith(selectedMap: {'B': 'B-41'}));
    globalContainer
        .read(_tabStateProvider.notifier)
        .set(_tabState([_group('A'), group]));
    final key = await pumpTabView(tester);
    await tester.pumpAndSettle();
    final firstRowTop = tester
        .getRect(find.text('B-0', findRichText: true).first)
        .top;

    key.currentState?.scrollToGroupSelected();
    await tester.pumpAndSettle();

    // fork 的滚动对齐带 8px 行内边距差，选中行落在首行位置附近即可。
    expect(
      tester.getRect(find.text('B-41', findRichText: true).first).top,
      closeTo(firstRowTop, 10),
    );
  });

  testWidgets('cards rest where the grid clips them, clear of the tabs', (
    tester,
  ) async {
    final group = Group(
      type: GroupType.Selector,
      name: 'B',
      all: [for (var i = 0; i < 40; i++) Proxy(name: 'B-$i', type: 'ss')],
    );
    globalContainer
        .read(_tabStateProvider.notifier)
        .set(_tabState([_group('A'), group]));
    await pumpTabView(tester);
    await tester.pumpAndSettle();
    final tabs = tester.getRect(tabOf('B'));
    final grid = tester.getRect(find.byType(GridView));

    // fork 的页签和网格之间还隔着「当前出口」仪表卡与地区筛选栏，
    // 网格始终在页签下方即可；网格自带 16 内边距，首卡不贴网格顶。
    expect(grid.top, greaterThan(tabs.bottom));
    expect(
      tester.getRect(find.byType(ProxyCard).first).top,
      greaterThanOrEqualTo(grid.top),
    );
  });

  testWidgets('a long press on a card offers the node actions menu, one from '
      'a provider too', (tester) async {
    const group = Group(
      type: GroupType.Selector,
      name: 'B',
      all: [
        Proxy(name: 'B-0', type: 'ss'),
        Proxy(name: 'B-1', type: 'ss', providerName: 'sub'),
      ],
    );
    globalContainer.read(groupsProvider.notifier).value = [group];
    final profile = globalContainer.read(currentProfileProvider)!;
    globalContainer
        .read(profilesProvider.notifier)
        .put(profile.copyWith(selectedMap: {'B': 'B-0'}));
    globalContainer
        .read(_tabStateProvider.notifier)
        .set(_tabState([_group('A'), group]));
    await pumpTabView(tester);
    await tester.pumpAndSettle();
    // fork 的卡片菜单是收藏/测速/分享/删除（CommonPopupMenu，双类用谓词）。
    final menu = _popupMenu();

    await tester.longPress(find.text('B-0', findRichText: true));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: menu, matching: find.text('Favorite node')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: menu, matching: find.text('Test')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: menu, matching: find.text('Copy share link')),
      findsOneWidget,
    );

    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('B-1', findRichText: true));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: menu, matching: find.text('Favorite node')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: menu, matching: find.text('Copy share link')),
      findsOneWidget,
    );
  });

  testWidgets('a custom profile offers the same node actions menu', (
    tester,
  ) async {
    const group = Group(
      type: GroupType.Selector,
      name: 'B',
      all: [
        Proxy(name: 'B-0', type: 'ss'),
        Proxy(name: 'B-1', type: 'ss', providerName: 'sub'),
      ],
    );
    globalContainer.read(groupsProvider.notifier).value = [group];
    final profile = globalContainer.read(currentProfileProvider)!;
    globalContainer
        .read(profilesProvider.notifier)
        .put(profile.copyWith(type: ProfileType.custom));
    globalContainer
        .read(_tabStateProvider.notifier)
        .set(_tabState([_group('A'), group]));
    await pumpTabView(tester);
    await tester.pumpAndSettle();
    final menu = _popupMenu();

    await tester.longPress(find.text('B-0', findRichText: true));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: menu, matching: find.text('Favorite node')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: menu, matching: find.text('Delete node')),
      findsOneWidget,
    );

    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('B-1', findRichText: true));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: menu, matching: find.text('Favorite node')),
      findsOneWidget,
    );
  });

  testWidgets('a new current group leaves the visible cards as they were', (
    tester,
  ) async {
    final group = Group(
      type: GroupType.Selector,
      name: 'B',
      all: [for (var i = 0; i < 4; i++) Proxy(name: 'B-$i', type: 'ss')],
    );
    final state = _tabState([_group('A'), group]);
    globalContainer.read(_tabStateProvider.notifier).set(state);
    await pumpTabView(tester);
    final card = find.byType(ProxyCard).first;
    final before = tester.widget(card);

    globalContainer
        .read(_tabStateProvider.notifier)
        .set(state.copyWith(currentGroupName: 'A'));
    await tester.pump();

    // fork 切组会重建 ProxyCard 实例，但卡片 key（组名.节点名）稳定，
    // 元素状态因此保留 —— 断言 key 不变即可。
    expect(
      (tester.widget(card) as ProxyCard).key,
      (before as ProxyCard).key,
    );
  });

  testWidgets('lays each tab out at the width its label takes', (tester) async {
    const names = ['A', '🚀 节点选择', 'Group with a long name'];
    globalContainer
        .read(_tabStateProvider.notifier)
        .set(_tabState([for (final name in names) _group(name)], current: 'A'));
    await pumpTabView(tester);

    for (final name in names) {
      final tab = tabOf(name);
      expect(
        tester.getSize(tab).width,
        closeTo(
          tester
              .renderObject<RenderBox>(tab)
              .getMaxIntrinsicWidth(double.infinity),
          1,
        ),
        reason: name,
      );
    }
  });

  testWidgets('builds only the tabs in view and opens on a far current one', (
    tester,
  ) async {
    globalContainer
        .read(_tabStateProvider.notifier)
        .set(
          _tabState([
            for (var i = 0; i < 200; i++) _group('Group $i'),
          ], current: 'Group 180'),
        );
    await pumpTabView(tester);
    await tester.pump();
    await tester.pump();

    // fork 的页签条（TabBar + _ProxyTabPill）不做上游 GroupTabs 的近景惰性
    // 构建 —— 断言改为打开时落在远端当前页签上且选中。
    final current = tester.getRect(tabOf('Group 180'));
    final more = tester.getRect(_moreButton());
    expect(isTabSelected(tester, 'Group 180'), isTrue);
    expect(current.left, greaterThanOrEqualTo(0));
    expect(current.right, lessThan(more.left));
  });

  testWidgets('the bar following the current group leaves the page built', (
    tester,
  ) async {
    globalContainer
        .read(proxiesStyleSettingProvider.notifier)
        .update((state) => state.copyWith(type: ProxiesType.tab));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: globalContainer,
        child: const TestApp(child: ProxiesView()),
      ),
    );
    await tester.pump();
    expect(find.byType(TabBar), findsOneWidget);

    final state = globalContainer.read(_tabStateProvider);
    globalContainer
        .read(_tabStateProvider.notifier)
        .set(state.copyWith(currentGroupName: 'C'));
    globalContainer.read(delayTestingGroupsProvider.notifier).start('C');
    await tester.pump();

    expect(globalContainer.read(currentGroupDelayTestingProvider), isTrue);
    expect(find.byType(TabBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rebuilds the tab bar when groups return', (tester) async {
    final key = await pumpTabView(tester);

    globalContainer.read(_tabStateProvider.notifier).set(_tabState([]));
    await tester.pumpAndSettle();
    globalContainer
        .read(_tabStateProvider.notifier)
        .set(_tabState([_group('A'), _group('B'), _group('C')]));
    await tester.pumpAndSettle();

    for (final name in ['A', 'B', 'C']) {
      expect(tabOf(name), findsOneWidget);
    }
    expect(key.currentState?.currentGroup?.name, 'B');
    expect(isTabSelected(tester, 'B'), isTrue);
    expect(tester.takeException(), isNull);
  });
}

/// fork 的页签是自有胶囊设计（`_ProxyTabPill`，私有类，组名经 EmojiText 渲染），
/// find.text 匹配不到 —— 统一用谓词找胶囊本体。
Finder _pill(String name) => find.byWidgetPredicate(
  (widget) =>
      widget.runtimeType.toString() == '_ProxyTabPill' &&
      (widget as dynamic).name == name,
);

Finder tabOf(String name) => _pill(name);

bool isTabSelected(WidgetTester tester, String name) =>
    (tester.widget(_pill(name)) as dynamic).selected as bool;

/// fork 的「更多」按钮：IconButton(tooltip: More)，图标随端切换（expand_more /
/// chevron_right），用 tooltip 定位最稳。
Finder _moreButton() => find.byTooltip('More');

/// fork 弹层/菜单里的组条目：SettingTextCard（fork 版，双类同名用 runtimeType）。
Finder _settingCard(String text) => find.byWidgetPredicate(
  (widget) =>
      widget.runtimeType.toString() == 'SettingTextCard' &&
      (widget as dynamic).text == text,
);

/// fork 的卡片长按菜单是 widgets 版 CommonPopupMenu（ui 版被 hide），双类同名。
Finder _popupMenu() => find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == 'CommonPopupMenu',
);

ProxiesTabState _tabState(List<Group> groups, {String current = 'B'}) {
  return ProxiesTabState(
    groups: groups,
    currentGroupName: current,
    proxyCardType: ProxyCardType.standard,
  );
}

Group _group(String name) {
  return Group(type: GroupType.Selector, name: name);
}
