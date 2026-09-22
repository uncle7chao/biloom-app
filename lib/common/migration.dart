import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/models/models.dart';

import 'preferences.dart';
import 'task.dart';

typedef MigrationTransform =
    Future<MigrationData> Function(Map<String, Object?> configMap);

abstract interface class MigrationStore {
  /// False when the backing store could not be opened at all, as opposed to a
  /// store that opened but holds nothing.
  Future<bool> get isAvailable;

  Future<Map<String, Object?>?> getConfigMap();

  Future<int> getVersion();

  Future<Map<String, Object?>?> getClashConfigMap();

  Future<void> restore(MigrationData data);

  Future<bool> saveConfig(Config config);

  Future<void> clearClashConfig();

  Future<void> setVersion(int version);
}

class _AppMigrationStore implements MigrationStore {
  const _AppMigrationStore();

  @override
  Future<bool> get isAvailable => preferences.isInit;

  @override
  Future<Map<String, Object?>?> getConfigMap() => preferences.getConfigMap();

  @override
  Future<int> getVersion() => preferences.getVersion();

  @override
  Future<Map<String, Object?>?> getClashConfigMap() =>
      preferences.getClashConfigMap();

  @override
  Future<void> restore(MigrationData data) {
    return database.restore(
      data.profiles,
      data.scripts,
      data.rules,
      data.links,
      data.proxyGroups,
    );
  }

  @override
  Future<bool> saveConfig(Config config) => preferences.saveConfig(config);

  @override
  Future<void> clearClashConfig() => preferences.clearClashConfig();

  @override
  Future<void> setVersion(int version) => preferences.setVersion(version);
}

class Migration {
  final MigrationStore _store;
  final MigrationTransform _migrateV0;

  Migration({required MigrationStore store, MigrationTransform? migrateV0})
    : _store = store,
      _migrateV0 = migrateV0 ?? oldToNowTask;

  static const currentVersion = 1;

  Future<Config> run() async {
    final configMap = await _store.getConfigMap();
    var oldVersion = await _store.getVersion();
    Config? config;
    if (oldVersion > currentVersion) {
      throw StateError(
        'Local data version $oldVersion is newer than $currentVersion.',
      );
    }
    if (oldVersion == currentVersion) {
      try {
        config = Config.realFromJson(configMap);
      } catch (_) {
        if (!_isV0(configMap)) {
          throw StateError(
            'Local data is damaged. A reset is required to fix this issue.',
          );
        }
        oldVersion = 0;
      }
      if (config != null) {
        final storedDavPassword = _getStoredDavPassword(configMap);
        final hasPlainTextDavPassword =
            storedDavPassword != null &&
            storedDavPassword == config.davProps?.password;
        // 与 WebDAV 密码混淆同样的处理方式：**不升版本号**的幂等变换，
        // 每次启动都跑一遍。这类变换的判据必须是「读回来的东西还是老的默认值」，
        // 换句话说它是自限的 —— 一旦写过一次就不再成立，不会反复写盘。
        final migrated = config
            .migrateLegacyDnsNameservers()
            // 同一套「不升版本号的幂等变换」：主上游换了之后，上游那套**围绕
            // 「主上游 = 国内 DoH」设计**的 fallback-filter 就全变成了「架空主上游」
            // 的东西（`domain` 旁路 + `geoip` 反选），必须一并拆掉 —— 详见
            // `migrateLegacyDnsFallback` 的注释。
            .migrateLegacyDnsFallback();
        final reasons = <String>[
          if (hasPlainTextDavPassword) 'webdav password obfuscation',
          if (!identical(migrated, config)) 'dns defaults upgrade',
        ];
        if (reasons.isNotEmpty) {
          if (!await _store.saveConfig(migrated)) {
            throw StateError(
              'Failed to save migrated preferences (${reasons.join(', ')})',
            );
          }
        }
        return migrated;
      }
    }

    MigrationData data = MigrationData(configMap: configMap);
    var shouldClearClashConfig = false;
    if (oldVersion == 0) {
      final clashConfigMap = await _store.getClashConfigMap();
      if (_isV0(configMap) && configMap != null) {
        final legacyConfigMap = Map<String, Object?>.from(configMap);
        if (clashConfigMap != null) {
          legacyConfigMap['patchClashConfig'] = clashConfigMap;
          shouldClearClashConfig = true;
        }
        data = await _migrateV0(legacyConfigMap);
      } else if (clashConfigMap != null) {
        final currentConfigMap = Map<String, Object?>.from(
          configMap ?? const {},
        );
        currentConfigMap.putIfAbsent('patchClashConfig', () => clashConfigMap);
        data = MigrationData(configMap: currentConfigMap);
        shouldClearClashConfig = true;
      }
    }

    // v0 升上来的配置里那个 DNS 上游同样是「从没被改过的旧默认值」，一并升级
    // （备用上游与 fallback-filter 的 domain / geoip 同理）。
    config = Config.realFromJson(
      data.configMap,
    ).migrateLegacyDnsNameservers().migrateLegacyDnsFallback();
    await _store.restore(data);
    if (!await _store.saveConfig(config)) {
      // An unopenable store is reported later by the corrupt-cache dialog,
      // which offers a reset; failing here would hide that path.
      if (await _store.isAvailable) {
        throw StateError('Failed to save migrated preferences');
      }
      return config;
    }
    if (shouldClearClashConfig) {
      await _store.clearClashConfig();
    }
    await _store.setVersion(currentVersion);
    return config;
  }
}

bool _isV0(Map<String, Object?>? configMap) =>
    configMap?['proxiesStyle'] != null;

String? _getStoredDavPassword(Map<String, Object?>? configMap) {
  final dav = configMap?['davProps'] ?? configMap?['dav'];
  if (dav is! Map) {
    return null;
  }
  final password = dav['password'];
  return password is String && password.isNotEmpty ? password : null;
}

final migration = Migration(store: const _AppMigrationStore());
