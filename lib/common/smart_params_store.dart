import 'dart:convert';

import 'preferences.dart';
import 'smart_params.dart';

/// 智能抗检测参数层 —— 持久化与轮换触发（shared_preferences）。
///
/// 纯逻辑在 smart_params.dart（零依赖，可独立测试）；这里只做三件事：
/// 覆盖记录的读写、测延迟成败时的轮换推进/钉住、开关的存取。
///
/// SP 直存而不是 drift：批量轮换一轮只写几个条目，整键重写的写放大可以
/// 接受（对比落地记录那批两三百条才值得迁 drift）。
class SmartFingerprintStore {
  static Future<Map<String, FingerprintRecord>> load() async {
    final prefs = await preferences.sharedPreferencesCompleter.future;
    final raw = prefs?.getString(kFingerprintOverridesKey);
    if (raw == null || raw.isEmpty) {
      return {};
    }
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) {
        return {};
      }
      final result = <String, FingerprintRecord>{};
      decoded.forEach((key, value) {
        if (key is String && value is Map) {
          final record = FingerprintRecord.fromJson(
            Map<String, dynamic>.from(value),
          );
          if (record != null) {
            result[key] = record;
          }
        }
      });
      return result;
    } catch (_) {
      // 整份 JSON 坏了就当没有覆盖记录，回退到默认填充，不影响连通性。
      return {};
    }
  }

  static Future<void> save(Map<String, FingerprintRecord> overrides) async {
    final prefs = await preferences.sharedPreferencesCompleter.future;
    final raw = json.encode({
      for (final entry in overrides.entries) entry.key: entry.value.toJson(),
    });
    await prefs?.setString(kFingerprintOverridesKey, raw);
  }

  /// 测延迟失败时把节点推进到池中下一组指纹。返回是否真的轮换了。
  ///
  /// 三重护栏：只动被本层填过的节点；冷却期内不重复推进；池子用尽就停
  /// （全池轮完还失败，节点多半是真挂了，不是指纹的事）。
  static Future<bool> rotateOnFailure(String proxyName) async {
    if (!smartFilledProxyNames.contains(proxyName)) {
      return false;
    }
    final overrides = await load();
    final record = overrides[proxyName];
    final now = DateTime.now().millisecondsSinceEpoch;
    if (record != null) {
      if (now - record.rotatedAt < rotateCooldown.inMilliseconds) {
        return false;
      }
      final index = kFingerprintPool.indexOf(record.fingerprint);
      if (index < 0 || index >= kFingerprintPool.length - 1) {
        return false;
      }
      overrides[proxyName] = FingerprintRecord(
        fingerprint: kFingerprintPool[index + 1],
        rotatedAt: now,
      );
    } else {
      overrides[proxyName] = FingerprintRecord(
        fingerprint: kFingerprintPool[1],
        rotatedAt: now,
      );
    }
    await save(overrides);
    return true;
  }

  /// 测延迟成功：保留已生效的指纹（回退默认值会把修好的节点又弄坏），
  /// 只更新时间戳让后续失败可以再次轮换。
  static Future<void> noteSuccess(String proxyName) async {
    if (!smartFilledProxyNames.contains(proxyName)) {
      return;
    }
    final overrides = await load();
    final record = overrides[proxyName];
    if (record == null) {
      return;
    }
    overrides[proxyName] = FingerprintRecord(
      fingerprint: record.fingerprint,
      rotatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await save(overrides);
  }
}

/// 两次轮换之间的最短间隔：测延迟失败可能是节点或服务器本身挂了，
/// 冷却期内不重复推进指纹，避免一次故障把池子轮空。
const rotateCooldown = Duration(minutes: 10);

/// 开关读取。默认开 —— 抗检测参数对服务器完全透明，关掉只会让用户少一层保护。
Future<bool> loadSmartAntidetectionEnabled() async {
  final prefs = await preferences.sharedPreferencesCompleter.future;
  return prefs?.getBool(kSmartAntidetectionKey) ?? true;
}

Future<void> saveSmartAntidetectionEnabled(bool value) async {
  final prefs = await preferences.sharedPreferencesCompleter.future;
  await prefs?.setBool(kSmartAntidetectionKey, value);
}
