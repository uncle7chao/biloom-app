part of '../state.dart';

/// 链式代理注入进运行时配置的节点名集合：链节点本体 + 快照注入的外部前置
/// 节点本体（见 `common/proxy_chains.dart` 的 injectProxyChains）。GLOBAL 页签
/// 的展示层用它把这些「链的东西」从节点列表里摘掉 —— 链统一在「链式代理」
/// 页签里出现与选择。配置组装（setup.dart）在每次应用配置时重写本集合。
///
/// 手写 Notifier 不走代码生成：本文件里 ProxyRegionFilter 等同款处理（生成器
/// 在环境故障期跑不动，而这里必须在组装配置的主隔离同步写入）。
class ChainInjectedNames extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void set(Set<String> names) => state = names;
}

final chainInjectedNamesProvider =
    NotifierProvider<ChainInjectedNames, Set<String>>(ChainInjectedNames.new);

/// GLOBAL 组的展示层过滤：链式代理注入的节点（链节点 + 快照前置节点）
/// 不出现在 GLOBAL 成员里 —— 它们的家在「链式代理」页签。内核数据不动，
/// 仅展示层过滤。抽成顶层纯函数便于测试。
List<Proxy> filterGlobalGroupMembers(
  List<Proxy> all,
  Set<String> injectedChainNames,
) {
  if (injectedChainNames.isEmpty) {
    return all;
  }
  return all
      .where((proxy) => !injectedChainNames.contains(proxy.name))
      .toList();
}

/// 内核内置出站的 type 值（mihomo adapter 侧的 Type() 串）。它们不是订阅节点。
const _builtinOutboundTypes = {
  'Direct',
  'Reject',
  'Compatible',
  'Pass',
  'RejectDrop',
};

/// 组页签成员列表的展示层过滤（GLOBAL 之外的组共用）：成员里的**策略组**与
/// **内置出站**（DIRECT/REJECT 等）不作为卡片出现。它们是「出口模式」的切换
/// 入口（自动最快 / 主备 / 直连），不是节点 —— 混在节点列表里，看起来就像
/// 页签掉进了节点列表（2026-09-27 用户拍板：一律不显示）。内核成员数据不动，
/// 选中状态照旧；代价是这几个模式不再能从组页签里一键切回。GLOBAL 页签走
/// 自己的规则（[filterGlobalGroupMembers]），不经过这里。
List<Proxy> filterGroupMemberCards(List<Proxy> all) {
  return all.where((proxy) {
    if (GroupTypeExtension.valueList.contains(proxy.type)) {
      return false;
    }
    return !_builtinOutboundTypes.contains(proxy.type);
  }).toList();
}

@riverpod
GroupsState currentGroupsState(Ref ref) {
  final mode = ref.watch(
    patchClashConfigProvider.select((state) => state.mode),
  );
  final injectedChainNames = ref.watch(chainInjectedNamesProvider);
  final groups = ref.watch(
    groupsProvider.select(
      (state) => state.map((item) {
        final all =
            item.name == GroupName.GLOBAL.name
            ? filterGlobalGroupMembers(item.all, injectedChainNames)
            : filterGroupMemberCards(item.all);
        return item.copyWith(
          now: '',
          all: all.map((proxy) => proxy.copyWith(now: '')).toList(),
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

/// 节点所属地区 —— **实测落地优先，没测过才看名字**（名字路线绝不查 IP）。
///
/// 为什么名字路线不查 IP：这批 CF 中转节点的域名实测解析出来是 Cloudflare
/// 边缘 IP（`c.ali88.site → 104.21.3.153`、`bestcf.top → 104.17.30.233`），
/// 拿它查 GeoIP 只会得到「美国」—— 那是 CF 边缘的位置，跟节点真实落地无关。
/// 而「测落地」走的是另一条路：请求真的从节点里发出去看出口，那条路的结果
/// 可信，所以排前面。认不出就返回 `unknown`，卡片上不标地区，绝不编一个。
///
/// 刻意**手写** `Provider.family` 而不是加 `@riverpod` 注解 —— 生成器在环境
/// 故障期跑不了。用 family 缓存则是有意义的 —— 卡片每次 build 都要取，
/// 缓存后零成本。详细规则见 `lib/common/proxy_region.dart`。
final proxyRegionProvider = Provider.family<ProxyRegion, Proxy>(
  (ref, proxy) {
    // 落地优先：实测过的节点标签跟着真实出口走（US 名字实落吉隆坡就标 🇲🇾），
    // 没测过的才按名字认。用 **select 按节点名取** 而不是 watch 整表 —— 批量
    // 测落地时每两秒就有一行变，watch 整表会让**所有**卡片跟着整页重build；
    // select 之后只有「这条记录变了」的那张卡片重建。未变的行持有同一个
    // ProxyExitInfo 实例，select 的同一性比较天然不会误触发。
    final stored = ref.watch(
      proxyExitStoreProvider.select((state) => state.value?[proxy.name]),
    );
    if (stored != null) {
      final region = ProxyRegion.ofCountry(stored.countryCode);
      if (region != null) {
        return region;
      }
    }
    return resolveProxyRegion(proxy.name);
  },
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

/// 节点收藏（按配置分开记：profileId 字符串 → 收藏名字列表，列表序 = 置顶序）。
///
/// 代理页一个组动辄两三百个节点，常用的那几个每次都要翻 —— 收藏 + 置顶
/// 是这个体量列表的基本盘。持久层在 `common/proxy_favorites.dart`。
///
/// 手写 `AsyncNotifierProvider`（同 ProxyExitStore 的理由：生成器环境故障）。
class ProxyFavorites extends AsyncNotifier<Map<String, List<String>>> {
  @override
  Future<Map<String, List<String>>> build() => ProxyFavoritesStore.load();

  Set<String>? of(int? profileId) {
    if (profileId == null) return null;
    final list = state.value?[profileId.toString()];
    return list == null ? null : Set<String>.from(list);
  }

  void toggle(int profileId, String name) {
    final key = profileId.toString();
    final current = Map<String, List<String>>.from(state.value ?? const {});
    final list = List<String>.from(current[key] ?? const []);
    // remove 返回 false 说明本来不在 → 加入；在 → 移除。
    if (!list.remove(name)) {
      list.add(name);
    }
    if (list.isEmpty) {
      current.remove(key);
    } else {
      current[key] = list;
    }
    state = AsyncData(current);
    unawaited(ProxyFavoritesStore.save(current));
  }
}

final proxyFavoritesProvider =
    AsyncNotifierProvider<ProxyFavorites, Map<String, List<String>>>(
      ProxyFavorites.new,
    );

/// 「测落地」的结果：这个节点真实出口的国家码与 IP。
///
/// 节点名的地区标注是**机场随手写的**（实测 `US-443-WS-TLS` 落在吉隆坡、
/// `SG-*` 落在马尼拉），只有真的把一个请求从节点里发出去、看回显服务认出
/// 的出口 IP，才能知道它到底在哪。`countryCode` 是内核本地 geoip 数据认出
/// 的两位码（认不出为空串）。[testedAt] 供落库后判新鲜度 —— 落地会漂移，
/// 没有时间戳的记录没法淘汰。
class ProxyExitInfo {
  const ProxyExitInfo({
    required this.countryCode,
    required this.ip,
    required this.testedAt,
  });

  final String countryCode;
  final String ip;

  /// 探测完成时刻的毫秒时间戳。
  final int testedAt;

  Map<String, dynamic> toJson() => {
    'countryCode': countryCode,
    'ip': ip,
    'testedAt': testedAt,
  };

  factory ProxyExitInfo.fromJson(Map<String, dynamic> json) => ProxyExitInfo(
    countryCode: json['countryCode'] as String? ?? '',
    ip: json['ip'] as String? ?? '',
    testedAt: (json['testedAt'] as num?)?.toInt() ?? 0,
  );
}

/// [ProxyExit] 的状态：谁正在测、测出了什么。
///
/// `results[name] == null` 表示**测过但失败** —— 与「没测过」（键不存在）
/// 是两回事，按钮要据此显示「失败」而不是「测落地」。结果只留在本次会话，
/// 要跨会话看 [ProxyExitStore] —— 那一层只存成功、只当新鲜数据用。
class ProxyExitState {
  const ProxyExitState({this.testing = const {}, this.results = const {}});

  final Set<String> testing;
  final Map<String, ProxyExitInfo?> results;
}

/// 落地结果的**持久层**（drift 表 `proxy_exits`，经 `ProxyExitsDao`）。
///
/// 为什么只存成功：失败多半是「节点此刻不通」这种暂时态，把它存下来会让
/// 一个昨天还好的节点今天被标成「测不出」。失败让会话态去表达就够了。
///
/// 写放大控制：批测一轮两三百个节点，内存 map 即时更新（卡片渐进刷新），
/// 磁盘侧攒 2 秒去抖、把窗口内变过的行**一次性 upsert**——一行一次写，
/// 不再是旧 shared_preferences 方案的「整键 JSON 全量重写」。
class ProxyExitStore extends AsyncNotifier<Map<String, ProxyExitInfo>> {
  /// 落地会漂移（服务端负载均衡让同一节点不同时刻从不同出口出去），
  /// 超过这个时间的记录不再当作地区依据 —— 过期数据比没数据更糟。
  static const freshness = Duration(days: 14);

  Timer? _saveDebounce;
  final Map<String, ProxyExitInfo> _pending = {};

  @override
  Future<Map<String, ProxyExitInfo>> build() async {
    final result = <String, ProxyExitInfo>{};
    try {
      final dao = database.proxyExitsDao;
      // 旧 shared_preferences 方案的一次性搬家：库空而 SP 有货才动。
      await dao.migrateLegacyIfNeeded();
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final row in await dao.all()) {
        if (now - row.testedAt <= freshness.inMilliseconds) {
          result[row.proxyName] = ProxyExitInfo(
            countryCode: row.countryCode,
            ip: row.ip ?? '',
            testedAt: row.testedAt,
          );
        }
      }
      // 过期行顺手清掉，表别越攒越大。
      await dao.deleteOlderThan(now - freshness.inMilliseconds);
      return result;
    } catch (_) {
      // 库坏了不挡 UI —— 本次会话退化为纯名字识别，下次探测会再写。
      return const {};
    }
  }

  /// 记录一次成功探测。内存立即生效（卡片渐进刷新），写库去抖 ——
  /// 全量测一轮是两三百个节点，一个节点刷一次盘毫无必要。
  void record(String proxyName, ProxyExitInfo info) {
    if (info.countryCode.isEmpty) {
      // 国家码都认不出的记录不配入库：地区层拿它没有任何用处。
      return;
    }
    final current = Map<String, ProxyExitInfo>.from(state.value ?? const {});
    current[proxyName] = info;
    state = AsyncData(current);
    _pending[proxyName] = info;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 2), _save);
  }

  Future<void> _save() async {
    if (_pending.isEmpty) {
      return;
    }
    final batch = Map<String, ProxyExitInfo>.from(_pending);
    _pending.clear();
    try {
      await database.proxyExitsDao.upsertAll([
        for (final entry in batch.entries)
          ProxyExitRecord(
            proxyName: entry.key,
            countryCode: entry.value.countryCode,
            ip: entry.value.ip.isEmpty ? null : entry.value.ip,
            testedAt: entry.value.testedAt,
          ),
      ]);
    } catch (_) {
      // 写库失败不影响本次会话 —— 内存里那份还在，下次探测会再试。
    }
  }

  /// 立刻把去抖窗口里的待写记录落库（取消定时器、同步写）。退出流程的
  /// cleanup 调用 —— 不 flush 的话，批测结束前几秒测到的结果会随进程
  /// 退出一起丢掉，下一轮批测又得重新烧一遍流量。
  Future<void> flushSave() async {
    _saveDebounce?.cancel();
    await _save();
  }

  /// 节点名 → 国家码，只含新鲜记录。地区识别（标签 / 筛选 / 分组）统一从
  /// [proxyLandingCodesProvider] 取 —— store 的状态本身已经只含新鲜记录
  /// （build 时过滤 + 会话内新增的都是刚测的），这里不再重复一份同样语义
  /// 的变换。
}

final proxyExitStoreProvider =
    AsyncNotifierProvider<ProxyExitStore, Map<String, ProxyExitInfo>>(
      ProxyExitStore.new,
    );

/// 落地覆盖表（节点名 → 国家码）—— 筛选栏、页签列表、分组计划共用的**同一份**
/// 实测落地。单独提出来：三处都要「store → countryCode 映射」这同一变换，
/// 各写一遍早晚写出不一致。
final proxyLandingCodesProvider = Provider<Map<String, String>>((ref) {
  return ref
      .watch(
        proxyExitStoreProvider.select(
          (state) => state.value ?? const <String, ProxyExitInfo>{},
        ),
      )
      .map((key, value) => MapEntry(key, value.countryCode));
});

/// 「测落地」按钮背后的逻辑：经内核把一个 GET 从指定节点里发出去，拿回出口
/// IP；国家码由内核**本地**查随包 geoip 数据得出 —— 外部地理 API 有限流
/// （ip-api 免费版 45 req/min，自动化跑测延迟节奏必撞），本地分类零配额。
class ProxyExit extends Notifier<ProxyExitState> {
  static const _probeTimeoutMs = 10000;

  /// 自动批量测落地（跟在测延迟后面）的并发数。内核侧每个探测都是独立拨号，
  /// 开太大只会让节点并发带宽互相挤 —— 4 路已经能在两分钟内扫完两三百个节点。
  static const _batchConcurrency = 4;

  @override
  ProxyExitState build() => const ProxyExitState();

  Future<void> test(String proxyName) async {
    if (state.testing.contains(proxyName)) {
      return;
    }
    state = ProxyExitState(
      testing: {...state.testing, proxyName},
      results: state.results,
    );
    ProxyExitInfo? info;
    try {
      info = await _probe(proxyName);
    } catch (_) {
      info = null;
    }
    if (!ref.mounted) {
      return;
    }
    state = ProxyExitState(
      testing: {...state.testing}..remove(proxyName),
      results: {...state.results, proxyName: info},
    );
    // 手动单节点测与批测**同一口径**：成功的记录一并落库 —— 不然同一张卡片
    // 在「点了按钮」和「跑过批测」两条路里得到两种持久化结果。
    if (info != null && info.countryCode.isNotEmpty) {
      ref.read(proxyExitStoreProvider.notifier).record(proxyName, info);
    }
  }

  /// 是否有一轮批测还在跑。批测是重活（两三百节点、几分钟），定时任务与
  /// 「测延迟后自动批测」撞在同一个窗口时会重复探测 —— 后到的直接让路，
  /// 等下一轮补（新鲜记录机制保证不会漏测）。
  bool _batchRunning = false;

  /// 批量测落地：**跳过库里还有新鲜记录的节点**（重复测只是重复烧流量），
  /// 逐个完成后渐进刷新卡片并把结果落库。放在「测延迟」全部结束后由
  /// `ProxiesAction` 调起 —— 与延迟探测抢带宽没有意义。
  ///
  /// 蜂窝网络门控：每个探测都真的从节点里走一趟（几百字节请求 + TLS 握手），
  /// 两三百个节点一轮 1~3 MB，两头吃流量 —— 手机套餐和机场套餐。手机流量
  /// 下这一步整个跳过，等回 Wi-Fi 的下一轮测延迟再补（新鲜记录会跳过已测的）。
  /// 判不出网络状态就放行 —— 门控宁可失效也不拦住正常功能。手动单节点
  /// 「测落地」不走这里，用户点了就是明确意图，不该被拦。
  Future<void> testBatch(Set<String> proxyNames) async {
    if (proxyNames.isEmpty || _batchRunning) {
      return;
    }
    if (await _isMeteredNetwork()) {
      commonPrint.log(
        'Skip proxy exit batch: metered network',
        logLevel: LogLevel.info,
      );
      return;
    }
    // 等 store 的初始加载完成再取新鲜记录：刚启动时 store 还在 AsyncLoading，
    // 直接读 .value 拿到的是空表 —— 会把库里已有新鲜记录的节点全部重测一遍。
    final fresh = await ref.read(proxyExitStoreProvider.future);
    final queue = proxyNames
        .where((name) => !fresh.containsKey(name))
        .toList();
    if (queue.isEmpty) {
      return;
    }
    _batchRunning = true;
    try {
      final pool = TaskPool(_batchConcurrency);
      await Future.wait(queue.map((name) => pool.run(() => test(name))));
    } finally {
      _batchRunning = false;
    }
  }

  /// 只在「蜂窝在、且没有 Wi-Fi/以太网兜着」时算计费网络。桌面端通常是
  /// 以太网或 Wi-Fi，天然放行；VPN 开着时结果里会多一个 vpn 项，不影响判断。
  static Future<bool> _isMeteredNetwork() async {
    try {
      final results = await Connectivity().checkConnectivity();
      final unmetered = results.any(
        (r) =>
            r == ConnectivityResult.wifi || r == ConnectivityResult.ethernet,
      );
      return results.contains(ConnectivityResult.mobile) && !unmetered;
    } catch (_) {
      return false;
    }
  }

  Future<ProxyExitInfo?> _probe(String proxyName) async {
    final core = ref.read(coreHandlerProvider);
    final result = await core.requestProxyIP(
      proxyName: proxyName,
      timeoutMs: _probeTimeoutMs,
    );
    return ProxyExitInfo(
      countryCode: result.country,
      ip: result.ip,
      testedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }
}

final proxyExitProvider = NotifierProvider<ProxyExit, ProxyExitState>(
  ProxyExit.new,
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
