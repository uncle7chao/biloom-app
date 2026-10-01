import 'dart:convert';

import 'package:fl_clash/common/migration.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Migration', () {
    test('returns current config without rewriting storage', () async {
      final configMap = _createConfigMap(
        davProps: const DAVProps(
          uri: 'https://example.com/dav',
          user: 'user',
          password: 'secret',
        ),
      );
      final store = _FakeMigrationStore(
        configMap: configMap,
        version: Migration.currentVersion,
      );

      final config = await Migration(store: store).run();

      expect(config, Config.realFromJson(configMap));
      expect(config.davProps?.password, 'secret');
      expect(store.events, ['getConfigMap', 'getVersion']);
    });

    test(
      'obfuscates a compatible DAV password without a version migration',
      () async {
        final configMap = _createConfigMap(
          davProps: const DAVProps(
            uri: 'https://example.com/dav',
            user: 'user',
          ),
        );
        final davProps = configMap['davProps']! as Map<String, Object?>;
        davProps['password'] = 'secret';
        // 密码混淆是「不升版本号」的幂等变换，用当前版本存储验证 —— v1 存储
        // 现在会额外触发一次性的排序默认值迁移（见「Migration proxies sort
        // upgrade」组）。
        final store = _FakeMigrationStore(
          configMap: configMap,
          version: Migration.currentVersion,
        );

        final config = await Migration(store: store).run();

        expect(config.davProps?.user, 'user');
        expect(config.davProps?.password, 'secret');
        expect(store.savedConfig, config);
        expect(store.version, Migration.currentVersion);
        expect(store.events, ['getConfigMap', 'getVersion', 'saveConfig']);
        final savedConfigMap =
            jsonDecode(jsonEncode(store.savedConfig)) as Map<String, Object?>;
        final savedDavProps =
            savedConfigMap['davProps']! as Map<String, Object?>;
        expect(savedDavProps['password'], startsWith('v1.'));
        expect(savedDavProps['password'], isNot(contains('secret')));
      },
    );

    test(
      'commits v0 cleanup and version only after migrated data is saved',
      () async {
        final configMap = <String, Object?>{
          'proxiesStyle': <String, Object?>{},
          'dav': <String, Object?>{
            'uri': 'https://example.com/dav',
            'user': 'user',
            'password': 'secret',
          },
        };
        final store = _FakeMigrationStore(
          configMap: configMap,
          version: 0,
          clashConfigMap: <String, Object?>{'mixed-port': 7890},
        );
        final migration = Migration(
          store: store,
          migrateV0: (configMap) async {
            store.events.add('migrateV0');
            expect(configMap['patchClashConfig'], store.clashConfigMap);
            return MigrationData(
              configMap: _createConfigMap(
                davProps: const DAVProps(
                  uri: 'https://example.com/dav',
                  user: 'user',
                  password: 'secret',
                ),
              ),
            );
          },
        );

        await migration.run();

        expect(store.events, [
          'getConfigMap',
          'getVersion',
          'getClashConfigMap',
          'migrateV0',
          'restore',
          'saveConfig',
          'clearClashConfig',
          'setVersion',
        ]);
        expect(store.savedConfig?.davProps?.password, 'secret');
        expect(store.didClearClashConfig, isTrue);
        expect(store.version, Migration.currentVersion);
      },
    );

    test(
      'preserves legacy clash config when current-shaped data has version zero',
      () async {
        final configMap = _createConfigMap()..remove('patchClashConfig');
        final clashConfigMap = _createClashConfigMap(mixedPort: 1234);
        final store = _FakeMigrationStore(
          configMap: configMap,
          version: 0,
          clashConfigMap: clashConfigMap,
        );

        final config = await Migration(store: store).run();

        expect(config.patchClashConfig.mixedPort, 1234);
        expect(store.savedConfig?.patchClashConfig.mixedPort, 1234);
        expect(store.didClearClashConfig, isTrue);
        expect(store.events, [
          'getConfigMap',
          'getVersion',
          'getClashConfigMap',
          'restore',
          'saveConfig',
          'clearClashConfig',
          'setVersion',
        ]);
      },
    );

    test('does not clear legacy clash config when saving fails', () async {
      final configMap = _createConfigMap()..remove('patchClashConfig');
      final store = _FakeMigrationStore(
        configMap: configMap,
        version: 0,
        clashConfigMap: _createClashConfigMap(mixedPort: 1234),
        configSaveResult: false,
      );

      await expectLater(
        Migration(store: store).run(),
        throwsA(isA<StateError>()),
      );

      expect(store.didClearClashConfig, isFalse);
      expect(store.version, 0);
      expect(store.events, [
        'getConfigMap',
        'getVersion',
        'getClashConfigMap',
        'restore',
        'saveConfig',
        'isAvailable',
      ]);
    });

    test('starts with defaults when the store cannot be opened', () async {
      final store = _FakeMigrationStore(
        configMap: null,
        version: 0,
        configSaveResult: false,
        available: false,
      );

      final config = await Migration(store: store).run();

      expect(config, isNotNull);
      expect(store.didClearClashConfig, isFalse);
      expect(store.version, 0);
      expect(store.events, [
        'getConfigMap',
        'getVersion',
        'getClashConfigMap',
        'restore',
        'saveConfig',
        'isAvailable',
      ]);
    });

    test('keeps the current version when password obfuscation fails', () async {
      final configMap = _createConfigMap(
        davProps: const DAVProps(uri: 'https://example.com/dav', user: 'user'),
      );
      final davProps = configMap['davProps']! as Map<String, Object?>;
      davProps['password'] = 'secret';
      final store = _FakeMigrationStore(
        configMap: configMap,
        version: Migration.currentVersion,
        configSaveResult: false,
      );

      await expectLater(
        Migration(store: store).run(),
        throwsA(isA<StateError>()),
      );

      expect(store.events, ['getConfigMap', 'getVersion', 'saveConfig']);
      expect(store.version, Migration.currentVersion);
    });
  });

  group('migrateLegacyDnsNameservers', () {
    // 这一组钉住一个刻意不对称的取舍：漏迁移只是「没变好」，误迁移是「把用户自己
    // 精心填过的 DNS 上游覆盖掉」。所以只有与旧默认值**逐项相等**时才允许改写。
    test('rewrites an untouched legacy default', () {
      const config = Config(
        themeProps: defaultThemeProps,
        patchClashConfig: PatchClashConfig(
          dns: Dns(nameserver: legacyDefaultNameservers),
        ),
      );

      final migrated = config.migrateLegacyDnsNameservers();

      expect(migrated.patchClashConfig.dns.nameserver, defaultNameservers);
    });

    test('leaves a user-provided list alone even when it overlaps', () {
      const config = Config(
        themeProps: defaultThemeProps,
        patchClashConfig: PatchClashConfig(
          dns: Dns(nameserver: ['https://doh.pub/dns-query']),
        ),
      );

      expect(identical(config.migrateLegacyDnsNameservers(), config), isTrue);
    });

    test('is idempotent once the new default is in place', () {
      const config = Config(
        themeProps: defaultThemeProps,
        patchClashConfig: PatchClashConfig(
          dns: Dns(nameserver: defaultNameservers),
        ),
      );

      // 返回同一个实例，而不是内容相等的新实例 —— 调用方靠 identical 判断
      // 「需不需要写盘」，返回副本会让每次启动都白写一次。
      expect(identical(config.migrateLegacyDnsNameservers(), config), isTrue);
    });

    test('touches only the nameserver, not the surrounding dns settings', () {
      const config = Config(
        themeProps: defaultThemeProps,
        patchClashConfig: PatchClashConfig(
          dns: Dns(
            nameserver: legacyDefaultNameservers,
            fallback: ['tls://9.9.9.9'],
            listen: '0.0.0.0:1053',
          ),
        ),
      );

      final dns = config.migrateLegacyDnsNameservers().patchClashConfig.dns;

      expect(dns.nameserver, defaultNameservers);
      expect(dns.fallback, ['tls://9.9.9.9']);
      expect(dns.listen, '0.0.0.0:1053');
      expect(dns.nameserverPolicy, const Dns().nameserverPolicy);
    });
  });

  group('Migration dns nameserver upgrade', () {
    test('persists the upgrade for a stored legacy default', () async {
      final store = _FakeMigrationStore(
        configMap: _createConfigMapWithNameserver(legacyDefaultNameservers),
        version: Migration.currentVersion,
      );

      final config = await Migration(store: store).run();

      expect(config.patchClashConfig.dns.nameserver, defaultNameservers);
      expect(
        store.savedConfig?.patchClashConfig.dns.nameserver,
        defaultNameservers,
      );
      expect(store.events, ['getConfigMap', 'getVersion', 'saveConfig']);
    });

    test('does not write when the stored nameserver was customised', () async {
      final store = _FakeMigrationStore(
        configMap: _createConfigMapWithNameserver([
          'https://dns.quad9.net/dns-query',
        ]),
        version: Migration.currentVersion,
      );

      final config = await Migration(store: store).run();

      expect(config.patchClashConfig.dns.nameserver, [
        'https://dns.quad9.net/dns-query',
      ]);
      expect(store.events, ['getConfigMap', 'getVersion']);
    });
  });

  group('migrateLegacyDnsFallback', () {
    // 这一组守的是一个「改了主上游就以为改完了」的陷阱。上游那套默认值是**围绕
    // 「主上游 = 国内 DoH」设计**的，主上游换成境外 DoH 之后，其中三处都会反过来
    // **架空主上游**（判定都在 `dns/resolver.go` 的 `ipExchange`）：
    //   · `fallback-filter.domain`：命中它的域名跳过主上游、只查备用上游；
    //   · `fallback-filter.geoip`：主上游解析出非 CN 的 IP 时，丢弃主上游的成功结果、
    //     改用备用上游的结果（而且是无条件采用）；
    //   · `fallback` 本身：DoT:853（特征明显、易被干扰）→ DoH:443。
    // 所以三个字段都要升级，并且**各自独立判定** —— 用户可能只动过其中一个。
    test('clears both the legacy bypass list and the legacy DoT fallback', () {
      const config = Config(
        themeProps: defaultThemeProps,
        patchClashConfig: PatchClashConfig(
          dns: Dns(
            fallback: legacyDefaultFallback,
            fallbackFilter: FallbackFilter(
              domain: legacyFallbackFilterDomains,
            ),
          ),
        ),
      );

      final dns = config.migrateLegacyDnsFallback().patchClashConfig.dns;

      expect(dns.fallback, defaultFallback);
      expect(dns.fallbackFilter.domain, isEmpty);
    });

    test('turns off the legacy geoip filter that discards nameserver answers', () {
      // 出厂默认三件套同时命中：一起升级。
      const config = Config(
        themeProps: defaultThemeProps,
        patchClashConfig: PatchClashConfig(
          dns: Dns(
            fallback: legacyDefaultFallback,
            fallbackFilter: FallbackFilter(
              domain: legacyFallbackFilterDomains,
              geoip: legacyFallbackFilterGeoip,
              geoipCode: legacyFallbackFilterGeoipCode,
            ),
          ),
        ),
      );

      final dns = config.migrateLegacyDnsFallback().patchClashConfig.dns;

      expect(dns.fallback, defaultFallback);
      expect(dns.fallbackFilter.domain, isEmpty);
      expect(dns.fallbackFilter.geoip, isFalse);
      // `geoip-code` 本身不是问题（只在 geoip 开着时才被读），留着不动 ——
      // 迁移不该在用户看不出差别的地方改他的配置。
      expect(dns.fallbackFilter.geoipCode, 'CN');
      expect(dns.fallbackFilter.ipcidr, ['240.0.0.0/4']);
    });

    test('turns off geoip on its own, leaving the rest of the filter intact', () {
      // 独立判定的第三面：只 `geoip` 是旧的，也必须被单独升级；
      // 同时证明它不会顺手把兄弟字段（ipcidr）重置掉。
      const config = Config(
        themeProps: defaultThemeProps,
        patchClashConfig: PatchClashConfig(
          dns: Dns(
            fallback: defaultFallback,
            fallbackFilter: FallbackFilter(
              domain: defaultFallbackFilterDomains,
              geoip: legacyFallbackFilterGeoip,
              ipcidr: ['10.0.0.0/8'],
            ),
          ),
        ),
      );

      final dns = config.migrateLegacyDnsFallback().patchClashConfig.dns;

      expect(dns.fallbackFilter.geoip, isFalse);
      expect(dns.fallbackFilter.ipcidr, ['10.0.0.0/8']);
      expect(dns.fallbackFilter.geoipCode, 'CN');
      expect(dns.fallback, defaultFallback);
      expect(dns.fallbackFilter.domain, isEmpty);
    });

    test('leaves a geoip filter alone when the user picked another country', () {
      // `geoip-code` 不是出厂值 ⇒ 这一组是用户自己配的，一个字节都不碰。
      // 「宁可漏，不可错」：误改用户配置的代价远高于漏迁移一次。
      const config = Config(
        themeProps: defaultThemeProps,
        patchClashConfig: PatchClashConfig(
          dns: Dns(
            fallback: defaultFallback,
            fallbackFilter: FallbackFilter(
              domain: defaultFallbackFilterDomains,
              geoip: true,
              geoipCode: 'JP',
            ),
          ),
        ),
      );

      expect(identical(config.migrateLegacyDnsFallback(), config), isTrue);
    });

    test('upgrades only the untouched half when the other was customised', () {
      // 用户自己填过备用上游 → 那一半一个字节都不碰；旁路列表没动过 → 照改。
      const config = Config(
        themeProps: defaultThemeProps,
        patchClashConfig: PatchClashConfig(
          dns: Dns(
            fallback: ['tls://9.9.9.9'],
            fallbackFilter: FallbackFilter(
              domain: legacyFallbackFilterDomains,
            ),
          ),
        ),
      );

      final dns = config.migrateLegacyDnsFallback().patchClashConfig.dns;

      expect(dns.fallback, ['tls://9.9.9.9']);
      expect(dns.fallbackFilter.domain, isEmpty);
    });

    test('leaves a customised bypass list alone', () {
      const config = Config(
        themeProps: defaultThemeProps,
        patchClashConfig: PatchClashConfig(
          dns: Dns(
            fallback: legacyDefaultFallback,
            fallbackFilter: FallbackFilter(domain: ['+.example.com']),
          ),
        ),
      );

      final dns = config.migrateLegacyDnsFallback().patchClashConfig.dns;

      expect(dns.fallback, defaultFallback);
      expect(dns.fallbackFilter.domain, ['+.example.com']);
    });

    test('is idempotent once all three are upgraded', () {
      const config = Config(
        themeProps: defaultThemeProps,
        patchClashConfig: PatchClashConfig(
          dns: Dns(
            fallback: defaultFallback,
            fallbackFilter: FallbackFilter(
              domain: defaultFallbackFilterDomains,
              geoip: defaultFallbackFilterGeoip,
            ),
          ),
        ),
      );

      // 同 `migrateLegacyDnsNameservers`：返回同一实例才是「不需要写盘」的信号。
      expect(identical(config.migrateLegacyDnsFallback(), config), isTrue);
    });

    test('touches only the legacy fields, not the surrounding dns settings', () {
      const config = Config(
        themeProps: defaultThemeProps,
        patchClashConfig: PatchClashConfig(
          dns: Dns(
            fallback: legacyDefaultFallback,
            fallbackFilter: FallbackFilter(
              domain: legacyFallbackFilterDomains,
              // geoip 已经是「关」，不是出厂默认的那一组 → 不该被碰
              // （它本来就等于目标值，改与不改结果相同，但这里同时也守住了
              //  「判定基于 geoip + geoipCode 这一组」这个前提）。
              geoip: false,
              ipcidr: ['10.0.0.0/8'],
            ),
            listen: '0.0.0.0:1053',
          ),
        ),
      );

      final dns = config.migrateLegacyDnsFallback().patchClashConfig.dns;

      expect(dns.listen, '0.0.0.0:1053');
      // fallback-filter 里只有 domain 是旧默认值 —— 就只改它一个，兄弟字段原样保留。
      expect(dns.fallbackFilter.geoip, isFalse);
      expect(dns.fallbackFilter.ipcidr, ['10.0.0.0/8']);
      expect(dns.fallbackFilter.geoipCode, 'CN');
    });
  });

  group('Migration dns fallback upgrade', () {
    test('persists the upgrade for a stored legacy bypass list', () async {
      final store = _FakeMigrationStore(
        configMap: _createConfigMapWithDns(
          fallback: legacyDefaultFallback,
          domains: legacyFallbackFilterDomains,
        ),
        version: Migration.currentVersion,
      );

      final config = await Migration(store: store).run();
      final dns = config.patchClashConfig.dns;

      expect(dns.fallback, defaultFallback);
      expect(dns.fallbackFilter.domain, isEmpty);
      expect(store.savedConfig?.patchClashConfig.dns.fallback, defaultFallback);
      expect(store.events, ['getConfigMap', 'getVersion', 'saveConfig']);
    });

    test('one save covers the nameserver and every fallback upgrade', () async {
      // 两个迁移是链式跑的，必须合成**一次**写盘 —— 否则每次启动都白写两遍。
      final store = _FakeMigrationStore(
        configMap: _createConfigMapWithDns(
          nameserver: legacyDefaultNameservers,
          fallback: legacyDefaultFallback,
          domains: legacyFallbackFilterDomains,
          geoip: legacyFallbackFilterGeoip,
        ),
        version: Migration.currentVersion,
      );

      final config = await Migration(store: store).run();
      final dns = config.patchClashConfig.dns;

      expect(dns.nameserver, defaultNameservers);
      expect(dns.fallback, defaultFallback);
      expect(dns.fallbackFilter.domain, isEmpty);
      expect(dns.fallbackFilter.geoip, isFalse);
      expect(store.events, ['getConfigMap', 'getVersion', 'saveConfig']);
    });

    test('persists the geoip upgrade for a stored legacy filter', () async {
      // 只在 geoip 这一维上还是旧值 —— 也必须单独触发一次写盘。
      final store = _FakeMigrationStore(
        configMap: _createConfigMapWithDns(
          fallback: defaultFallback,
          domains: defaultFallbackFilterDomains,
          geoip: legacyFallbackFilterGeoip,
        ),
        version: Migration.currentVersion,
      );

      final config = await Migration(store: store).run();

      expect(config.patchClashConfig.dns.fallbackFilter.geoip, isFalse);
      expect(
        store.savedConfig?.patchClashConfig.dns.fallbackFilter.geoip,
        isFalse,
      );
      expect(store.events, ['getConfigMap', 'getVersion', 'saveConfig']);
    });

    test('does not write when nothing is left at the legacy default', () async {
      final store = _FakeMigrationStore(
        configMap: _createConfigMapWithDns(
          fallback: ['tls://9.9.9.9'],
          domains: ['+.example.com'],
          // geoip 这里取**当前**默认（关）→ 三个字段都不是旧默认值。
        ),
        version: Migration.currentVersion,
      );

      final config = await Migration(store: store).run();

      expect(config.patchClashConfig.dns.fallback, ['tls://9.9.9.9']);
      expect(config.patchClashConfig.dns.fallbackFilter.domain, [
        '+.example.com',
      ]);
      expect(store.events, ['getConfigMap', 'getVersion']);
    });
  });

  group('Migration proxies sort upgrade', () {
    // v1 → v2 的一次性迁移：出厂排序从「默认(none)」切到「按延迟(delay)」。
    // 与 DNS 那组幂等变换不同，`none` 是用户随时可主动选回的有效值，所以
    // 判据不能是「读回来还是默认值」（那会把用户后来的选择反复改掉），
    // 必须靠版本号保证只跑一次。
    test('migrates a stored legacy default once (v1 → v2)', () async {
      final store = _FakeMigrationStore(
        configMap: _createConfigMapWithSort(ProxiesSortType.none),
        version: 1,
      );

      final config = await Migration(store: store).run();

      expect(config.proxiesStyleProps.sortType, ProxiesSortType.delay);
      expect(
        store.savedConfig?.proxiesStyleProps.sortType,
        ProxiesSortType.delay,
      );
      expect(store.version, Migration.currentVersion);
      expect(store.events, [
        'getConfigMap',
        'getVersion',
        'saveConfig',
        'setVersion',
      ]);
    });

    test('does not rewrite a v1 store that already picked a sort', () async {
      // 用户在旧版里就选过「名称」→ 迁移只升版本号，不碰他的选择。
      final store = _FakeMigrationStore(
        configMap: _createConfigMapWithSort(ProxiesSortType.name),
        version: 1,
      );

      final config = await Migration(store: store).run();

      expect(config.proxiesStyleProps.sortType, ProxiesSortType.name);
      expect(store.savedConfig, isNull);
      expect(store.version, Migration.currentVersion);
      expect(store.events, ['getConfigMap', 'getVersion', 'setVersion']);
    });

    test('leaves an explicit default alone on the current version', () async {
      // v2 里主动选回「默认」的配置 → 版本号已是当前值，永远不再被改写。
      final store = _FakeMigrationStore(
        configMap: _createConfigMapWithSort(ProxiesSortType.none),
        version: Migration.currentVersion,
      );

      final config = await Migration(store: store).run();

      expect(config.proxiesStyleProps.sortType, ProxiesSortType.none);
      expect(store.savedConfig, isNull);
      expect(store.version, Migration.currentVersion);
      expect(store.events, ['getConfigMap', 'getVersion']);
    });

    test('ships delay as the factory default sort', () {
      expect(defaultProxiesStyleProps.sortType, ProxiesSortType.delay);
    });
  });
}

/// 造一份「存下来的配置」。没显式给的那部分取**当前**默认值 —— 所以要模拟存量
/// 旧配置，必须把旧值显式传进来（这正是各用例在做的）。
Map<String, Object?> _createConfigMapWithDns({
  List<String>? nameserver,
  List<String>? fallback,
  List<String>? domains,
  bool? geoip,
}) {
  return jsonDecode(
        jsonEncode(
          Config(
            themeProps: defaultThemeProps,
            patchClashConfig: PatchClashConfig(
              dns: Dns(
                nameserver: nameserver ?? defaultNameservers,
                fallback: fallback ?? defaultFallback,
                fallbackFilter: FallbackFilter(
                  domain: domains ?? defaultFallbackFilterDomains,
                  geoip: geoip ?? defaultFallbackFilterGeoip,
                ),
              ),
            ),
          ),
        ),
      )
      as Map<String, Object?>;
}

Map<String, Object?> _createConfigMapWithNameserver(List<String> nameserver) {
  return jsonDecode(
        jsonEncode(
          Config(
            themeProps: defaultThemeProps,
            patchClashConfig: PatchClashConfig(
              dns: Dns(nameserver: nameserver),
            ),
          ),
        ),
      )
      as Map<String, Object?>;
}

Map<String, Object?> _createConfigMap({DAVProps? davProps}) {
  return jsonDecode(
        jsonEncode(Config(themeProps: defaultThemeProps, davProps: davProps)),
      )
      as Map<String, Object?>;
}

Map<String, Object?> _createConfigMapWithSort(ProxiesSortType sortType) {
  return jsonDecode(
        jsonEncode(
          Config(
            themeProps: defaultThemeProps,
            proxiesStyleProps: ProxiesStyleProps(sortType: sortType),
          ),
        ),
      )
      as Map<String, Object?>;
}

Map<String, Object?> _createClashConfigMap({required int mixedPort}) {
  return jsonDecode(jsonEncode(PatchClashConfig(mixedPort: mixedPort)))
      as Map<String, Object?>;
}

class _FakeMigrationStore implements MigrationStore {
  final Map<String, Object?>? configMap;
  final Map<String, Object?>? clashConfigMap;
  final bool configSaveResult;
  final bool available;
  final List<String> events = [];

  int version;
  Config? savedConfig;
  MigrationData? restoredData;
  bool didClearClashConfig = false;

  _FakeMigrationStore({
    required this.configMap,
    required this.version,
    this.clashConfigMap,
    this.configSaveResult = true,
    this.available = true,
  });

  @override
  Future<bool> get isAvailable async {
    events.add('isAvailable');
    return available;
  }

  @override
  Future<void> clearClashConfig() async {
    events.add('clearClashConfig');
    didClearClashConfig = true;
  }

  @override
  Future<Map<String, Object?>?> getClashConfigMap() async {
    events.add('getClashConfigMap');
    return clashConfigMap;
  }

  @override
  Future<Map<String, Object?>?> getConfigMap() async {
    events.add('getConfigMap');
    return configMap;
  }

  @override
  Future<int> getVersion() async {
    events.add('getVersion');
    return version;
  }

  @override
  Future<void> restore(MigrationData data) async {
    events.add('restore');
    restoredData = data;
  }

  @override
  Future<bool> saveConfig(Config config) async {
    events.add('saveConfig');
    savedConfig = config;
    return configSaveResult;
  }

  @override
  Future<void> setVersion(int version) async {
    events.add('setVersion');
    this.version = version;
  }
}
