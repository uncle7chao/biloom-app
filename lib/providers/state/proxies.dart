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
    // 没测过的才按名字认。watch 而不是 read —— 批量测落地时卡片要渐进刷新。
    final stored =
        ref.watch(proxyExitStoreProvider).value?[proxy.name];
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

/// 落地结果的**持久层**（落库）。
///
/// 为什么放 shared_preferences 而不是 drift：它是一个纯 KV（节点名 → 出口），
/// 不需要查询、关联和迁移；而给 drift 加表就得跑 build_runner，代码生成器在
/// 环境故障期起不来。一个 JSON 键 + 启动时裁剪过期项，就够这一层用的了。
///
/// 为什么只存成功：失败多半是「节点此刻不通」这种暂时态，把它存下来会让
/// 一个昨天还好的节点今天被标成「测不出」。失败让会话态去表达就够了。
class ProxyExitStore extends AsyncNotifier<Map<String, ProxyExitInfo>> {
  static const _key = 'proxyExitInfo';

  /// 落地会漂移（服务端负载均衡让同一节点不同时刻从不同出口出去），
  /// 超过这个时间的记录不再当作地区依据 —— 过期数据比没数据更糟。
  static const freshness = Duration(days: 14);

  Timer? _saveDebounce;

  @override
  Future<Map<String, ProxyExitInfo>> build() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      final prefs = await preferences.sharedPreferencesCompleter.future;
      final raw = prefs?.getString(_key);
      if (raw == null || raw.isEmpty) {
        return const {};
      }
      final map = json.decode(raw) as Map<String, dynamic>;
      final result = <String, ProxyExitInfo>{};
      for (final entry in map.entries) {
        if (entry.value is! Map<String, dynamic>) {
          continue;
        }
        try {
          final info = ProxyExitInfo.fromJson(
            entry.value as Map<String, dynamic>,
          );
          if (now - info.testedAt <= freshness.inMilliseconds) {
            result[entry.key] = info;
          }
        } catch (_) {
          // 单条坏了只丢那条，不让一份损坏的 JSON 把整层记忆清空。
        }
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  /// 记录一次成功探测。内存立即生效（卡片渐进刷新），写盘去抖 ——
  /// 全量测一轮是两三百个节点，一个节点刷一次盘毫无必要。
  void record(String proxyName, ProxyExitInfo info) {
    if (info.countryCode.isEmpty) {
      // 国家码都认不出的记录不配入库：地区层拿它没有任何用处。
      return;
    }
    final current = Map<String, ProxyExitInfo>.from(state.value ?? const {});
    current[proxyName] = info;
    state = AsyncData(current);
    final toSave = current;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 2), () => _save(toSave));
  }

  /// 节点名 → 国家码，只含新鲜记录。地区识别（标签 / 筛选 / 分组）统一从这里取。
  Map<String, String> freshCountryCodes() {
    final value = state.value;
    if (value == null || value.isEmpty) {
      return const {};
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    return {
      for (final entry in value.entries)
        if (now - entry.value.testedAt <= freshness.inMilliseconds)
          entry.key: entry.value.countryCode,
    };
  }

  Future<void> _save(Map<String, ProxyExitInfo> data) async {
    try {
      final prefs = await preferences.sharedPreferencesCompleter.future;
      await prefs?.setString(
        _key,
        json.encode({
          for (final entry in data.entries) entry.key: entry.value.toJson(),
        }),
      );
    } catch (_) {
      // 写盘失败不影响本次会话 —— 内存里那份还在，下次探测会再试。
    }
  }
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
  }

  /// 批量测落地：**跳过库里还有新鲜记录的节点**（重复测只是重复烧流量），
  /// 逐个完成后渐进刷新卡片并把结果落库。放在「测延迟」全部结束后由
  /// `ProxiesAction` 调起 —— 与延迟探测抢带宽没有意义。
  Future<void> testBatch(Set<String> proxyNames) async {
    if (proxyNames.isEmpty) {
      return;
    }
    final fresh = ref.read(proxyExitStoreProvider).value ?? const {};
    final queue = proxyNames
        .where((name) => !fresh.containsKey(name))
        .toList();
    if (queue.isEmpty) {
      return;
    }
    final pool = TaskPool(_batchConcurrency);
    await Future.wait(queue.map((name) => pool.run(() => _testAndStore(name))));
  }

  Future<void> _testAndStore(String proxyName) async {
    await test(proxyName);
    final info = state.results[proxyName];
    if (info != null && info.countryCode.isNotEmpty) {
      ref.read(proxyExitStoreProvider.notifier).record(proxyName, info);
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
