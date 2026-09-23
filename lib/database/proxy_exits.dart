part of 'database.dart';

/// 节点实测落地（「测落地」/ 测延迟后自动批测的结果）。
///
/// 为什么进 drift 而不是 shared_preferences：批测一轮写两三百条，SP 是
/// 「整键重写」，每轮全量序列化一份 JSON；这里是一行一行 upsert，写放大
/// 从「整表」降到「一条」，且过期清理直接一条 DELETE。启动时做一次旧
/// SP 数据的搬家（见 [ProxyExitsDao.migrateLegacyIfNeeded]）。
@DataClassName('ProxyExitRecord')
class ProxyExits extends Table {
  @override
  String get tableName => 'proxy_exits';

  /// 节点名。同名节点在订阅更新后语义不变，作为主键天然去重。
  TextColumn get proxyName => text()();

  /// 内核本地查 geoip 得到的两位国家码（小写）。
  TextColumn get countryCode => text()();

  /// 出口 IP。探测失败不会有记录（只存成功），但成功时 IP 理论上不会缺。
  TextColumn get ip => text().nullable()();

  /// 探测时间（毫秒时间戳）。新鲜度窗口在 Dart 侧与原 shared_preferences
  /// 方案一致（14 天），这里只是数据。
  IntColumn get testedAt => integer()();

  @override
  Set<Column> get primaryKey => {proxyName};
}

@DriftAccessor(tables: [ProxyExits])
class ProxyExitsDao extends DatabaseAccessor<Database>
    with _$ProxyExitsDaoMixin {
  ProxyExitsDao(super.attachedDatabase);

  Future<List<ProxyExitRecord>> all() => select(proxyExits).get();

  Future<void> upsert(ProxyExitRecord record) {
    return into(proxyExits).insertOnConflictUpdate(record);
  }

  Future<void> upsertAll(Iterable<ProxyExitRecord> records) {
    return batch((b) => b.insertAllOnConflictUpdate(proxyExits, records));
  }

  Future<void> deleteOlderThan(int thresholdMillis) {
    return (delete(
      proxyExits,
    )..where((t) => t.testedAt.isSmallerThanValue(thresholdMillis))).go();
  }

  Future<int> count() async => (await proxyExits.count.getSingle()) ?? 0;

  /// 旧方案（shared_preferences 键 `proxyExitInfo`）的数据搬家：只在
  /// 库还是空的、而 SP 里有存货时做一次。搬完不删 SP 键 —— 万一用户
  /// 降级回旧版，旧版还能读到；两边并存也只是几百字节的冗余。
  ///
  /// 直接手解 JSON 而不是调 providers 层的 `ProxyExitInfo.fromJson`：
  /// 数据库层不依赖界面层，这个方向的 import 早晚出环。
  Future<void> migrateLegacyIfNeeded() async {
    final existing = await count();
    if (existing > 0) {
      return;
    }
    final prefs = await preferences.sharedPreferencesCompleter.future;
    final value = prefs?.getString('proxyExitInfo');
    if (value == null || value.isEmpty) {
      return;
    }
    try {
      final map = json.decode(value) as Map<String, dynamic>;
      final records = <ProxyExitRecord>[];
      for (final entry in map.entries) {
        if (entry.value is! Map<String, dynamic>) {
          continue;
        }
        final fields = entry.value as Map<String, dynamic>;
        final countryCode = fields['countryCode'] as String?;
        if (countryCode == null || countryCode.isEmpty) {
          continue;
        }
        final ip = fields['ip'] as String?;
        records.add(
          ProxyExitRecord(
            proxyName: entry.key,
            countryCode: countryCode,
            ip: ip == null || ip.isEmpty ? null : ip,
            testedAt: (fields['testedAt'] as num?)?.toInt() ?? 0,
          ),
        );
      }
      if (records.isNotEmpty) {
        await upsertAll(records);
      }
    } catch (_) {
      // 整份 JSON 坏了就放弃搬家，旧键留着不碍事。
    }
  }
}
