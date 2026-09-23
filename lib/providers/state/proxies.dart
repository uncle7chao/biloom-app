part of '../state.dart';

@riverpod
GroupsState currentGroupsState(Ref ref) {
  final mode = ref.watch(
    patchClashConfigProvider.select((state) => state.mode),
  );
  final groups = ref.watch(
    groupsProvider.select(
      (state) => state.map((item) {
        return item.copyWith(
          now: '',
          all: item.all.map((proxy) => proxy.copyWith(now: '')).toList(),
        );
      }),
    ),
  );
  // 只隐藏**明确**标了 hidden 的分组。上游写的是 `hidden == false`，那会把
  // 「字段缺失（null）」也判成隐藏 —— 任何没带上这个标记的分组都会从「代理」页
  // 静默消失。这类「看不见的状态」正是这轮要清理掉的东西，不能再引入一个。
  // 内核的四类策略组都会回传 bool（adapter/outboundgroup 的 MarshalJSON），
  // 所以两种写法在运行时等价，但这一种在缺字段时不会咬人。
  final visible = groups.where((item) => item.hidden != true).toList();
  final nonGlobal = visible
      .where((item) => item.name != GroupName.GLOBAL.name)
      .toList();
  return GroupsState(
    value: switch (mode) {
      Mode.direct => [],
      // 全局模式也要过滤 hidden。上游这里用的是**未过滤**的 groups，于是切一次
      // 出站模式，profile 里标了 hidden 的分组会全部冒出来 —— 用户刚被我们清理干净的
      // 页签栏又变回原样。GLOBAL 组本身不带 hidden，所以用 visible 不会把它漏掉。
      Mode.global => visible,
      // 规则模式下 GLOBAL 通常是冗余的：能落到它的流量本来就该由 profile 自己的
      // 分组承接，所以平时把它藏起来。但一份只带 proxies 的配置（例如直接导入的
      // 订阅转换结果）除 GLOBAL 外没有任何分组，藏掉它会让分组列表为空、
      // 「代理」页签整块消失 —— 用户连节点列表和测速按钮都找不到。
      // 所以只在「确实还有别的分组」时才隐藏 GLOBAL，否则原样保留作为兜底入口。
      Mode.rule => nonGlobal.isNotEmpty ? nonGlobal : visible,
    },
  );
}

@riverpod
ProxyState proxyState(Ref ref) {
  final suspend = ref.watch(suspendProvider);
  final isStart = ref.watch(runTimeProvider.select((state) => state != null));
  final systemProxySelector = ref.watch(
    networkSettingProvider.select(
      (state) => SystemProxySelectorState(
        systemProxy: state.systemProxy,
        bypassDomain: state.bypassDomain,
      ),
    ),
  );
  final mixedPort = ref.watch(
    patchClashConfigProvider.select((state) => state.mixedPort),
  );
  return ProxyState(
    isStart: suspend ? false : isStart,
    systemProxy: systemProxySelector.systemProxy,
    bassDomain: systemProxySelector.bypassDomain,
    port: mixedPort,
  );
}

@riverpod
ProxiesActionsState proxiesActionsState(Ref ref) {
  final pageLabel = ref.watch(currentPageLabelProvider);
  final hasProviders = ref.watch(
    providersProvider.select((state) => state.isNotEmpty),
  );
  final type = ref.watch(
    proxiesStyleSettingProvider.select((state) => state.type),
  );
  return ProxiesActionsState(
    pageLabel: pageLabel,
    hasProviders: hasProviders,
    type: type,
  );
}

@riverpod
GroupsState filterGroupsState(Ref ref, String query) {
  final currentGroups = ref.watch(currentGroupsStateProvider);
  if (query.isEmpty) {
    return currentGroups;
  }
  final lowQuery = query.toLowerCase();
  final groups = currentGroups.value
      .map((group) {
        return group.copyWith(
          all: group.all
              .where((proxy) => proxy.name.toLowerCase().contains(lowQuery))
              .toList(),
        );
      })
      .where((group) => group.all.isNotEmpty)
      .toList();
  return currentGroups.copyWith(value: groups);
}

@riverpod
ProxiesListState proxiesListState(Ref ref) {
  final query = ref.watch(queryProvider(QueryTag.proxies));
  final currentGroups = ref.watch(filterGroupsStateProvider(query));
  final currentUnfoldSet = ref.watch(unfoldSetProvider);
  final cardType = ref.watch(
    proxiesStyleSettingProvider.select((state) => state.cardType),
  );
  return ProxiesListState(
    groups: currentGroups.value,
    currentUnfoldSet: currentUnfoldSet,
    proxyCardType: cardType,
  );
}

@riverpod
ProxiesTabState proxiesTabState(Ref ref) {
  final query = ref.watch(queryProvider(QueryTag.proxies));
  final currentGroups = ref.watch(filterGroupsStateProvider(query));
  final currentGroupName = ref.watch(
    currentProfileProvider.select((state) => state?.currentGroupName),
  );
  final cardType = ref.watch(
    proxiesStyleSettingProvider.select((state) => state.cardType),
  );
  return ProxiesTabState(
    groups: currentGroups.value,
    currentGroupName: currentGroupName,
    proxyCardType: cardType,
  );
}

@riverpod
bool isStart(Ref ref) {
  return ref.watch(runTimeProvider.select((state) => state != null));
}

@riverpod
ProxiesTabControllerState proxiesTabControllerState(Ref ref) {
  return ref.watch(
    proxiesTabStateProvider.select(
      (state) => ProxiesTabControllerState(
        groupNames: state.groups.map((group) => group.name).toList(),
        currentGroupName: state.currentGroupName,
      ),
    ),
  );
}

@riverpod
ProxyGroupSelectorState proxyGroupSelectorState(
  Ref ref,
  String groupName,
  String query,
) {
  final proxiesStyle = ref.watch(proxiesStyleSettingProvider);
  final group = ref.watch(
    currentGroupsStateProvider.select(
      (state) => state.value.getGroup(groupName),
    ),
  );
  final sortNum = ref.watch(sortNumProvider);
  final lowQuery = query.toLowerCase();
  final proxies =
      group?.all.where((item) {
        return item.name.toLowerCase().contains(lowQuery);
      }).toList() ??
      [];
  return ProxyGroupSelectorState(
    testUrl: group?.testUrl,
    proxiesSortType: proxiesStyle.sortType,
    proxyCardType: proxiesStyle.cardType,
    sortNum: sortNum,
    groupType: group?.type ?? GroupType.Selector,
    proxies: proxies,
  );
}

@riverpod
String realTestUrl(Ref ref, [String? testUrl]) {
  final currentTestUrl = ref.watch(appSettingProvider).testUrl;
  return testUrl.takeFirstValid([currentTestUrl]);
}

@riverpod
int? delay(Ref ref, {required String proxyName, String? testUrl}) {
  final currentTestUrl = ref.watch(realTestUrlProvider(testUrl));
  final proxyState = ref.watch(realSelectedProxyStateProvider(proxyName));
  final effectiveTestUrl = proxyState.testUrl.takeFirstValid([currentTestUrl]);
  final effectiveProxyName = proxyState.proxyName;
  return ref.watch(
    delayDataSourceProvider.select(
      (state) => state[effectiveTestUrl]?[effectiveProxyName],
    ),
  );
}

@riverpod
bool delayTestPending(Ref ref, {required String proxyName, String? testUrl}) {
  final currentTestUrl = ref.watch(realTestUrlProvider(testUrl));
  final proxyState = ref.watch(realSelectedProxyStateProvider(proxyName));
  final effectiveTestUrl = proxyState.testUrl.takeFirstValid([currentTestUrl]);
  final key = delayTestKey(effectiveTestUrl, proxyState.proxyName);
  return ref.watch(
    pendingDelayTestsProvider.select((state) => state.contains(key)),
  );
}

@riverpod
Map<String, String> selectedMap(Ref ref) {
  final selectedMap = ref.watch(
    currentProfileProvider.select((state) => state?.selectedMap ?? {}),
  );
  return selectedMap;
}

@riverpod
Set<String> unfoldSet(Ref ref) {
  final unfoldSet = ref.watch(
    currentProfileProvider.select((state) => state?.unfoldSet ?? {}),
  );
  return unfoldSet;
}

@riverpod
SelectedProxyState realSelectedProxyState(Ref ref, String proxyName) {
  final groups = ref.watch(groupsProvider);
  final selectedMap = ref.watch(selectedMapProvider);
  return computeRealSelectedProxyState(
    proxyName,
    groups: groups,
    selectedMap: selectedMap,
  );
}

@riverpod
String? proxyName(Ref ref, String groupName) {
  final proxyName = ref.watch(
    selectedMapProvider.select((state) => state[groupName]),
  );
  return proxyName;
}

@riverpod
String? selectedProxyName(Ref ref, String groupName) {
  final proxyName = ref.watch(proxyNameProvider(groupName));
  final group = ref.watch(
    groupsProvider.select((state) => state.getGroup(groupName)),
  );
  return group?.getCurrentSelectedName(proxyName ?? '');
}

@riverpod
String proxyDesc(Ref ref, Proxy proxy) {
  final groupTypeNamesList = GroupType.values.map((e) => e.name).toList();
  if (!groupTypeNamesList.contains(proxy.type)) {
    return proxy.type;
  } else {
    final groups = ref.watch(groupsProvider);
    final index = groups.indexWhere((element) => element.name == proxy.name);
    if (index == -1) return proxy.type;
    final state = ref.watch(realSelectedProxyStateProvider(proxy.name));
    return "${proxy.type}(${state.proxyName.isNotEmpty ? state.proxyName : '*'})";
  }
}

/// 节点所属地区 —— **只看节点名，不查 IP**。
///
/// 为什么不查 IP：这批 CF 中转节点的域名实测解析出来是 Cloudflare 边缘 IP
/// （`c.ali88.site → 104.21.3.153`、`bestcf.top → 104.17.30.233`），
/// 拿它查 GeoIP 只会得到「美国」—— 那是 CF 边缘的位置，跟节点真实落地无关。
/// 认不出就返回 `unknown`，卡片上不标地区，绝不编一个。
///
/// 刻意**手写** `Provider.family` 而不是加 `@riverpod` 注解：这个解析不依赖
/// 任何其它 provider（输入只有节点名），注解只会平白多出一份生成代码。
/// 用 family 缓存则是有意义的 —— 卡片每次 build 都要取，缓存后零成本。
/// 详细规则见 `lib/common/proxy_region.dart`。
final proxyRegionProvider = Provider.family<ProxyRegion, Proxy>(
  (ref, proxy) => resolveProxyRegion(proxy.name),
);

/// 当前生效的「按地区筛选」：策略组名 → `ProxyRegion.key`（表里没有该键 = 不筛）。
///
/// **按策略组分开记**，不共用一个全局键：「代理」页有多个页签，各自的节点集合不同。
/// 共用一个键的话，在「香港节点」页选了香港、切到「美国节点」页就是一片空白 ——
/// 用户只会以为那一页坏了。分开记则每个页签各自保留自己的筛选，切回来还在。
///
/// 刻意**不落盘**：这是一次「我现在想找香港的节点」的临时动作，不是一个设置。
/// 落了盘，下次打开代理页会看到一份被悄悄筛掉一大半的列表，而筛选栏又未必在
/// 视线里 —— 「东西莫名其妙少了」正是这一轮要清掉的状态。
///
/// 手写 `NotifierProvider` 而不加 `@riverpod` 注解：这里不需要代码生成，
/// 而生成期的环境故障每次都让 `build_runner` 跑不起来（见 `common/proxy_region.dart`
/// 里同样的处理）。
class ProxyRegionFilter extends Notifier<Map<String, String?>> {
  @override
  Map<String, String?> build() => const {};

  void set(String groupName, String? regionKey) {
    if (state[groupName] == regionKey) {
      return;
    }
    final next = Map<String, String?>.from(state);
    if (regionKey == null) {
      next.remove(groupName);
    } else {
      next[groupName] = regionKey;
    }
    state = next;
  }

  void clear(String groupName) => set(groupName, null);
}

final proxyRegionFilterProvider =
    NotifierProvider<ProxyRegionFilter, Map<String, String?>>(
      ProxyRegionFilter.new,
    );

@riverpod
({bool isProxies, int sortNum, ProxiesSortType sortType}) needUpdateGroups(
  Ref ref,
) {
  final isProxies = ref.watch(
    currentPageLabelProvider.select((state) => state == PageLabel.proxies),
  );
  final sortNum = ref.watch(sortNumProvider);
  final sortType = ref.watch(
    proxiesStyleSettingProvider.select((state) => state.sortType),
  );
  return (isProxies: isProxies, sortNum: sortNum, sortType: sortType);
}
