import 'dart:convert';

/// 链式代理数据层 —— 纯模型与运行时注入（零 Flutter 依赖，可独立测试）。
///
/// **模型（2026-09-25 定稿）**：链式代理**不写进任何 profile 文件**。它们存在
/// shared_preferences 里（见 proxy_chains_store.dart），组装运行时配置时注入：
/// 一个链 = 一个代理级 `dialer-proxy` 条目（参数复制自出口、名字独立），外加一个
/// 固定的「链式代理」select 分组把所有链收在一起 —— 代理页里就是一个**永远
/// 显性存在**的页签，固定排在「自动选择」后面。
///
/// 为什么不落盘到 profile：链是用户在 BiLoom 里加的一层，不是订阅的一部分。
/// 写进文件的话，订阅一更新就被冲掉；不写的话，「原始节点的配置」保持纯净，
/// 删除也只是删一条记录。代价是注入时拿不到「最新」的出口参数 —— 所以链上
/// 存一份出口参数快照，注入时优先用配置里的实时参数（订阅更新自动跟随），
/// 实时参数拿不到（节点被删/换名）再退快照。
///
/// 没有有效链时不注入「链式代理」分组：用户没建链时不需要一个空页签/空卡片
/// 占位置；分组只在该配置至少有一条有效链时才出现，链删光后页签自动消失。

/// 一条链式代理。
class ProxyChain {
  const ProxyChain({
    required this.profileId,
    required this.name,
    required this.exitName,
    required this.exitNode,
    required this.dialer,
    this.dialerNode,
    required this.createdAt,
  });

  /// 链归属的配置。链的出口/前置都是从这份配置的候选里挑的，注入也只发生
  /// 在这份配置的运行时配置里。
  final int profileId;

  /// 链节点名。默认名「链式代理」自动编号（链式代理1、链式代理2 …），
  /// 自定义名原样使用 —— 名字在创建时就已保证与配置及既有链不撞。
  final String name;

  /// 出口节点名（展示与实时解析用）。
  final String exitName;

  /// 出口节点的完整参数快照。实时参数可用时它只是兜底，但必须存：
  /// 订阅更新把出口删了的话，没有快照的链就彻底失效了。
  final Map<String, dynamic> exitNode;

  /// 前置名 —— 节点或策略组。
  final String dialer;

  /// 前置是**其他配置的节点**时的参数快照；前置是本配置的节点或策略组时为 null。
  /// 本配置的节点注入时按名实时解析（比快照新鲜）；策略组天然在配置里。
  final Map<String, dynamic>? dialerNode;

  final int createdAt;

  Map<String, dynamic> toJson() => {
    'profileId': profileId,
    'name': name,
    'exitName': exitName,
    'exitNode': exitNode,
    'dialer': dialer,
    if (dialerNode != null) 'dialerNode': dialerNode,
    'createdAt': createdAt,
  };

  static ProxyChain? fromJson(Map<String, dynamic> json) {
    final exitNode = json['exitNode'];
    if (exitNode is! Map) return null;
    final name = json['name'];
    final dialer = json['dialer'];
    if (name is! String || dialer is! String) return null;
    final dialerNode = json['dialerNode'];
    return ProxyChain(
      profileId: json['profileId'] is int ? json['profileId'] as int : 0,
      name: name,
      exitName: json['exitName'] is String
          ? json['exitName'] as String
          : name,
      exitNode: exitNode.cast<String, dynamic>(),
      dialer: dialer,
      dialerNode: dialerNode is Map ? dialerNode.cast<String, dynamic>() : null,
      createdAt: json['createdAt'] is int
          ? json['createdAt'] as int
          : 0,
    );
  }

  ProxyChain copyWith({String? name}) => ProxyChain(
    profileId: profileId,
    name: name ?? this.name,
    exitName: exitName,
    exitNode: exitNode,
    dialer: dialer,
    dialerNode: dialerNode,
    createdAt: createdAt,
  );
}

ProxyChain? _chainFromJson(Object? value) {
  if (value is! Map) return null;
  try {
    return ProxyChain.fromJson(Map<String, dynamic>.from(value));
  } catch (_) {
    return null;
  }
}

/// SP 存储的 JSON 文本 → 记录列表。坏的条目跳过，坏的整体当空表 ——
/// 链丢了顶多要重建，不能让它把配置组装拖垮。
/// ⛔ 返回值必须是**可变列表**（不能用 const []）：ProxyChainStore.add 拿到
/// 后直接追加，const 列表会抛「Cannot add to an unmodifiable list」——
/// 首次建链（还没有任何记录）必崩，2026-09-26 用户实测踩过。
List<ProxyChain> decodeProxyChains(String raw) {
  if (raw.isEmpty) return <ProxyChain>[];
  final Object? decoded;
  try {
    decoded = json.decode(raw);
  } catch (_) {
    return <ProxyChain>[];
  }
  if (decoded is! List) return <ProxyChain>[];
  return decoded
      .map(_chainFromJson)
      .whereType<ProxyChain>()
      .toList();
}

/// 给默认名取下一个编号：取已占用最大编号 +1，不回填空位 —— 编号与创建
/// 顺序保持一致，删掉中间某条后新链接着最大编号往后排。
int nextChainNumber({
  required Iterable<ProxyChain> chains,
  required int profileId,
  required String defaultName,
}) {
  final prefix = RegExp(
    '^${RegExp.escape(defaultName)}(\\d+)\$',
  );
  var max = 0;
  for (final chain in chains) {
    if (chain.profileId != profileId) continue;
    final match = prefix.firstMatch(chain.name);
    if (match != null) {
      final value = int.tryParse(match.group(1)!);
      if (value != null && value > max) max = value;
    }
  }
  return max + 1;
}

/// 注入链式代理到运行时配置 —— [getProfile] 组装 configMap 时的最后一步之一。
///
/// [chains] 必须已经是**这一份配置**的链（调用方按 profileId 过滤）。
/// [groupName] 是「链式代理」页签名。链式代理命名空间是**专属**的：配置里
/// 名字落在「[groupName]」「[groupName]N」「[groupName]-N」模式内的节点与组
/// 一律视为旧模型（把链写进配置文件的时代）残留，注入前先清掉 —— 否则残留组
/// 会占住组名，让注入的组被迫改名，页签上就多出一个「链式代理-2」。
/// [autoGroupName] / [selectorGroupName] 是页签插入位置的锚（自动选择 / 节点选择，
/// 与内核 subscription_defaults.go 的常量同名）—— 都找不到就把组追加到末尾。
///
/// 返回 `(groupName: 实际组名, chainNames: 成功注入的链名)` —— 自定义覆写模式
/// 会在后面整体替换 proxy-groups，调用方要拿这份信息把组重新补进覆写列表。
///
/// 规则：
/// 1. **残留清理先行**：模式匹配的节点/组/组员引用/规则引用全部移除（组员被清空
///    的组补 `[DIRECT]` 兜底，不然整份配置加载失败）。
/// 2. 链节点参数**优先实时解析**（配置里有同名出口就用配置里的，订阅更新自动
///    跟随），解析不到退快照；快照里残留的 `dialer-proxy` 一律剥掉 —— 链的前置
///    以本条记录为准，继承出口的旧链是悬空引用。
/// 3. 前置是外部配置的节点（有 [ProxyChain.dialerNode] 快照）且配置里没有这个名字
///    时，先注入前置节点本体（同样剥掉它自己的 dialer-proxy，那在它的配置里才有
///    意义）。
/// 4. 前置两头落空（比如订阅更新把前置节点删了）→ 跳过该链：引用悬空会让整份
///    配置加载失败。链名与**非残留**的配置节点/组撞名（用户自己起的名）也跳过 ——
///    改名会让选中态记忆失效，跳过是最不意外的降级。
/// 5. **分组只在至少有一条有效链时注入**：没有有效链（一条都没有 / 全部被跳过）
///    时不注入空组，「链式代理」页签与卡片自然隐藏；注入时插入位置固定在
///    「自动选择」后面，成员是全部有效链名。
({String groupName, List<String> chainNames}) injectProxyChains(
  final Map<String, dynamic> rawConfig, {
  required List<ProxyChain> chains,
  required String groupName,
  required String autoGroupName,
  required String selectorGroupName,
}) {
  final proxies = rawConfig['proxies'];
  final proxyList = proxies is List
      ? proxies
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
      : <Map<String, dynamic>>[];
  final groups = rawConfig['proxy-groups'];
  final groupList = groups is List
      ? groups
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
      : <Map<String, dynamic>>[];

  String nameOf(Map<String, dynamic> node) =>
      node['name'] is String ? node['name'] as String : '';

  // ---- 规则 1：旧模型残留清理先行 ----
  //
  // 「链式代理」「链式代理1」「链式代理-2」这些名字属于链式代理的专属命名空间：
  // 出现在配置文件里只可能是旧模型（把链落盘的时代）留下的残留。不清掉的话，
  // 残留组占住组名，注入组被迫让位成「链式代理-2」，页签栏就多出一个假页签。
  final residuePattern = RegExp(
    '^${RegExp.escape(groupName)}(?:-\\d+|\\d+)?\$',
  );
  final residueNames = <String>{
    for (final node in proxyList)
      if (residuePattern.hasMatch(nameOf(node))) nameOf(node),
    for (final group in groupList)
      if (residuePattern.hasMatch(
        group['name'] is String ? group['name'] as String : '',
      ))
        group['name'] as String,
  };
  if (residueNames.isNotEmpty) {
    proxyList.removeWhere((node) => residueNames.contains(nameOf(node)));
    groupList.removeWhere(
      (group) => residueNames.contains(
        group['name'] is String ? group['name'] as String : '',
      ),
    );
    // 悬空引用清理：其他组的成员列表、规则指向的被删名字 —— 两者留一个都会
    // 让整份配置加载失败，比残留本身严重得多。
    for (final group in groupList) {
      final members = group['proxies'];
      if (members is List && members.any((m) => residueNames.contains(m))) {
        final kept = members.where((m) => !residueNames.contains(m)).toList();
        group['proxies'] = kept.isNotEmpty ? kept : <String>['DIRECT'];
      }
    }
    final rules = rawConfig['rules'];
    if (rules is List) {
      bool ruleTargetsResidue(Object rule) {
        if (rule is! String) return false;
        final index = rule.lastIndexOf(',');
        if (index < 0) return false;
        return residueNames.contains(rule.substring(index + 1).trim());
      }

      rawConfig['rules'] = rules.where((rule) => !ruleTargetsResidue(rule)).toList();
    }
  }

  // 节点与组共用同一个命名空间，前置可以是其中任何一种 —— 都算「存在」。
  final existingNames = <String>{
    for (final node in proxyList) nameOf(node),
    for (final group in groupList)
      group['name'] is String ? group['name'] as String : '',
  };

  /// 实时参数优先、快照兜底地解析一个节点参数；剥掉残留的 dialer-proxy。
  Map<String, dynamic>? resolveNode(String name, Map<String, dynamic>? snapshot) {
    for (final node in proxyList) {
      if (nameOf(node) == name) {
        return Map<String, dynamic>.from(node)..remove('dialer-proxy');
      }
    }
    if (snapshot == null) return null;
    return Map<String, dynamic>.from(snapshot)..remove('dialer-proxy');
  }

  final chainNames = <String>[];
  for (final chain in chains) {
    if (existingNames.contains(chain.name)) {
      continue; // 规则 3：撞名跳过，绝不写坏配置。
    }
    // 前置必须真实存在：本配置的节点/组按名即可；外部节点靠快照注入。
    // 两头都落空（比如订阅更新把前置节点删了）—— 这条链的引用会悬空，
    // 整份配置加载失败的代价远大于少一条链，跳过。
    if (!existingNames.contains(chain.dialer)) {
      final dialerNode = resolveNode(chain.dialer, chain.dialerNode);
      if (dialerNode == null) {
        continue;
      }
      proxyList.add(dialerNode);
      existingNames.add(nameOf(dialerNode));
    }
    final exitParams = resolveNode(chain.exitName, chain.exitNode);
    if (exitParams == null) {
      continue; // 出口实时与快照都拿不到，链没有参数可用。
    }
    exitParams['name'] = chain.name;
    exitParams['dialer-proxy'] = chain.dialer;
    proxyList.add(exitParams);
    existingNames.add(chain.name);
    chainNames.add(chain.name);
  }
  rawConfig['proxies'] = proxyList;

  // 没有有效链时不需要注入空组：用户没建链时「链式代理」页签/卡片不应显示，
  // 也不必担心空成员导致配置加载失败（直接不注入即可）。但残留清理的结果必须
  // 写回 rawConfig，否则旧模型残留会留在配置里。
  if (chainNames.isEmpty) {
    rawConfig['proxy-groups'] = groupList;
    return (groupName: '', chainNames: const []);
  }

  // 分组名与节点名/组名共用命名空间。残留清理已把专属命名空间腾空，正常路径
  // 下 [groupName] 必然可用；这个让位循环只是最后一道防线 —— 万一用户给普通
  // 节点/组起了一模一样的名字（清理模式管不到的形态），让位好过写坏配置。
  var realGroupName = groupName;
  var suffix = 2;
  while (existingNames.contains(realGroupName)) {
    realGroupName = '$groupName-$suffix';
    suffix++;
  }

  final groupEntry = <String, dynamic>{
    'name': realGroupName,
    'type': 'select',
    'proxies': chainNames.isNotEmpty ? chainNames : <String>['DIRECT'],
  };

  // 页签位置：固定在「自动选择」后面；没有它退「节点选择」后面；都没有
  // （服务商自己设计分组的订阅）就追加到末尾。
  var insertAt = groupList.indexWhere(
    (group) => group['name'] == autoGroupName,
  );
  if (insertAt < 0) {
    insertAt = groupList.indexWhere(
      (group) => group['name'] == selectorGroupName,
    );
  }
  if (insertAt < 0) {
    groupList.add(groupEntry);
  } else {
    groupList.insert(insertAt + 1, groupEntry);
  }
  rawConfig['proxy-groups'] = groupList;
  return (groupName: realGroupName, chainNames: chainNames);
}
