import 'package:fl_clash/common/proxy_region.dart';
import 'package:test/test.dart';

/// 样品全部取自**真实订阅**（`%APPDATA%\BiLoom` 里那份 269 节点的配置），
/// 不是编出来的。这个模块的价值全在「真实名字能不能认对、会不会认错」，
/// 所以测例必须长这样。
void main() {
  group('机场三字码', () {
    test('运营商专线：移动/联通/电信 + 机场码', () {
      expect(resolveProxyRegion('移动-HKG-443-WS-TLS').code, 'HK');
      expect(resolveProxyRegion('移动-HKG-443-WS-TLS-04').code, 'HK');
      expect(resolveProxyRegion('联通-LAX-443-WS-TLS').code, 'US');
      expect(resolveProxyRegion('联通-LAX-443-xhttp-08').code, 'US');
      expect(resolveProxyRegion('电信-SIN-443-Trojan-WS-TLS').code, 'SG');
      expect(resolveProxyRegion('电信-AMS-443-WS-TLS').code, 'NL');
      expect(resolveProxyRegion('电信-FRA-443-xhttp').code, 'DE');
      expect(resolveProxyRegion('移动-SEA-443-WS-TLS-01').code, 'US');
      expect(resolveProxyRegion('联通-HKG-443-xhttp').code, 'HK');
    });

    test('同一国家不同机场归到同一个地区码', () {
      expect(resolveProxyRegion('LAX-01').code, 'US');
      expect(resolveProxyRegion('SEA-01').code, 'US');
      expect(resolveProxyRegion('JFK-01').code, 'US');
    });
  });

  group('国家码', () {
    test('独立的两位大写 token', () {
      expect(resolveProxyRegion('US-443-WS-TLS').code, 'US');
      expect(resolveProxyRegion('SG-443-Trojan-WS-TLS').code, 'SG');
      expect(resolveProxyRegion('HK-01').code, 'HK');
    });
  });

  group('Cloudflare 中转', () {
    test('明确带 CF 特征的标成 cdn，而不是猜一个落地', () {
      for (final name in [
        'bestcf.top-443-WS-TLS',
        'cf.0sm.com-443-xhttp',
        'cf.090227.xyz-443-WS-TLS',
        'cf.zhetengsha.eu.org-443-Trojan-WS-TLS',
        'cfip.cfcdn.vip-443-WS-TLS',
        'cfip.1323123.xyz-443-xhttp',
        'cloudflare.182682.xyz-443-WS-TLS',
        'cloudflare-ip.mofashi.ltd-443-WS-TLS',
        'freeyx.cloudflare88.eu.org-443-Trojan-WS-TLS',
      ]) {
        expect(
          resolveProxyRegion(name).kind,
          ProxyRegionKind.cdn,
          reason: '$name 应识别为 CF 中转',
        );
      }
    });
  });

  group('完全没有线索时老实说不知道', () {
    test('未知节点归 unknown —— 绝不硬猜', () {
      // 这几个域名实测确实解析到 Cloudflare 的 IP（`c.ali88.site → 104.21.3.153`），
      // 但**名字本身给不出落地**，所以只能是 unknown。
      // 拿 IP 去查 GeoIP 得到的是 CF 边缘位置，标上去就是编。
      for (final name in [
        'c.ali88.site',
        '原生地址-443-WS-TLS',
        '原生地址-443-Trojan-WS-TLS',
        'speed.marisalnc.com-443-WS-TLS',
        'cdn.2020111.xyz-443-xhttp',
        'cnamefuckxxs.yuchen.icu-443-WS-TLS',
        '',
        '   ',
      ]) {
        expect(
          resolveProxyRegion(name).kind,
          ProxyRegionKind.unknown,
          reason: '「$name」不该被猜出地区',
        );
      }
    });
  });

  group('误判防线', () {
    test('子串陷阱：域名片段被切出来后不得当地区码', () {
      // `site` 含 `in`（印度）、`top` 含 `to`（汤加）、`to` 本身是汤加码。
      // 只认「全大写独立 token」就是为了挡住这一类。
      expect(resolveProxyRegion('c.ali88.site').isCountry, isFalse);
      expect(resolveProxyRegion('bestcf.top-443-WS-TLS').code, isNot('TO'));
      expect(resolveProxyRegion('xn--b6gac.eu.org').isCountry, isFalse);
    });

    test('协议词不得当地区码', () {
      // WS = 萨摩亚、SS = 南苏丹、CF = 中非 —— 这三个在这里都是协议/服务名。
      expect(resolveProxyRegion('foo-WS-443').isCountry, isFalse);
      expect(resolveProxyRegion('foo-SS-443').isCountry, isFalse);
      expect(resolveProxyRegion('foo-443-WS-TLS').isCountry, isFalse);
    });

    test('小写 token 不参与地区码匹配', () {
      // `us`/`sg` 小写多半是域名片段，不能当美国/新加坡。
      expect(resolveProxyRegion('myus-server.example.com').isCountry, isFalse);
      expect(resolveProxyRegion('best-sg.node.xyz').isCountry, isFalse);
    });
  });

  group('名字里自带地区信息时优先用名字', () {
    test('国旗 emoji', () {
      expect(resolveProxyRegion('🇭🇰 香港 01').code, 'HK');
      expect(resolveProxyRegion('🇺🇸 洛杉矶').code, 'US');
      expect(resolveProxyRegion('🇸🇬SG-01').code, 'SG');
    });

    test('中文地区名', () {
      expect(resolveProxyRegion('香港节点').code, 'HK');
      expect(resolveProxyRegion('中国香港 01').code, 'HK');
      expect(resolveProxyRegion('日本 东京').code, 'JP');
      expect(resolveProxyRegion('美国 洛杉矶').code, 'US');
    });

    test('英文地区全名', () {
      expect(resolveProxyRegion('Hong Kong 01').code, 'HK');
      expect(resolveProxyRegion('Tokyo Japan').code, 'JP');
      expect(resolveProxyRegion('Los Angeles, United States').code, 'US');
    });
  });

  group('countryCodeToEmoji', () {
    test('两位字母转国旗', () {
      expect(countryCodeToEmoji('HK'), '🇭🇰');
      expect(countryCodeToEmoji('hk'), '🇭🇰');
      expect(countryCodeToEmoji('US'), '🇺🇸');
      expect(countryCodeToEmoji('JP'), '🇯🇵');
    });

    test('非法输入原样返回，不抛异常', () {
      expect(countryCodeToEmoji(''), '');
      expect(countryCodeToEmoji('H'), 'H');
      expect(countryCodeToEmoji('HKG'), 'HKG');
      expect(countryCodeToEmoji('12'), '12');
    });
  });

  group('ProxyRegion.ofCountry', () {
    test('只收已收录的码', () {
      expect(ProxyRegion.ofCountry('HK')?.code, 'HK');
      expect(ProxyRegion.ofCountry(' hk ')?.code, 'HK');
      // 没进词条表的码不输出，否则卡片上会显示裸码。
      expect(ProxyRegion.ofCountry('XX'), isNull);
      expect(ProxyRegion.ofCountry(''), isNull);
      expect(ProxyRegion.ofCountry('HKG'), isNull);
    });

    test('常量实例的语义', () {
      expect(ProxyRegion.cdn.isCdn, isTrue);
      expect(ProxyRegion.cdn.isCountry, isFalse);
      expect(ProxyRegion.unknown.isUnknown, isTrue);
      expect(ProxyRegion.cdn.emoji, '☁️');
      expect(ProxyRegion.ofCountry('HK')?.emoji, '🇭🇰');
    });

    test('值相等（Riverpod family 缓存依赖它）', () {
      expect(ProxyRegion.ofCountry('HK'), ProxyRegion.ofCountry('hk'));
      expect(ProxyRegion.cdn, ProxyRegion.cdn);
      expect(ProxyRegion.cdn == ProxyRegion.unknown, isFalse);
    });
  });

  group('地名表与识别表必须对齐', () {
    test('每个识别得出的码都叫得出名字 —— 否则卡片上会显示裸码', () {
      expect(knownRegionCodes, isNotEmpty);
      for (final code in knownRegionCodes) {
        expect(
          localizedRegionName(code, 'zh'),
          isNotNull,
          reason: '$code 没进 _regionNames，卡片上会显示裸码',
        );
      }
    });

    test('港澳台带「中国」前缀（不是独立国家）', () {
      expect(localizedRegionName('HK', 'zh_CN'), '中国香港');
      expect(localizedRegionName('MO', 'zh_CN'), '中国澳门');
      expect(localizedRegionName('TW', 'zh_CN'), '中国台湾');
      expect(localizedRegionName('HK', 'en'), 'Hong Kong, China');
      expect(localizedRegionName('MO', 'en'), 'Macao, China');
      expect(localizedRegionName('TW', 'en'), 'Taiwan, China');
    });

    test('四种语言都能取到名字，认不出的语言按英文兜底', () {
      expect(localizedRegionName('HK', 'zh_CN'), '中国香港');
      expect(localizedRegionName('HK', 'en'), 'Hong Kong, China');
      expect(localizedRegionName('HK', 'ja'), '中国香港');
      expect(localizedRegionName('HK', 'ru'), 'Гонконг, Китай');
      expect(localizedRegionName('HK', 'de'), 'Hong Kong, China');
      expect(localizedRegionName('hk', 'zh'), '中国香港');
      expect(localizedRegionName('XX', 'zh'), isNull);
    });
  });

  group('ProxyRegion.key', () {
    test('稳定、不随界面语言变化', () {
      // 筛选状态里存的就是它 —— 一变语言筛选就失效的话，用户会以为筛选坏了。
      expect(ProxyRegion.ofCountry('HK')!.key, 'HK');
      expect(ProxyRegion.ofCountry('hk')!.key, 'HK');
      expect(ProxyRegion.cdn.key, 'cdn');
      expect(ProxyRegion.unknown.key, '');
    });
  });

  group('按地区分桶', () {
    test('节点多的地区在前，认不出地区的桶固定最后', () {
      final buckets = groupProxyNamesByRegion([
        '移动-HKG-443-WS-TLS',
        '移动-HKG-443-WS-TLS-01',
        'US-443-WS-TLS',
        'c.ali88.site',
      ]);
      expect(buckets.groups.map((group) => group.region.key).toList(), [
        'HK',
        'US',
        '',
      ]);
      expect(buckets.groupOf('HK')!.count, 2);
      expect(buckets.total, 4);
      expect(buckets.unknownGroup!.count, 1);
    });

    test('数量相同时按地区码升序 —— 顺序稳定，芯片不会自己跳', () {
      final buckets = groupProxyNamesByRegion([
        'US-443-WS-TLS',
        'JP-443-WS-TLS',
        'HK-443-WS-TLS',
      ]);
      expect(buckets.groups.map((group) => group.region.key).toList(), [
        'HK',
        'JP',
        'US',
      ]);
    });

    test('重名去重 —— 同一节点在多个分组里出现只算一次', () {
      // 「代理」页是拿所有分组的节点来分桶的，GLOBAL 会把每个节点再列一遍。
      final buckets = groupProxyNamesByRegion([
        'US-443-WS-TLS',
        'US-443-WS-TLS',
        'US-443-WS-TLS',
      ]);
      expect(buckets.groupOf('US')!.count, 1);
      expect(buckets.total, 1);
    });

    test('认不出的节点也要进桶（键是空串），不能被吞掉', () {
      // 真实订阅 224 个节点里有 34 个认不出 —— 藏起来等于让这些节点没有入口。
      final buckets = groupProxyNamesByRegion([
        'c.ali88.site',
        '原生地址-443-WS-TLS',
      ]);
      expect(buckets.groups.length, 1);
      expect(buckets.unknownGroup!.proxyNames.length, 2);
      expect(buckets.groupOf('')!.region.isUnknown, isTrue);
    });

    test('空输入不炸', () {
      expect(groupProxyNamesByRegion(const <String>[]).isEmpty, isTrue);
      expect(groupProxyNamesByRegion(const <String>[]).total, 0);
    });
  });

  group('筛选键收敛', () {
    test('地区还在就照常筛', () {
      final buckets = groupProxyNamesByRegion(['US-443-WS-TLS']);
      expect(resolveEffectiveRegionFilter(buckets: buckets, key: 'US'), 'US');
    });

    test('地区已经不在这批节点里 → 当作不筛，而不是筛出一片空白', () {
      final buckets = groupProxyNamesByRegion(['US-443-WS-TLS']);
      expect(resolveEffectiveRegionFilter(buckets: buckets, key: 'HK'), isNull);
      expect(resolveEffectiveRegionFilter(buckets: buckets, key: null), isNull);
    });

    test('「其他」桶的键是空串，也必须被当成有效筛选', () {
      final buckets = groupProxyNamesByRegion(['c.ali88.site']);
      expect(resolveEffectiveRegionFilter(buckets: buckets, key: ''), '');
    });
  });

  group('像不像我们生成的组', () {
    test('组名认得出地区 + 成员全是同一个地区 → 像', () {
      expect(
        looksLikeGeneratedRegionGroup(
          const ExistingRegionGroup(
            name: '🇭🇰 HK',
            proxyNames: ['移动-HKG-443-WS-TLS', 'HK-01'],
          ),
        ),
        isTrue,
      );
    });

    test('成员混了别的地区 → 不是我们的，既不重写也不删', () {
      // 用户自建的「香港节点」里塞了几个日本节点 —— 一删就是删掉他攒的组。
      expect(
        looksLikeGeneratedRegionGroup(
          const ExistingRegionGroup(
            name: '🇭🇰 HK',
            proxyNames: ['移动-HKG-443-WS-TLS', 'US-443-WS-TLS'],
          ),
        ),
        isFalse,
      );
    });

    test('带 use: 的组一律不碰 —— 它的成员来自 provider，不是节点名', () {
      expect(
        looksLikeGeneratedRegionGroup(
          const ExistingRegionGroup(
            name: '🇭🇰 HK',
            proxyNames: ['移动-HKG-443-WS-TLS'],
            hasProviderSource: true,
          ),
        ),
        isFalse,
      );
    });

    test('组名认不出地区、或成员为空 → 不是我们的', () {
      expect(
        looksLikeGeneratedRegionGroup(
          const ExistingRegionGroup(
            name: '手动分组',
            proxyNames: ['US-443-WS-TLS'],
          ),
        ),
        isFalse,
      );
      expect(
        looksLikeGeneratedRegionGroup(
          const ExistingRegionGroup(name: '🇭🇰 HK', proxyNames: []),
        ),
        isFalse,
      );
    });

    test('CF 中转的组名能被自己认回来 —— 四种语言都要', () {
      // 认不回来的话，每点一次「生成」都会再建一个 CF 组，旧的那个还永远删不掉。
      // 这个名字是 `'${region.emoji} ${region.label}'` 拼出来的，所以四种语言的
      // label 都得落在 `_looksLikeCloudflare` 的判据里。
      for (final name in [
        '☁️ CF 中转',
        '☁️ CF relay',
        '☁️ CF 中継',
        '☁️ CF-релей',
      ]) {
        expect(resolveProxyRegion(name).isCdn, isTrue, reason: name);
      }
    });
  });

  group('按地区生成分组的计划', () {
    test('全新创建：只出真实的地区桶，「其他」不归组', () {
      final plan = buildRegionGroupPlan(
        nodeNames: const [
          '移动-HKG-443-WS-TLS',
          'US-443-WS-TLS',
          'US-444-WS-TLS',
          'c.ali88.site',
        ],
        existingGroups: const [],
        nameOf: _testNameOf,
      );
      expect(plan.upserts.map((RegionGroupDraft d) => d.name).toList(), [
        '🇺🇸 US',
        '🇭🇰 HK',
      ]);
      expect(plan.createdCount, 2);
      expect(plan.updatedCount, 0);
      expect(plan.groupedNodeCount, 3);
      expect(plan.unknownCount, 1);
      expect(plan.removals, isEmpty);
      expect(plan.isEmpty, isFalse);
    });

    test('已经有同地区的组 → 认领它（改名与规则引用由 put 连带处理）', () {
      final plan = buildRegionGroupPlan(
        nodeNames: const ['移动-HKG-443-WS-TLS', 'HK-01'],
        existingGroups: const [
          ExistingRegionGroup(
            name: '🇭🇰 HK',
            proxyNames: ['移动-HKG-443-WS-TLS'],
          ),
        ],
        nameOf: _testNameOf,
      );
      expect(plan.upserts.length, 1);
      expect(plan.upserts.first.existingName, '🇭🇰 HK');
      expect(plan.upserts.first.isUpdate, isTrue);
      expect(plan.updatedCount, 1);
      // 刷成「当前所有香港节点」，而不是留着旧名单。
      expect(plan.upserts.first.proxyNames.length, 2);
      expect(plan.removals, isEmpty);
    });

    test('换过界面语言：名字对不上就按地区认领，不另建一个', () {
      // 上次用中文建的 `🇭🇰 中国香港`，这次界面是英文，nameOf 给出 `🇭🇰 HK`。
      // 只按名字找的话会新建一个，把旧的留成孤儿。
      final plan = buildRegionGroupPlan(
        nodeNames: const ['移动-HKG-443-WS-TLS'],
        existingGroups: const [
          ExistingRegionGroup(
            name: '🇭🇰 中国香港',
            proxyNames: ['移动-HKG-443-WS-TLS'],
          ),
        ],
        nameOf: _testNameOf,
      );
      expect(plan.upserts.first.name, '🇭🇰 HK');
      expect(plan.upserts.first.existingName, '🇭🇰 中国香港');
      expect(plan.removals, isEmpty);
    });

    test('节点没了 → 旧组要移除（留着会让整份配置加载失败）', () {
      final plan = buildRegionGroupPlan(
        nodeNames: const ['US-443-WS-TLS'],
        existingGroups: const [
          ExistingRegionGroup(
            name: '🇭🇰 HK',
            proxyNames: ['移动-HKG-443-WS-TLS'],
          ),
        ],
        nameOf: _testNameOf,
      );
      expect(plan.removals, ['🇭🇰 HK']);
      expect(plan.upserts.length, 1);
      expect(plan.upserts.first.name, '🇺🇸 US');
    });

    test('用户自建的组不误删', () {
      final plan = buildRegionGroupPlan(
        nodeNames: const ['US-443-WS-TLS'],
        existingGroups: const [
          ExistingRegionGroup(name: '手动分组', proxyNames: ['移动-HKG-443-WS-TLS']),
        ],
        nameOf: _testNameOf,
      );
      expect(plan.removals, isEmpty);
    });

    test('带 use: 的组也不误删', () {
      final plan = buildRegionGroupPlan(
        nodeNames: const ['US-443-WS-TLS'],
        existingGroups: const [
          ExistingRegionGroup(
            name: '🇭🇰 HK',
            proxyNames: ['移动-HKG-443-WS-TLS'],
            hasProviderSource: true,
          ),
        ],
        nameOf: _testNameOf,
      );
      expect(plan.removals, isEmpty);
    });

    test('一个地区都认不出时计划是空的 —— 面板据此不给确认按钮', () {
      final plan = buildRegionGroupPlan(
        nodeNames: const ['c.ali88.site', '原生地址-443-WS-TLS'],
        existingGroups: const [],
        nameOf: _testNameOf,
      );
      expect(plan.isEmpty, isTrue);
      expect(plan.unknownCount, 2);
      expect(RegionGroupPlan.empty.isEmpty, isTrue);
    });

    test('CF 中转也归组，组名就是芯片上那个名字', () {
      final plan = buildRegionGroupPlan(
        nodeNames: const ['bestcf.top-443-WS-TLS'],
        existingGroups: const [],
        nameOf: _testNameOf,
      );
      expect(plan.upserts.length, 1);
      expect(plan.upserts.first.region.isCdn, isTrue);
      expect(plan.upserts.first.name, '☁️ CF 中转');
    });

    test('重名节点只算一次（GLOBAL 与子分组会重复列出同一个名字）', () {
      final plan = buildRegionGroupPlan(
        nodeNames: const ['US-443-WS-TLS', 'US-443-WS-TLS'],
        existingGroups: const [],
        nameOf: _testNameOf,
      );
      expect(plan.groupedNodeCount, 1);
    });
  });
}

/// 测试用的组名生成器 —— 模仿真实 `nameOf`（`'${emoji} ${label}'`）的形态，
/// 但不依赖 l10n。CF 那条特意用中文标签：它的名字要能被自己认回来。
String _testNameOf(ProxyRegion region) =>
    region.isCdn ? '☁️ CF 中转' : '${region.emoji} ${region.key}';
