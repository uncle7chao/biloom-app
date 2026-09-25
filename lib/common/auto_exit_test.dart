import 'preferences.dart';

/// 「定时自动测落地」开关 —— 持久化（shared_preferences）。
///
/// 自动测落地每天跑一轮（跳过库里还有新鲜记录的节点，14 天内测过的不再测），
/// 让地区标注/筛选在长期使用中保持真实 —— 节点的落地会漂移，只靠「测延迟后
/// 顺带批测」的话，不常点测速的用户数据会越来越旧。
///
/// 默认开：每一轮只探测「没有新鲜记录」的节点，常态下每天只有零星几个待测，
/// 流量代价很小；关掉它只会让落地数据慢慢失真。
const kAutoExitTestEnabledKey = 'autoExitTestEnabled';

Future<bool> loadAutoExitTestEnabled() async {
  final prefs = await preferences.sharedPreferencesCompleter.future;
  return prefs?.getBool(kAutoExitTestEnabledKey) ?? true;
}

Future<void> saveAutoExitTestEnabled(bool value) async {
  final prefs = await preferences.sharedPreferencesCompleter.future;
  await prefs?.setBool(kAutoExitTestEnabledKey, value);
}
