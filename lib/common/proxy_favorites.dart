import 'dart:convert';

import 'preferences.dart';

/// 节点收藏 —— 持久化（shared_preferences）。
///
/// 收藏按**配置分开记**（profileId → 名字列表）：同一个名字在两份配置里是
/// 两个不同的节点，跨配置共享收藏只会造成「置顶了一堆不存在的节点」。
/// 名字列表而不是 Set 落盘：JSON 序列化顺带保序，置顶顺序 = 收藏顺序。
///
/// 条目量级（几十个名字），整键重写的写放大可以接受。
const kProxyFavoritesKey = 'proxyFavorites';

class ProxyFavoritesStore {
  static Future<Map<String, List<String>>> load() async {
    final prefs = await preferences.sharedPreferencesCompleter.future;
    final raw = prefs?.getString(kProxyFavoritesKey);
    if (raw == null || raw.isEmpty) {
      return {};
    }
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) {
        return {};
      }
      final result = <String, List<String>>{};
      decoded.forEach((key, value) {
        if (key is String && value is List) {
          result[key] = value.whereType<String>().toList();
        }
      });
      return result;
    } catch (_) {
      // 坏数据当没有收藏，不影响其它功能。
      return {};
    }
  }

  static Future<void> save(Map<String, List<String>> favorites) async {
    final prefs = await preferences.sharedPreferencesCompleter.future;
    final raw = json.encode(favorites);
    await prefs?.setString(kProxyFavoritesKey, raw);
  }
}
