import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/ui/color.dart';

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

  Future<int> getUpgradeVersion();

  Future<void> setUpgradeVersion(int version);
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
      data.disabledRules,
      data.proxyGroups,
      clashProviders: data.clashProviders,
    );
  }

  @override
  Future<bool> saveConfig(Config config) => preferences.saveConfig(config);

  @override
  Future<void> clearClashConfig() => preferences.clearClashConfig();

  @override
  Future<void> setVersion(int version) => preferences.setVersion(version);

  @override
  Future<int> getUpgradeVersion() => preferences.getUpgradeVersion();

  @override
  Future<void> setUpgradeVersion(int version) =>
      preferences.setUpgradeVersion(version);
}

class Migration {
  final MigrationStore _store;
  final MigrationTransform _migrateV0;

  Migration({required MigrationStore store, MigrationTransform? migrateV0})
    : _store = store,
      _migrateV0 = migrateV0 ?? oldToNowTask;

  /// - v2（当前）：出厂默认排序从「默认」切到「按延迟」，存量仍是 `none` 的
  ///   配置一次性迁到 `delay`。**不能**套用下方 DNS 那类「不升版本号的幂等
  ///   变换」—— `none` 是用户随时可以主动选回的有效值，靠「读回来还是默认值」
  ///   做判据会把用户后来的选择反复改掉；所以必须升版本号、只跑一次。
  static const currentVersion = 2;

  /// One-off setting changes for upgrades, apart from [currentVersion], which
  /// backups carry and an older app refuses when it is newer than its own.
  static const upgradeVersion = 4;

  static const Map<int, Config Function(Config config)> _upgrades = {
    1: _resetThemeColors,
    2: _keepGlassLook,
    3: _followSystemColors,
    4: _turnOffSidebarBlur,
  };

  Future<Config> run() async {
    final configMap = await _store.getConfigMap();
    final config = await _migrate(configMap);
    return _upgrade(config, installed: configMap != null);
  }

  Future<Config> _upgrade(Config config, {required bool installed}) async {
    final from = await _store.getUpgradeVersion();
    if (from >= upgradeVersion) {
      return config;
    }
    var upgraded = config;
    if (installed) {
      for (var version = from + 1; version <= upgradeVersion; version++) {
        upgraded = _upgrades[version]!(upgraded);
      }
    }
    if (upgraded != config && !await _store.saveConfig(upgraded)) {
      return config;
    }
    await _store.setUpgradeVersion(upgradeVersion);
    return upgraded;
  }

  Future<Config> _migrate(Map<String, Object?>? configMap) async {
    var oldVersion = await _store.getVersion();
    Config? config;
    if (oldVersion > currentVersion) {
      throw StateError(
        'Local data version $oldVersion is newer than $currentVersion.',
      );
    }
    final needsSortMigration = oldVersion >= 1 && oldVersion < currentVersion;
    if (oldVersion == currentVersion || needsSortMigration) {
      if (configMap != null && _isV0(configMap)) {
        try {
          config = Config.strictFromJson(configMap);
        } catch (_) {
          oldVersion = 0;
        }
      } else {
        config = Config.realFromJson(configMap);
      }
      if (config != null) {
        final storedDavPassword = _getStoredDavPassword(configMap);
        final hasPlainTextDavPassword =
            storedDavPassword != null &&
            storedDavPassword == config.davProps?.password;
        // 与 WebDAV 密码混淆同样的处理方式：**不升版本号**的幂等变换，
        // 每次启动都跑一遍。这类变换的判据必须是「读回来的东西还是老的默认值」，
        // 换句话说它是自限的 —— 一旦写过一次就不再成立，不会反复写盘。
        var migrated = config
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
        // 排序默认值迁移：只认「还是出厂 none」的存量（v1 → v2，只跑一次）。
        if (needsSortMigration &&
            migrated.proxiesStyleProps.sortType == ProxiesSortType.none) {
          migrated = migrated.copyWith(
            proxiesStyleProps: migrated.proxiesStyleProps.copyWith(
              sortType: ProxiesSortType.delay,
            ),
          );
          reasons.add('proxies sort default upgrade');
        }
        if (reasons.isNotEmpty) {
          if (!await _store.saveConfig(migrated)) {
            throw StateError(
              'Failed to save migrated preferences (${reasons.join(', ')})',
            );
          }
        }
        if (needsSortMigration) {
          await _store.setVersion(currentVersion);
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

Config _resetThemeColors(Config config) => config.copyWith(
  themeProps: config.themeProps.copyWith(
    primaryColor: defaultPrimaryColor,
    primaryColors: defaultPrimaryColors,
    colorStyle: ColorStyle.vivid,
  ),
);

// The standard glass became the ultra tier when a lighter standard joined it.
Config _keepGlassLook(Config config) =>
    config.themeProps.liquidGlass == LiquidGlassMode.standard
    ? config.copyWith(
        themeProps: config.themeProps.copyWith(
          liquidGlass: LiquidGlassMode.ultra,
        ),
      )
    : config;

const _formerSystemColors = {
  0xFFAF52DE: 0xFFCB30E0,
  0xFFFF3B30: 0xFFFF383C,
  0xFFFF9500: 0xFFFF8D28,
};

// Every preset but blue moved to iOS 27's system color; one picked before moves.
Config _followSystemColors(Config config) {
  final theme = config.themeProps;
  return config.copyWith(
    themeProps: theme.copyWith(
      primaryColor:
          _formerSystemColors[theme.primaryColor] ?? theme.primaryColor,
      primaryColors: [
        ...{
          for (final color in theme.primaryColors)
            _formerSystemColors[color] ?? color,
        },
      ],
    ),
  );
}

// Releases stored sidebar blur on while its switch stayed hidden.
Config _turnOffSidebarBlur(Config config) =>
    config.copyWith(themeProps: config.themeProps.copyWith(sidebarBlur: false));

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
