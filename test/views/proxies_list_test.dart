import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/context.dart';
import 'package:fl_clash/views/proxies/card.dart';
import 'package:fl_clash/views/proxies/list.dart';
import 'package:fl_clash/views/views.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

void main() {
  testWidgets('the list scrolls its rows under the bar, pinning the header '
      'at its foot', (tester) async {
    tester.view.physicalSize = const Size(500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final profile = Profile.normal().copyWith(
      currentGroupName: 'Selector',
      selectedMap: {'Selector': 'Proxy 1'},
      unfoldSet: {'Selector'},
    );
    final group = Group(
      name: 'Selector',
      type: GroupType.Selector,
      hidden: false,
      now: 'Proxy 1',
      all: List.generate(
        160,
        (index) => Proxy(name: 'Proxy $index', type: 'Direct'),
      ),
    );
    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles([profile])),
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        currentGroupsStateProvider.overrideWithValue(
          GroupsState(value: [group]),
        ),
        groupsProvider.overrideWithValue([group]),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container
        .read(viewSizeProvider.notifier)
        .update((_) => const Size(500, 1000));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: ProxiesView()),
      ),
    );
    container
        .read(proxiesStyleSettingProvider.notifier)
        .update((state) => state.copyWith(type: ProxiesType.list));
    await tester.pump();

    final barBottom = tester.getRect(find.byType(AppBar)).bottom;
    // fork 的列表 header 紧贴 AppBar 底（appBarInset），不带上游的 +12 空隙。
    final contentTop = tester.element(find.byType(ListHeader)).appBarInset;
    expect(tester.getRect(find.byType(ListHeader)).top, contentTop);

    await tester.drag(find.byType(ProxyCard).first, const Offset(0, -300));
    await tester.pump();

    expect(tester.getRect(find.byType(ListHeader)).top, contentTop);
    expect(
      find
          .byType(ProxyCard)
          .evaluate()
          .map((element) => tester.getRect(find.byWidget(element.widget))),
      contains(
        predicate<Rect>(
          (rect) => rect.top < barBottom && rect.bottom > 0,
          'a card under the bar',
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('builds only the headers near the view and pins a far one '
      'once its rows reach the bar', (tester) async {
    tester.view.physicalSize = const Size(500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final profile = Profile.normal().copyWith(unfoldSet: {'Far'});
    final groups = [
      for (var index = 0; index < 40; index++)
        Group(name: 'G$index', type: GroupType.Selector, hidden: false),
      Group(
        name: 'Far',
        type: GroupType.Selector,
        hidden: false,
        all: List.generate(
          160,
          (index) => Proxy(name: 'Proxy $index', type: 'Direct'),
        ),
      ),
    ];
    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles([profile])),
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        currentGroupsStateProvider.overrideWithValue(
          GroupsState(value: groups),
        ),
        groupsProvider.overrideWithValue(groups),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container
        .read(viewSizeProvider.notifier)
        .update((_) => const Size(500, 1000));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: ProxiesView()),
      ),
    );
    container
        .read(proxiesStyleSettingProvider.notifier)
        .update((state) => state.copyWith(type: ProxiesType.list));
    await tester.pump();

    // fork 的列表是自有实现（ProxyExitDashboard + 自有组头），不沿用上游
    // _GroupSliver 的近景惰性组头 —— 组头首帧全量挂载；但行卡片仍由
    // SliverFixedExtentList 按视口惰性构建。这里断言行级惰性（fork 语义）。
    expect(
      find.byType(ProxyCard, skipOffstage: false).evaluate().length,
      lessThan(160),
    );

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    position.jumpTo(position.maxScrollExtent - 1000);
    await tester.pump();

    // 组名经 EmojiText(RichText) 渲染，find.text 匹配不到 —— 用组名谓词找。
    final far = find.byWidgetPredicate(
      (widget) => widget is ListHeader && widget.group.name == 'Far',
    );
    expect(far, findsOneWidget);
    expect(tester.getRect(far).top, tester.element(far).appBarInset);
    expect(
      find.byType(ProxyCard, skipOffstage: false).evaluate().length,
      lessThan(160),
    );
    expect(tester.takeException(), isNull);
  });
}
