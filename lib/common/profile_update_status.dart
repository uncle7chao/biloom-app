import 'dart:convert';

import 'preferences.dart';

/// 订阅更新失败记录 —— 持久化（shared_preferences）。
///
/// 自动更新在后台静默跑，失败以前只写一行日志：订阅过期/被墙/限流这种
/// 「不是今天才坏、是慢慢坏的」问题，用户可能几周都发现不了。这里把每个
/// 配置最近一次失败存下来（成功更新即清除），配置卡片据此显示红色提示行。
///
/// 条目数 = 配置数（个位数），整键重写的写放大可以接受，不值得为此上 drift。
class ProfileUpdateStatus {
  const ProfileUpdateStatus({required this.error, required this.at});

  /// 异常的面向用户描述（与手动更新弹窗同源）。
  final String error;

  /// 失败时刻的毫秒时间戳。角标 tooltip 带上它，用户能分清「刚坏的」和
  /// 「早就坏的」。
  final int at;

  Map<String, dynamic> toJson() => {'error': error, 'at': at};

  factory ProfileUpdateStatus.fromJson(Map<String, dynamic> json) =>
      ProfileUpdateStatus(
        error: json['error'] as String? ?? '',
        at: (json['at'] as num?)?.toInt() ?? 0,
      );
}

const kProfileUpdateStatusKey = 'profileUpdateStatus';

class ProfileUpdateStatusStore {
  static Future<Map<String, ProfileUpdateStatus>> load() async {
    final prefs = await preferences.sharedPreferencesCompleter.future;
    final raw = prefs?.getString(kProfileUpdateStatusKey);
    if (raw == null || raw.isEmpty) {
      return {};
    }
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) {
        return {};
      }
      final result = <String, ProfileUpdateStatus>{};
      decoded.forEach((key, value) {
        if (key is String && value is Map) {
          result[key] = ProfileUpdateStatus.fromJson(
            Map<String, dynamic>.from(value),
          );
        }
      });
      return result;
    } catch (_) {
      // 整份 JSON 坏了就当没有失败记录：这层只影响提示，不该挡功能。
      return {};
    }
  }

  static Future<void> save(Map<String, ProfileUpdateStatus> statuses) async {
    final prefs = await preferences.sharedPreferencesCompleter.future;
    final raw = json.encode({
      for (final entry in statuses.entries) entry.key: entry.value.toJson(),
    });
    await prefs?.setString(kProfileUpdateStatusKey, raw);
  }
}
