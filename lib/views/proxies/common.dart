import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

double get listHeaderHeight {
  final measure = globalState.measure;
  return 20 + measure.titleMediumHeight + 4 + measure.bodyMediumHeight + 2;
}

/// 卡片第二行里那个胶囊的高度（协议胶囊与测速胶囊同高）。
///
/// = `labelSmall` 一行字 + 上下各 2px 内边距 + 1px 描边，再留 1px 余量。
/// 单独抽成 getter 是因为 `getItemHeight` 也必须用同一份数字 ——
/// 两处各算一遍的话，只要差一点点，`SliverFixedExtentList` 就会在实机上报
/// 「A RenderFlex overflowed」。
double get proxyCardMetaHeight => globalState.measure.labelSmallHeight + 6;

/// 右下角悬浮按钮区比 `BottomInsetScope` 假设的多出来的那一截。
///
/// `BottomInsetScope.floatingActionButtonInset` 是按「一颗 56 高的 FAB」
/// 定死的 72（`kFloatingActionButtonMargin + 56`）。「代理」页（tab 布局）的
/// 右下角现在叠了两颗 —— 小测速按钮 40 + 间距 10 + 启动按钮 56 = 106，
/// 比它多 50。不补这一截，滚到底时最后一排节点会被按钮压住。
const double proxiesExtraFabInset = 52;

/// 把收藏的节点稳定地排到列表前面。
///
/// 「代理」页的排序（延迟/按名）在内核做，这里在展示层再做一次**稳定分区**：
/// 收藏的在前、其余保持原序。稳定的意义：没收藏时列表与原来完全一致，收藏时
/// 收藏块内部也保持内核排好的顺序（比如延迟升序），只是整体前移。
/// `_applyRegionFilter` 之后的筛选列表同样适用 —— 筛选与置顶正交。
List<Proxy> orderFavoritesFirst(List<Proxy> proxies, Set<String>? favorites) {
  if (favorites == null || favorites.isEmpty) {
    return proxies;
  }
  final head = proxies.where((proxy) => favorites.contains(proxy.name)).toList();
  final tail = proxies.where((proxy) => !favorites.contains(proxy.name)).toList();
  return [...head, ...tail];
}

double getItemHeight(ProxyCardType proxyCardType) {
  final measure = globalState.measure;
  // 卡片内部从上到下：8 上边距 + 名称 + 6 + 第二行 + 8 下边距（+ 1 余量）。
  // 第二行从「一行纯文字」换成了「胶囊」，高度跟 [proxyCardMetaHeight] 走。
  final baseHeight =
      16 + measure.bodyMediumHeight * 2 + 6 + proxyCardMetaHeight + 1;
  return switch (proxyCardType) {
    // 展开卡片原来比另外两种多占一整行（协议名单独一行），2026-09-23 起那一行
    // 并进了协议胶囊 —— 于是它与 shrink 的第二行结构、高度都一致了。
    // ⛔ 改这里必须同步 `ProxyCard` 的实际行数，两处各算一遍必溢出。
    ProxyCardType.expand || ProxyCardType.shrink => baseHeight,
    ProxyCardType.min => baseHeight - measure.bodyMediumHeight,
  };
}

class GroupOffsets {
  const GroupOffsets(this.groups, this.offsets);

  static const empty = GroupOffsets(<Group>[], <double>[]);

  final List<Group> groups;
  final List<double> offsets;

  bool get isEmpty => offsets.isEmpty;

  double offsetOf(String groupName) {
    final index = groups.indexWhere((group) => group.name == groupName);
    if (index < 0 || index >= offsets.length) {
      return 0;
    }
    return offsets[index];
  }

  Group? groupOf(String groupName) => groups.getGroup(groupName);
}

double getScrollToSelectedOffset({
  required WidgetRef ref,
  required String groupName,
  required List<Proxy> proxies,
  required int columns,
}) {
  final proxyCardType = ref.read(
    proxiesStyleSettingProvider.select((state) => state.cardType),
  );
  final selectedProxyName = ref.read(selectedProxyNameProvider(groupName));
  final findSelectedIndex = proxies.indexWhere(
    (proxy) => proxy.name == selectedProxyName,
  );
  final selectedIndex = findSelectedIndex != -1 ? findSelectedIndex : 0;
  final rows = (selectedIndex / columns).floor();
  return rows * getItemHeight(proxyCardType) + (rows - 1) * 8;
}
