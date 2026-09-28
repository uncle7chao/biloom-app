import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:yaml/yaml.dart';

int _double(int value) => value * 2;

void main() {
  test('encoding helpers round-trip structured data', () async {
    final encoded = await encodeJSONTask({
      'name': 'FlClash',
      'values': [1, true, null],
    });
    final decoded = await decodeJSONTask<Map<String, dynamic>>(encoded);

    expect(decoded['name'], 'FlClash');
    expect(decoded['values'], [1, true, null]);
    expect(await encodeYamlTask({'enabled': true}), contains('enabled: true'));
    expect(await encodeMD5Task('abc'), '900150983cd24fb0d6963f7d28e17f72');
  });

  test('toGroupsTask converts, selects, and sorts core proxy data', () async {
    final proxies = <String, dynamic>{
      'Selector': {
        'name': 'Selector',
        'type': 'Selector',
        'now': 'Beta',
        'all': ['Zulu', 'Beta', 'missing'],
      },
      'Direct': {'name': 'Direct', 'type': 'Direct'},
      'Zulu': {'name': 'Zulu', 'type': 'Direct'},
      'Beta': {'name': 'Beta', 'type': 'Direct'},
    };
    final groups = await toGroupsTask(
      ComputeGroupsState(
        proxiesData: ProxiesData(
          all: const ['Selector', 'Direct'],
          proxies: proxies,
        ),
        sortType: ProxiesSortType.name,
        delayMap: const {},
        selectedMap: const {'Selector': 'Beta'},
        defaultTestUrl: 'https://example.com/generate_204',
      ),
    );

    expect(groups, hasLength(1));
    expect(groups.single.name, 'Selector');
    expect(groups.single.all.map((proxy) => proxy.name), ['Beta', 'Zulu']);
  });

  test(
    'clashConfigTask parses core config data off the main isolate',
    () async {
      final configMap = <String, dynamic>{
        'proxies': [
          {'name': 'Alpha', 'type': 'ss'},
          {'name': 'Beta', 'type': 'vmess'},
        ],
        'proxy-groups': [
          {
            'name': 'Auto',
            'type': 'url-test',
            'proxies': ['Alpha', 'Beta'],
          },
        ],
        'rules': ['DOMAIN,example.com,Auto'],
        'proxy-providers': {
          'provider': {'type': 'http'},
        },
        'rule-providers': {
          'ruleSet': {'type': 'http'},
        },
        'sub-rules': {'nested': []},
      };

      final clashConfig = await clashConfigTask(configMap);

      expect(clashConfig.proxies.map((item) => item.name), ['Alpha', 'Beta']);
      expect(clashConfig.proxyGroups.single.type, GroupType.URLTest);
      expect(clashConfig.rules.single.ruleTarget, 'Auto');
      expect(clashConfig.rules.single.content, 'example.com');
      expect(clashConfig.proxyProviders, ['provider']);
      expect(clashConfig.ruleProviders, ['ruleSet']);
      expect(clashConfig.subRules, ['nested']);
      expect(clashConfig.proxyTypeMap, {
        'Alpha': 'ss',
        'Beta': 'vmess',
        'Auto': 'url-test',
      });
    },
  );

  test('buildClashConfig indexes group types by their clash value', () {
    final clashConfig = buildClashConfig(<String, dynamic>{
      'proxies': [
        {'name': 'Alpha', 'type': 'ss'},
      ],
      'proxy-groups': [
        {
          'name': 'Fallback',
          'type': 'fallback',
          'proxies': ['Alpha'],
        },
      ],
    });

    expect(clashConfig.proxyTypeMap, {'Alpha': 'ss', 'Fallback': 'fallback'});
    expect(clashConfig.rules, isEmpty);
  });

  test('toGroupsTask leaves the source proxy map untouched', () async {
    final proxies = <String, dynamic>{
      'Selector': {
        'name': 'Selector',
        'type': 'Selector',
        'all': ['Beta'],
      },
      'Beta': {'name': 'Beta', 'type': 'Direct'},
    };
    final state = ComputeGroupsState(
      proxiesData: ProxiesData(all: const ['Selector'], proxies: proxies),
      sortType: ProxiesSortType.none,
      delayMap: const {},
      selectedMap: const {},
      defaultTestUrl: '',
    );

    await buildGroups(state);
    await buildGroups(state);

    expect(proxies['Selector']['all'], ['Beta']);
  });

  test('toGroupsTask returns empty data without proxies', () async {
    final groups = await toGroupsTask(
      const ComputeGroupsState(
        proxiesData: ProxiesData(proxies: {}, all: []),
        sortType: ProxiesSortType.none,
        delayMap: {},
        selectedMap: {},
        defaultTestUrl: '',
      ),
    );

    expect(groups, isEmpty);
  });

  // GLOBAL 是内核兜底的全量组，mihomo 会把 DIRECT/REJECT 和全部分组都塞进它的
  // 成员列表；这些条目在页签栏都被过滤，单独冒在 GLOBAL 页签里只会造成困惑。
  // 策略组也一样（2026-09-26 用户实测）：组已有自己的页签，再以卡片形态出现在
  // GLOBAL 节点列表里就像「页签掉进了节点列表」—— GLOBAL 只保留节点。
  test('buildGroups keeps only nodes in GLOBAL', () async {
    final proxies = <String, dynamic>{
      'GLOBAL': {
        'name': 'GLOBAL',
        'type': 'Selector',
        'all': ['HK-01', 'DIRECT', 'REJECT', '广告拦截', '节点选择'],
      },
      '节点选择': {
        'name': '节点选择',
        'type': 'Selector',
        'all': ['HK-01'],
      },
      '广告拦截': {
        'name': '广告拦截',
        'type': 'Selector',
        'hidden': true,
        'all': ['REJECT'],
      },
      'HK-01': {'name': 'HK-01', 'type': 'Direct'},
      'DIRECT': {'name': 'DIRECT', 'type': 'Direct'},
      'REJECT': {'name': 'REJECT', 'type': 'Reject'},
    };
    final groups = await buildGroups(
      ComputeGroupsState(
        proxiesData: ProxiesData(
          all: const ['GLOBAL', '节点选择'],
          proxies: proxies,
        ),
        sortType: ProxiesSortType.none,
        delayMap: const {},
        selectedMap: const {},
        defaultTestUrl: '',
      ),
    );

    final global = groups.firstWhere((group) => group.name == 'GLOBAL');
    expect(global.all.map((proxy) => proxy.name), ['HK-01']);
    // 其它组不受影响。
    final select = groups.firstWhere((group) => group.name == '节点选择');
    expect(select.all.map((proxy) => proxy.name), ['HK-01']);
  });

  test(
    'makeRealProfileTask normalizes runtime config and added rules',
    () async {
      final rawConfig = await decodeJSONTask<Map<String, dynamic>>(
        await encodeJSONTask({
          'dns': {
            'enable': true,
            'nameserver': ['1.1.1.1'],
          },
          'sniffer': {
            'sniff': {
              'HTTP': {
                'ports': [80, '443'],
              },
            },
          },
          'proxy-providers': {
            'remote': {'type': 'http', 'url': 'https://example.com/proxy.yaml'},
            'file': {'type': 'file', 'path': './local.yaml'},
          },
          'rule-providers': {
            'remote': {'type': 'http', 'url': 'https://example.com/rule.yaml'},
          },
          'rules': ['DOMAIN,existing.example,DIRECT', 'MATCH,Original'],
        }),
      );
      final result = await makeRealProfileTask(
        MakeRealProfileState(
          profilesPath: '/profiles',
          profileId: 7,
          rawConfig: rawConfig,
          realPatchConfig: const PatchClashConfig(
            mixedPort: 7893,
            port: 7890,
            socksPort: 7891,
            redirPort: 7892,
            tproxyPort: 7894,
            allowLan: true,
            ipv6: true,
            hosts: {'router.local': '192.168.1.1,192.168.1.2'},
          ),
          overrideDns: false,
          appendSystemDns: true,
          proxyGroups: const [],
          rules: const [],
          addedRules: const [
            Rule(
              ruleAction: RuleAction.DOMAIN_SUFFIX,
              content: 'added.example',
              ruleTarget: 'MATCH',
            ),
          ],
          defaultUA: 'FlClash-Test',
        ),
      );
      final config = loadYaml(result.yaml) as YamlMap;

      expect(result.md5, hasLength(32));
      expect(config['mixed-port'], 7893);
      expect(config['allow-lan'], true);
      expect(config['global-ua'], 'FlClash-Test');
      expect(config['profile']['store-selected'], false);
      expect(
        config['dns']['nameserver'],
        containsAll(['1.1.1.1', 'system://']),
      );
      expect(config['hosts']['router.local'], ['192.168.1.1', '192.168.1.2']);
      expect(config['sniffer']['sniff']['HTTP']['ports'], ['80', '443']);
      // `confineProviders` builds these paths with `p.join`, so they come out
      // `\`-separated on Windows; the segment layout is what this test owns.
      expect(
        (config['proxy-providers']['remote']['path'] as String).replaceAll(
          r'\',
          '/',
        ),
        startsWith('/profiles/providers/7/proxies/'),
      );
      expect(
        (config['rule-providers']['remote']['path'] as String).replaceAll(
          r'\',
          '/',
        ),
        startsWith('/profiles/providers/7/rules/'),
      );
      expect(config['rules'], [
        'DOMAIN-SUFFIX,added.example,Original',
        'DOMAIN,existing.example,DIRECT',
        'MATCH,Original',
      ]);
    },
  );

  test(
    'makeRealProfileTask routes MATCH placeholders to matchTarget',
    () async {
      final rawConfig = await decodeJSONTask<Map<String, dynamic>>(
        await encodeJSONTask({
          'proxies': [],
          'rules': ['DOMAIN,existing.example,DIRECT', 'MATCH,Original'],
        }),
      );
      final state = MakeRealProfileState(
        profilesPath: '/profiles',
        profileId: 7,
        rawConfig: rawConfig,
        realPatchConfig: const PatchClashConfig(),
        overrideDns: false,
        appendSystemDns: false,
        proxyGroups: const [],
        rules: const [],
        addedRules: const [
          Rule(
            ruleAction: RuleAction.DOMAIN_SUFFIX,
            content: 'added.example',
            ruleTarget: 'MATCH',
          ),
        ],
        defaultUA: 'FlClash-Test',
        matchTarget: 'HK',
      );

      final overridden = await makeRealProfileTask(state);
      expect((loadYaml(overridden.yaml) as YamlMap)['rules'], [
        'DOMAIN-SUFFIX,added.example,HK',
        'DOMAIN,existing.example,DIRECT',
        'MATCH,Original',
      ]);

      final blank = await makeRealProfileTask(state.copyWith(matchTarget: ' '));
      expect(
        (loadYaml(blank.yaml) as YamlMap)['rules'].first,
        'DOMAIN-SUFFIX,added.example,Original',
      );
    },
  );

  // The core re-reads these two keys out of the generated config on every
  // profile apply and adopts whatever it finds, so a subscription that ships
  // them would otherwise decide whether GEO databases auto-update — including
  // switching the updater back on after the user turned it off.
  test(
    'makeRealProfileTask lets the app setting own the geo updater',
    () async {
      final rawConfig = await decodeJSONTask<Map<String, dynamic>>(
        await encodeJSONTask({
          'geo-auto-update': true,
          'geo-update-interval': 6,
        }),
      );

      final result = await makeRealProfileTask(
        MakeRealProfileState(
          profilesPath: '/profiles',
          profileId: 11,
          rawConfig: rawConfig,
          realPatchConfig: const PatchClashConfig(
            geoAutoUpdate: false,
            geoUpdateInterval: 48,
          ),
          overrideDns: false,
          appendSystemDns: false,
          proxyGroups: const [],
          rules: const [],
          addedRules: const [],
          defaultUA: 'FlClash-Test',
        ),
      );
      final config = loadYaml(result.yaml) as YamlMap;

      expect(config['geo-auto-update'], false);
      expect(config['geo-update-interval'], 48);
    },
  );

  // A profile-shipped loopback skip-auth-prefixes would bypass the credentials.
  test('makeRealProfileTask lets the app own local authentication', () async {
    final rawConfig = await decodeJSONTask<Map<String, dynamic>>(
      await encodeJSONTask({
        'authentication': ['subscription:injected'],
        'skip-auth-prefixes': ['127.0.0.1/32'],
      }),
    );
    final state = MakeRealProfileState(
      profilesPath: '/profiles',
      profileId: 12,
      rawConfig: rawConfig,
      realPatchConfig: const PatchClashConfig(),
      overrideDns: false,
      appendSystemDns: false,
      proxyGroups: const [],
      rules: const [],
      addedRules: const [],
      defaultUA: 'FlClash-Test',
      authentication: const ['user:pass'],
    );

    final enabled = await makeRealProfileTask(state);
    final enabledConfig = loadYaml(enabled.yaml) as YamlMap;
    expect(enabledConfig['authentication'], ['user:pass']);
    expect(enabledConfig['skip-auth-prefixes'], isEmpty);

    final disabled = await makeRealProfileTask(
      state.copyWith(authentication: const []),
    );
    final disabledConfig = loadYaml(disabled.yaml) as YamlMap;
    expect(disabledConfig['authentication'], isEmpty);
    expect(disabledConfig['skip-auth-prefixes'], isEmpty);
  });

  test('makeRealProfileTask overrides DNS and explicit custom data', () async {
    final result = await makeRealProfileTask(
      const MakeRealProfileState(
        profilesPath: '/profiles',
        profileId: 9,
        rawConfig: {},
        realPatchConfig: PatchClashConfig(),
        overrideDns: true,
        appendSystemDns: false,
        proxyGroups: [
          ProxyGroup(
            id: 1,
            name: 'Select',
            type: GroupType.Selector,
            proxies: ['DIRECT'],
          ),
        ],
        rules: [
          Rule(
            ruleAction: RuleAction.DOMAIN,
            content: 'custom.example',
            ruleTarget: 'DIRECT',
          ),
        ],
        addedRules: [],
        defaultUA: 'Fallback-UA',
      ),
    );
    final config = loadYaml(result.yaml) as YamlMap;

    expect(config['dns']['enable'], true);
    expect(config['dns']['nameserver'], isNot(contains('system://')));
    expect(config['proxy-groups'], hasLength(1));
    expect(config['rules'], ['DOMAIN,custom.example,DIRECT']);
  });

  test('makeRealProfileTask keeps the DNS keys it cannot edit', () async {
    final rawConfig = await decodeJSONTask<Map<String, dynamic>>(
      await encodeJSONTask({
        'dns': {
          'enable': false,
          'direct-nameserver': ['223.5.5.5'],
          'proxy-server-nameserver-policy': {
            'www.example.com': ['8.8.8.8'],
          },
          'nameserver': ['9.9.9.9'],
        },
        'proxy-providers': {
          'first': {'type': 'http', 'url': 'https://example.com/shared.yaml'},
          'second': {'type': 'http', 'url': 'https://example.com/shared.yaml'},
        },
      }),
    );

    final result = await makeRealProfileTask(
      MakeRealProfileState(
        profilesPath: '/profiles',
        profileId: 13,
        rawConfig: rawConfig,
        realPatchConfig: const PatchClashConfig(),
        overrideDns: false,
        appendSystemDns: false,
        proxyGroups: const [],
        rules: const [],
        addedRules: const [],
        defaultUA: 'FlClash-Test',
      ),
    );
    final config = loadYaml(result.yaml) as YamlMap;

    expect(config['dns']['direct-nameserver'], ['223.5.5.5']);
    expect(config['dns']['proxy-server-nameserver-policy'], {
      'www.example.com': ['8.8.8.8'],
    });
    expect(config['dns']['nameserver'], isNot(contains('system://')));
    expect(
      config['proxy-providers']['first']['path'],
      isNot(config['proxy-providers']['second']['path']),
    );
  });

  group('makeRealProfileTask interface-name mode', () {
    Future<YamlMap> runWith(PatchClashConfig realPatchConfig) async {
      final rawConfig = await decodeJSONTask<Map<String, dynamic>>(
        await encodeJSONTask({'interface-name': 'en0'}),
      );

      final result = await makeRealProfileTask(
        MakeRealProfileState(
          profilesPath: '/profiles',
          profileId: 13,
          rawConfig: rawConfig,
          realPatchConfig: realPatchConfig,
          overrideDns: false,
          appendSystemDns: false,
          proxyGroups: const [],
          rules: const [],
          addedRules: const [],
          defaultUA: 'FlClash-Test',
        ),
      );
      return loadYaml(result.yaml) as YamlMap;
    }

    // Default mode, so a subscription value must not survive into the
    // generated config.
    test('clear forces interface-name empty', () async {
      final config = await runWith(const PatchClashConfig());

      expect(config['interface-name'], '');
    });

    test('follow leaves the profile value untouched', () async {
      final config = await runWith(
        const PatchClashConfig(interfaceNameMode: InterfaceNameMode.follow),
      );

      expect(config['interface-name'], 'en0');
    });

    test('custom writes the configured interface name', () async {
      final config = await runWith(
        const PatchClashConfig(
          interfaceNameMode: InterfaceNameMode.custom,
          interfaceName: 'eth0',
        ),
      );

      expect(config['interface-name'], 'eth0');
    });
  });

  group('makeRealProfileTask legacy provider file migration', () {
    late Directory tempDir;
    const url = 'https://example.com/proxy.yaml';
    const name = 'remote';

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('task_test_providers');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    Future<({String legacyPath, String newPath})> runMigration() async {
      final providerDir = join(
        tempDir.path,
        providersDirectoryName,
        '17',
        proxiesProviderDirectoryName,
      );
      final legacyPath = join(providerDir, url.toMd5());
      final newPath = join(providerDir, '$name@$url'.toMd5());

      final result = await makeRealProfileTask(
        MakeRealProfileState(
          profilesPath: tempDir.path,
          profileId: 17,
          rawConfig: {
            'proxy-providers': {
              name: {'type': 'http', 'url': url},
            },
          },
          realPatchConfig: const PatchClashConfig(),
          overrideDns: false,
          appendSystemDns: false,
          proxyGroups: const [],
          rules: const [],
          addedRules: const [],
          defaultUA: 'FlClash-Test',
        ),
      );
      final config = loadYaml(result.yaml) as YamlMap;
      expect(config['proxy-providers'][name]['path'], newPath);
      return (legacyPath: legacyPath, newPath: newPath);
    }

    test('renames a file cached under the legacy url-only key', () async {
      final providerDir = join(
        tempDir.path,
        providersDirectoryName,
        '17',
        proxiesProviderDirectoryName,
      );
      await Directory(providerDir).create(recursive: true);
      final legacyFile = File(join(providerDir, url.toMd5()));
      await legacyFile.writeAsString('cached-provider-data');

      final paths = await runMigration();

      expect(File(paths.newPath).existsSync(), isTrue);
      expect(await File(paths.newPath).readAsString(), 'cached-provider-data');
      expect(File(paths.legacyPath).existsSync(), isFalse);
    });

    test('is a no-op when no legacy file exists', () async {
      final paths = await runMigration();

      expect(File(paths.legacyPath).existsSync(), isFalse);
      expect(File(paths.newPath).existsSync(), isFalse);
    });
  });

  test('log and list tasks produce stable mapped output', () async {
    final logs = [
      const Log(
        logLevel: LogLevel.info,
        payload: 'first',
        dateTime: '2026-07-26 10:00:00',
      ),
      const Log(
        logLevel: LogLevel.error,
        payload: 'second',
        dateTime: '2026-07-26 10:00:01',
      ),
    ];

    final encoded = await encodeLogsTask(logs);

    expect(encoded, contains('first'));
    expect(encoded, contains('\n'));
    expect(await mapListTask([1, 2, 3], _double), [2, 4, 6]);
  });

  test('filterGlobalGroupMembers removes only injected chain names', () {
    final all = const [
      Proxy(name: '普通节点', type: 'Shadowsocks'),
      Proxy(name: '链式代理1', type: 'Shadowsocks'),
      Proxy(name: '前置节点', type: 'Shadowsocks'),
    ];
    final injected = {'链式代理1', '前置节点'};

    final filtered = filterGlobalGroupMembers(all, injected);
    expect(filtered.map((proxy) => proxy.name), ['普通节点']);

    // 空集合直通，且不改变原列表。
    expect(filterGlobalGroupMembers(all, const {}), same(all));
    expect(filterGlobalGroupMembers(const [], injected), isEmpty);
  });

  group('injectProxyChains merges chain names into the selector group', () {
    Map<String, dynamic> baseConfig() => {
      'proxies': [
        {'name': '出口节点', 'type': 'ss', 'server': 'a.com', 'port': 443},
        {'name': '前置节点', 'type': 'ss', 'server': 'b.com', 'port': 443},
      ],
      'proxy-groups': [
        {
          'name': '节点选择',
          'type': 'select',
          'proxies': ['出口节点', '自动选择'],
        },
        {
          'name': '自动选择',
          'type': 'url-test',
          'proxies': ['出口节点'],
        },
      ],
      'rules': ['MATCH,节点选择'],
    };

    List<ProxyChain> oneChain() => [
      ProxyChain(
        name: '链式代理1',
        exitName: '出口节点',
        exitNode: {
          'name': '出口节点',
          'type': 'ss',
          'server': 'a.com',
          'port': 443,
        },
        dialer: '前置节点',
        createdAt: 1,
      ),
    ];

    Map<String, dynamic> selectorOf(Map<String, dynamic> config) {
      return (config['proxy-groups'] as List)
          .whereType<Map>()
          .firstWhere((group) => group['name'] == '节点选择')
          .cast<String, dynamic>();
    }

    test('appends chain names to the end of the selector group', () {
      final config = baseConfig();
      injectProxyChains(
        config,
        chains: oneChain(),
        groupName: '链式代理',
        autoGroupName: '自动选择',
        selectorGroupName: '节点选择',
      );

      expect(selectorOf(config)['proxies'], ['出口节点', '自动选择', '链式代理1']);
    });

    test('is idempotent across repeated injections', () {
      final config = baseConfig();
      for (var i = 0; i < 3; i++) {
        injectProxyChains(
          config,
          chains: oneChain(),
          groupName: '链式代理',
          autoGroupName: '自动选择',
          selectorGroupName: '节点选择',
        );
        expect(selectorOf(config)['proxies'], ['出口节点', '自动选择', '链式代理1']);
      }
    });

    test('does not touch a selector group of the wrong type', () {
      final config = baseConfig();
      (config['proxy-groups'] as List).firstWhere((group) {
        return group is Map && group['name'] == '节点选择';
      })['type'] = 'url-test';

      injectProxyChains(
        config,
        chains: oneChain(),
        groupName: '链式代理',
        autoGroupName: '自动选择',
        selectorGroupName: '节点选择',
      );

      expect(selectorOf(config)['proxies'], ['出口节点', '自动选择']);
    });

    test('survives a missing selector group', () {
      final config = baseConfig();
      final injected = injectProxyChains(
        config,
        chains: oneChain(),
        groupName: '链式代理',
        autoGroupName: '自动选择',
        selectorGroupName: '不存在的主组',
      );

      expect(injected.chainNames, ['链式代理1']);
      expect(
        (config['proxy-groups'] as List).whereType<Map>().map(
          (group) => group['name'],
        ),
        contains('节点选择'),
      );
    });
  });

  test('filterGroupMemberCards hides groups and built-in outbounds', () {
    final all = const [
      Proxy(name: '自动选择', type: 'URLTest'),
      Proxy(name: '故障转移', type: 'Fallback'),
      Proxy(name: 'DIRECT', type: 'Direct'),
      Proxy(name: 'vl-reality-instance', type: 'Vless'),
      Proxy(name: 'hy2-instance', type: 'Hysteria2'),
      Proxy(name: '链式代理1', type: 'Shadowsocks'),
    ];

    final filtered = filterGroupMemberCards(all);
    expect(filtered.map((proxy) => proxy.name), [
      'vl-reality-instance',
      'hy2-instance',
      '链式代理1',
    ]);

    // 真节点直通：空列表与纯节点列表原样返回内容。
    expect(filterGroupMemberCards(const []), isEmpty);
    expect(
      filterGroupMemberCards(const [Proxy(name: '裸节点', type: 'Trojan')]),
      everyElement(isA<Proxy>()),
    );
  });
}
