import 'dart:convert';

/// 链式代理数据层 —— 纯模型与运行时注入（零 Flutter 依赖，可独立测试）。
///
/// **模型（2026-09-27 全局索引定稿）**：链式代理**不写进任何 profile 文件**。
/// 它们存在 shared_preferences 里（见 proxy_chains_store.dart），组装运行时
/// 配置时注入：一个链 = 一个代理级 `dialer-proxy` 条目（参数复制自出口、名字
/// 独立），外加一个固定的「链式代理」select 分组把所有链收在一起 —— 代理页里
/// 就是一个**永远显性存在**的页签，固定排在「自动选择」后面。
///
/// **链是全局索引，不属于任何配置**（2026-09-27 用户拍板）：链只是一份
/// 「出口 + 前置」的引用清单，规划流量走向而已 —— 不复制节点、不改节点属性
/// 与归属。任何配置下「链式代理」页签都显示全部链；运行时把链引用的节点定义
/// 装配进当前配置（当前配置里按名实时解析，解析不到退链上存的参数快照）。
///
/// 为什么不落盘到 profile：链是用户在 BiLoom 里加的一层，不是订阅的一部分。
/// 写进文件的话，订阅一更新就被冲掉；不写的话，「原始节点的配置」保持纯净，
/// 删除也只是删一条记录。代价是注入时拿不到「最新」的出口参数 —— 所以链上
/// 存一份出口参数快照，注入时优先用配置里的实时参数（订阅更新自动跟随），
/// 实时参数拿不到（节点被删/换名）再退快照。
///
/// 「链式代理」分组**常驻注入**：不管当前配置有没有链、哪怕一条链都没建过，
/// 页签都固定显示（没有链时分组成员是 [DIRECT] 占位）。

/// 链式代理的**配置层固定名**（分组名与默认链名共用）。
///
/// ⛔ 刻意不走 l10n：这个名字同时是「残留清理的模式锚点」与「自动编号的
/// 基础名」。跟着界面语言走的话，用户切一次语言，上一语言下写的链名/残留
/// 就再也匹配不上了 —— 重新编号、残留清不掉、页签名凭空变化。界面文案的
/// 本地化交给 l10n 词条（输入框占位、按钮等），配置里永远用这个名字。
/// 与「自动选择」「节点选择」两个硬编码锚点名同一处理。
const kProxyChainGroupName = '链式代理';

/// 一条链式代理 —— 全局索引记录，**没有配置归属**。
class ProxyChain {
  const ProxyChain({
    required this.name,
    required this.exitName,
    required this.exitNode,
    required this.dialer,
    this.dialerNode,
    required this.createdAt,
  });

  /// 链节点名。默认名「链式代理」自动编号（链式代理1、链式代理2 …），
  /// 自定义名原样使用 —— 名字在创建时就已保证与各配置及既有链不撞。
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
    // 旧记录里的 profileId（链曾经绑定创建时的配置）直接忽略 —— 全局索引
    // 模型下没有归属概念，快照已足够撑起注入。
    return ProxyChain(
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
/// 顺序保持一致，删掉中间某条后新链接着最大编号往后排。编号是**全局**的
/// （链没有配置归属，所有链共用一个编号序列）。
int nextChainNumber({
  required Iterable<ProxyChain> chains,
  required String defaultName,
}) {
  final prefix = RegExp(
    '^${RegExp.escape(defaultName)}(\\d+)\$',
  );
  var max = 0;
  for (final chain in chains) {
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
/// [chains] 是**全部**链（全局索引模型：链不属于任何配置，所有链在每份配置
/// 的运行时里都尝试装配）。[groupName] 是「链式代理」页签名。链式代理命名
/// 空间是**专属**的：配置里名字落在「[groupName]」「[groupName]N」「[groupName]-N」
/// 模式内的节点与组一律视为旧模型（把链写进配置文件的时代）残留，注入前先
/// 清掉 —— 否则残留组会占住组名，让注入的组被迫改名，页签上就多出一个
/// 「链式代理-2」。[autoGroupName] / [selectorGroupName] 是页签插入位置的锚
/// （自动选择 / 节点选择，与内核 subscription_defaults.go 的常量同名）——
/// 都找不到就把组追加到末尾。
///
/// 返回 `(groupName: 实际组名, chainNames: 成功注入的链名, injectedDialerNames:
/// 快照注入的前置节点名)` —— 自定义覆写模式会在后面整体替换 proxy-groups，
/// 调用方要拿这份信息把组重新补进覆写列表；GLOBAL 页签的展示层过滤（代理页
/// 不出现链的东西）要的是 chainNames + injectedDialerNames 的并集。
///
/// 规则：
/// 1. **残留清理先行**：模式匹配的节点/组/组员引用/规则引用全部移除（组员被清空
///    的组补 `[DIRECT]` 兜底，不然整份配置加载失败）。
/// 2. 链节点参数**优先实时解析**（当前配置里有同名出口就用配置里的，订阅更新
///    自动跟随），解析不到退快照；快照里残留的 `dialer-proxy` 一律剥掉 —— 链的
///    前置以本条记录为准，继承出口的旧链是悬空引用。
/// 3. 前置是其他配置的节点（有 [ProxyChain.dialerNode] 快照）且当前配置里没有
///    这个名字时，先注入前置节点本体（同样剥掉它自己的 dialer-proxy，那在它的
///    配置里才有意义）。
/// 4. 前置两头落空（比如订阅更新把前置节点删了）→ 跳过该链：引用悬空会让整份
///    配置加载失败。链名与**非残留**的配置节点/组撞名（用户自己起的名）也跳过
///    —— 改名会让选中态记忆失效，跳过是最不意外的降级。
/// 5. **分组常驻注入**：不管有没有有效链，「链式代理」页签都存在（全局页签，
///    用户拍板：任何配置、任何时刻都显示）。有链时成员是全部有效链名；没有时
///    成员是 `[DIRECT]` 占位（组必须非空，空成员整份配置加载失败）。注入位置
///    固定在「自动选择」后面。
/// 6. [finalGroupNames]（可选）：调用方知道**最终生效**的组名单时传入（自定义
///    覆写模式会整体替换 proxy-groups，rawConfig 里的组活不到最后）。组前置的
///    有效性按它判；不传则按 rawConfig 当前的组列表判。
({String groupName, List<String> chainNames, List<String> injectedDialerNames})
injectProxyChains(
  final Map<String, dynamic> rawConfig, {
  required List<ProxyChain> chains,
  required String groupName,
  required String autoGroupName,
  required String selectorGroupName,
  Set<String>? finalGroupNames,
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
  // 规则形态两种：TYPE,payload,target 与 TYPE,payload,target,no-resolve
  // （no-resolve/src 是尾参，不是目标）。lastIndexOf(',') 会把尾参当成
  // 目标名漏删 —— 悬空规则会让整份配置加载失败。
  const ruleParams = {'no-resolve', 'src'};
  String? ruleTargetOf(Object rule) {
    if (rule is! String) return null;
    final parts = rule.split(',');
    if (parts.length < 2) return null;
    final last = parts.last.trim();
    if (parts.length >= 3 && ruleParams.contains(last.toLowerCase())) {
      return parts[parts.length - 2].trim();
    }
    return last;
  }

  final residueNames = <String>{
    for (final node in proxyList)
      if (residuePattern.hasMatch(nameOf(node))) nameOf(node),
    for (final group in groupList)
      if (residuePattern.hasMatch(
        group['name'] is String ? group['name'] as String : '',
      ))
        group['name'] as String,
  };
  // 残留名只出现在规则里（节点/组已经不在了）也要收进来 —— 规则指向专属
  // 命名空间里不存在的名字，配置同样加载失败，一并是旧模型残留。
  final rulesForCollect = rawConfig['rules'];
  if (rulesForCollect is List) {
    for (final rule in rulesForCollect) {
      final target = ruleTargetOf(rule);
      if (target != null && residuePattern.hasMatch(target)) {
        residueNames.add(target);
      }
    }
  }
  final subRulesForCollect = rawConfig['sub-rules'];
  if (subRulesForCollect is Map) {
    for (final list in subRulesForCollect.values) {
      if (list is! List) continue;
      for (final rule in list) {
        final target = ruleTargetOf(rule);
        if (target != null && residuePattern.hasMatch(target)) {
          residueNames.add(target);
        }
      }
    }
  }
  if (residueNames.isNotEmpty) {
    // 保守清理（#不误伤）：命名空间撞名不该变成数据丢失。用户完全可能给
    // 自己的节点/组起「链式代理」这类名字 —— 清理只针对旧模型的**形态特征**：
    // - 链节点必带 dialer-proxy（旧 addProxyChain 写的就是这种）；
    // - 残留组必是 select 且成员全是链名/DIRECT（链组或空组兜底形态）。
    // 不满足特征的同名条目原样保留；store 层撞名时对**链**改名（-2 兜底），
    // 两头合起来才是完整的「不删用户数据」策略。
    proxyList.removeWhere((node) {
      if (!residueNames.contains(nameOf(node))) {
        return false;
      }
      return node.containsKey('dialer-proxy');
    });
    groupList.removeWhere((group) {
      final name = group['name'] is String ? group['name'] as String : '';
      if (!residueNames.contains(name)) {
        return false;
      }
      if (group['type'] != 'select') {
        return false;
      }
      final members = group['proxies'];
      if (members is! List || members.isEmpty) {
        return true;
      }
      return members.every(
        (m) => m == 'DIRECT' || (m is String && residuePattern.hasMatch(m)),
      );
    });
    // 悬空引用清理：其他组的成员列表、规则指向的被删名字 —— 两者留一个都会
    // 让整份配置加载失败，比残留本身严重得多。
    for (final group in groupList) {
      final members = group['proxies'];
      if (members is List && members.any((m) => residueNames.contains(m))) {
        final kept = members.where((m) => !residueNames.contains(m)).toList();
        group['proxies'] = kept.isNotEmpty ? kept : <String>['DIRECT'];
      }
    }
    // 规则清理（形态与目标识别见上方 ruleTargetOf）。
    final rules = rawConfig['rules'];
    if (rules is List) {
      rawConfig['rules'] = rules
          .where((rule) => !residueNames.contains(ruleTargetOf(rule)))
          .toList();
    }
    // sub-rules 是 Map<名, List<规则>>，里面的规则同样可能指向残留名。
    final subRules = rawConfig['sub-rules'];
    if (subRules is Map) {
      for (final key in subRules.keys.toList()) {
        final list = subRules[key];
        if (list is List) {
          subRules[key] = list
              .where((rule) => !residueNames.contains(ruleTargetOf(rule)))
              .toList();
        }
      }
    }
  }

  // 节点与组共用同一个命名空间，前置可以是其中任何一种 —— 都算「存在」。
  // 但自定义覆写模式下 rawConfig 的组活不到最后（整体替换），组前置要按
  // [finalGroupNames] 判；节点不受覆写影响，始终按配置本体验。
  final nodeNames = {for (final node in proxyList) nameOf(node)};
  final groupNames = {
    for (final group in groupList)
      group['name'] is String ? group['name'] as String : '',
  };
  final existingNames = {...nodeNames, ...groupNames};

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
  final injectedDialerNames = <String>[];
  for (final chain in chains) {
    if (existingNames.contains(chain.name)) {
      continue; // 规则 3：撞名跳过，绝不写坏配置。
    }
    // 前置必须真实存在：本配置的节点按名即可；组前置在自定义覆写模式下按
    // 最终生效的组名单判（覆写会整体替换 proxy-groups）；外部节点靠快照注入。
    // 都落空（比如订阅更新把前置节点删了）—— 这条链的引用会悬空，整份配置
    // 加载失败的代价远大于少一条链，跳过。
    final dialerAsGroupValid = finalGroupNames != null
        ? finalGroupNames.contains(chain.dialer)
        : groupNames.contains(chain.dialer);
    if (!nodeNames.contains(chain.dialer) && !dialerAsGroupValid) {
      final dialerNode = resolveNode(chain.dialer, chain.dialerNode);
      if (dialerNode == null) {
        continue;
      }
      proxyList.add(dialerNode);
      nodeNames.add(nameOf(dialerNode));
      existingNames.add(nameOf(dialerNode));
      injectedDialerNames.add(nameOf(dialerNode));
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

  // 分组**常驻注入**（全局页签，2026-09-27 用户拍板）：没有有效链时成员是
  // [DIRECT] 占位 —— 组必须非空，空成员整份配置加载失败；有链后成员换成链名，
  // DIRECT 自然退出。残留清理的结果同样必须写回 rawConfig，否则旧模型残留会
  // 留在配置里。
  //
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
  return (
    groupName: realGroupName,
    chainNames: chainNames,
    injectedDialerNames: injectedDialerNames,
  );
}
