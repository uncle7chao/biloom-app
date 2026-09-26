import 'dart:convert';

import 'preferences.dart';
import 'proxy_chains.dart';

export 'proxy_chains.dart'
    show ProxyChain, decodeProxyChains, injectProxyChains, nextChainNumber;

/// 链式代理的持久化（shared_preferences）。
///
/// 链**不写进 profile 文件**（模型说明见 proxy_chains.dart）—— 这里就是链的
/// 唯一落点。SP 直存而不是 drift：链通常个位数条，整键重写的写放大可以接受
/// （对比落地记录那批两三百条才值得迁 drift）。
class ProxyChainStore {
  static const key = 'proxyChains';

  static Future<List<ProxyChain>> load() async {
    final prefs = await preferences.sharedPreferencesCompleter.future;
    return decodeProxyChains(prefs?.getString(key) ?? '');
  }

  static Future<void> save(List<ProxyChain> chains) async {
    final prefs = await preferences.sharedPreferencesCompleter.future;
    final raw = json.encode([
      for (final chain in chains) chain.toJson(),
    ]);
    await prefs?.setString(key, raw);
  }

  /// 新建一条链，返回**最终名字**。默认名按 链式代理1、链式代理2 … 自动编号
  /// （取已占用最大编号 +1，不回填空位）；自定义名原样使用，与既有链或目标
  /// 配置里的节点/组撞名时 -2 兜底 —— 撞名会让整份配置加载失败，这里必须挡。
  static Future<String> add({
    required int profileId,
    required String name,
    required bool autoNumber,
    required String defaultName,
    required String exitName,
    required Map<String, dynamic> exitNode,
    required String dialer,
    Map<String, dynamic>? dialerNode,
    Iterable<String> takenNames = const [],
  }) async {
    // 防御性拷贝：load() 理应返回可变列表（decodeProxyChains 有注释钉着），
    // 但这里要 add，多一层拷贝让 store 不再依赖上游的可变性承诺。
    final chains = [...await load()];
    var finalName = name;
    if (autoNumber) {
      final number = nextChainNumber(
        chains: chains,
        profileId: profileId,
        defaultName: defaultName,
      );
      finalName = '$defaultName$number';
    }
    final taken = {
      ...takenNames,
      for (final chain in chains) chain.name,
    };
    var suffix = 2;
    while (taken.contains(finalName)) {
      finalName = '$name-$suffix';
      suffix++;
    }
    chains.add(
      ProxyChain(
        profileId: profileId,
        name: finalName,
        exitName: exitName,
        exitNode: exitNode,
        dialer: dialer,
        dialerNode: dialerNode,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    await save(chains);
    return finalName;
  }

  /// 删除指定配置里名字命中的链，返回是否真的删了东西。
  ///
  /// 「删除节点」的两个入口（节点卡片右键、管理面板批量删）都先走这里改道：
  /// 链不在配置文件里，内核 removeProxyNodes 找不到它 —— 数据层删完重应用
  /// 才是正确路径。
  static Future<bool> removeNames({
    required int profileId,
    required Iterable<String> names,
  }) async {
    final targets = names.toSet();
    final chains = await load();
    final kept = chains
        .where((chain) => !(chain.profileId == profileId && targets.contains(chain.name)))
        .toList();
    if (kept.length == chains.length) {
      return false;
    }
    await save(kept);
    return true;
  }

  /// 某份配置下的全部链名 —— 删除链路改道、面板撞名检查共用。
  static Future<Set<String>> namesOfProfile(int profileId) async {
    return {
      for (final chain in await load())
        if (chain.profileId == profileId) chain.name,
    };
  }
}
