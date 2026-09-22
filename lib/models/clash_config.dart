import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'generated/clash_config.freezed.dart';

part 'generated/clash_config.g.dart';

const defaultClashConfig = PatchClashConfig();

const defaultTun = Tun();

/// 上游 FlClash 原样的 DNS 上游：国内 DoH。
///
/// 留这个常量只有一个用途 —— **存量配置迁移时做精确比对**。只有「一个字节都没被
/// 用户动过」的配置才允许被改写，用户自己填过的（哪怕填的正好是同一个地址）一律不碰。
const legacyDefaultNameservers = <String>[
  'https://doh.pub/dns-query',
  'https://dns.alidns.com/dns-query',
];

/// 默认 DNS 上游：境外 DoH。
///
/// 全部写成 **IP 形式**（而不是 `https://dns.google/dns-query` 这种域名形式）是刻意的：
/// 域名形式的上游必须先靠 `default-nameserver` 把它的域名解析出来才能建连，
/// 而那个引导查询恰好是明文的、最容易被打歪的一环；IP 形式则不需要任何引导解析。
///
/// 国内域名不走这里 —— 见 `Dns.nameserverPolicy` 里的 `geosite:cn`，那条把国内域名
/// 指向国内 DoH，既快又不会被跨境链路拖慢。所以这里的默认值只服务「境外域名」，
/// 它们本来就要出境，把解析也交给出境后的解析器，才和「流量出境」这件事自洽。
const defaultNameservers = <String>[
  'https://1.1.1.1/dns-query',
  'https://1.0.0.1/dns-query',
  'https://8.8.8.8/dns-query',
];

/// 上游 FlClash 原样的备用上游：境外 DoT。同样只用于迁移时精确比对。
const legacyDefaultFallback = <String>['tls://8.8.4.4', 'tls://1.1.1.1'];

/// 上游 FlClash 原样的 `fallback-filter.domain`。只用于迁移时精确比对。
const legacyFallbackFilterDomains = <String>[
  '+.google.com',
  '+.facebook.com',
  '+.youtube.com',
];

/// 默认备用上游：与 `defaultNameservers` 同一批境外 DoH。
///
/// 从 `tls://`（DoT:853）改成 `https://`（DoH:443）是必须的 —— 853 是个特征极明显的
/// 端口，在国内被干扰的概率远高于 443，而这些备用上游一旦被调用就是要救场的，
/// 救场通道本身比主通道更脆弱说不通。
const defaultFallback = <String>[
  'https://8.8.8.8/dns-query',
  'https://1.1.1.1/dns-query',
];

/// 默认 `fallback-filter.domain`：**空**。
///
/// 上游在这里放了 `+.google.com` / `+.facebook.com` / `+.youtube.com`，原因是内核
/// `dns/resolver.go` 的 `shouldOnlyQueryFallback()` 对命中的域名会**跳过 `nameserver`、
/// 只查 `fallback`** —— 上游的主上游是国内 DoH（会被污染），所以让这几个敏感域族
/// 绕开国内解析器直达境外 DoT 是对的。
///
/// 但主上游改成境外 DoH 之后，主路径本身就不可污染了（DoH 走 TLS，运营商只能阻断
/// 连接、无法伪造应答），这个特例就只剩坏处：它让 google/facebook/youtube 反而
/// **不**走新默认的境外 DoH，继续依赖 DoT:853，且 `fallback` 成为唯一通道 ——
/// 一旦 853 被干扰，这三个域族直接解析失败，连备用都没有。
///
/// 清空之后这些域名回到正常路径（境外 DoH）。注意 `fallback` 的定位也随之变了 ——
/// 见 `defaultFallbackFilterGeoip`：关掉那个开关之后，`fallback` 不再是「主上游答案
/// 可疑时的第二意见」，而是**仅在主上游失败时**才顶上的兜底。
const defaultFallbackFilterDomains = <String>[];

/// 上游 FlClash 原样的 `fallback-filter.geoip` 与配套的 `geoip-code`。只用于迁移时精确比对。
///
/// ⚠️ `legacyFallbackFilterGeoipCode` **不是**「当前 `geoip-code` 默认值的镜像」：
/// 当前默认恰好也是 `'CN'`，但它在这里的身份是「上游那一版的历史值」。所以将来若改了
/// `Dns` 里 `geoip-code` 的默认值，这两个 `legacy*` 常量**不能跟着改** —— 它们的职责
/// 是记住「旧配置长什么样」，不是「新配置该长什么样」。
const legacyFallbackFilterGeoip = true;
const legacyFallbackFilterGeoipCode = 'CN';

/// 默认 `fallback-filter.geoip`：**关**。
///
/// 开着的时候，内核会把「`nameserver` 解析出了**不属于** `geoip-code` 的 IP」当作
/// 「主上游的应答可能被污染」的信号，进而**丢弃 `nameserver` 的成功结果、改用 `fallback`
/// 的结果**。判定点在 `rules/common/geoip.go` 的 `DnsFallbackFilter().MatchIp`，它是
/// **取反**的（`return !matcher.Match(ip)`，即「不属于 `geoip-code` 才算命中」），
/// 消费点在 `dns/resolver.go` 的 `ipExchange`：只要这个判定返回 true，流程就会走到最后
/// 那步「无条件把 `fallback` 的结果当作答案返回」—— 哪怕 `nameserver` 已经成功、
/// 而 `fallback` 失败，抛出去的也是 `fallback` 的错误，不会回落到 `nameserver` 的成功结果。
/// 也就是说开着它时，**真正回答问题的是 `fallback`，`nameserver` 被架空**。
///
/// 上游设成 `true` 是合理的：那时主上游是国内 DoH，会被投毒，需要「解析出国外 IP 就可疑」
/// 这条启发式。但主上游已换成境外 DoH —— DoH 走 TLS，运营商只能阻断连接、无法伪造应答，
/// 这条启发式的前提已经不存在，留着它只剩副作用。
///
/// 关掉之后 IP 侧只剩 `ipcidr` 的保留段（`240.0.0.0/4`）这一个过滤器，正常公网 IP
/// 永不命中，于是语义回到本来的样子：**`nameserver` 负责回答，`fallback` 退化为
/// 仅当主上游失败时才顶上的兜底**（`resolver.go:337-341` 那条路径仍然生效）。
const defaultFallbackFilterGeoip = false;

const defaultDns = Dns();
const defaultGeoXUrl = {
  GeoResource.MMDB:
      'https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.metadb',
  GeoResource.ASN:
      'https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/GeoLite2-ASN.mmdb',
  GeoResource.GEOIP:
      'https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat',
  GeoResource.GEOSITE:
      'https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat',
};

const defaultMixedPort = 7890;
const defaultKeepAliveInterval = 30;

const defaultBypassPrivateRouteAddress = [
  '1.0.0.0/8',
  '2.0.0.0/7',
  '4.0.0.0/6',
  '8.0.0.0/7',
  '11.0.0.0/8',
  '12.0.0.0/6',
  '16.0.0.0/4',
  '32.0.0.0/3',
  '64.0.0.0/3',
  '96.0.0.0/4',
  '112.0.0.0/5',
  '120.0.0.0/6',
  '124.0.0.0/7',
  '126.0.0.0/8',
  '128.0.0.0/3',
  '160.0.0.0/5',
  '168.0.0.0/8',
  '169.0.0.0/9',
  '169.128.0.0/10',
  '169.192.0.0/11',
  '169.224.0.0/12',
  '169.240.0.0/13',
  '169.248.0.0/14',
  '169.252.0.0/15',
  '169.255.0.0/16',
  '170.0.0.0/7',
  '172.0.0.0/12',
  '172.32.0.0/11',
  '172.64.0.0/10',
  '172.128.0.0/9',
  '173.0.0.0/8',
  '174.0.0.0/7',
  '176.0.0.0/4',
  '192.0.0.0/9',
  '192.128.0.0/11',
  '192.160.0.0/13',
  '192.169.0.0/16',
  '192.170.0.0/15',
  '192.172.0.0/14',
  '192.176.0.0/12',
  '192.192.0.0/10',
  '193.0.0.0/8',
  '194.0.0.0/7',
  '196.0.0.0/6',
  '200.0.0.0/5',
  '208.0.0.0/4',
  '240.0.0.0/5',
  '248.0.0.0/6',
  '252.0.0.0/7',
  '254.0.0.0/8',
  '255.0.0.0/9',
  '255.128.0.0/10',
  '255.192.0.0/11',
  '255.224.0.0/12',
  '255.240.0.0/13',
  '255.248.0.0/14',
  '255.252.0.0/15',
  '255.254.0.0/16',
  '255.255.0.0/17',
  '255.255.128.0/18',
  '255.255.192.0/19',
  '255.255.224.0/20',
  '255.255.240.0/21',
  '255.255.248.0/22',
  '255.255.252.0/23',
  '255.255.254.0/24',
  '255.255.255.0/25',
  '255.255.255.128/26',
  '255.255.255.192/27',
  '255.255.255.224/28',
  '255.255.255.240/29',
  '255.255.255.248/30',
  '255.255.255.252/31',
  '255.255.255.254/32',
  '::/1',
  '8000::/2',
  'c000::/3',
  'e000::/4',
  'f000::/5',
  'f800::/6',
  'fe00::/9',
  'fec0::/10',
];

@freezed
abstract class ProxyGroup with _$ProxyGroup {
  const factory ProxyGroup({
    int? profileId,
    @JsonKey(fromJson: Snowflake.buildId) required int id,
    required String name,
    required GroupType type,
    List<String>? proxies,
    List<String>? use,
    int? interval,
    bool? lazy,
    @JsonKey(name: 'disable-udp') bool? disableUDP,
    String? url,
    int? timeout,
    @JsonKey(name: 'max-failed-times') int? maxFailedTimes,
    String? filter,
    @JsonKey(name: 'exclude-filter') String? excludeFilter,
    @JsonKey(name: 'exclude-type') String? excludeType,
    @JsonKey(name: 'expected-status') String? expectedStatus,
    @JsonKey(name: 'include-all') bool? includeAll,
    @JsonKey(name: 'include-all-proxies') bool? includeAllProxies,
    @JsonKey(name: 'include-all-providers') bool? includeAllProviders,
    bool? hidden,
    String? icon,
    String? order,
  }) = _ProxyGroup;

  factory ProxyGroup.fromJson(Map<String, Object?> json) =>
      _$ProxyGroupFromJson(json);
}

@freezed
abstract class Proxy with _$Proxy {
  const factory Proxy({
    required String name,
    required String type,
    String? now,
  }) = _Proxy;

  factory Proxy.fromJson(Map<String, Object?> json) => _$ProxyFromJson(json);
}

@freezed
abstract class CustomOverwriteDate with _$CustomOverwriteDate {
  const factory CustomOverwriteDate({
    @Default(false) bool loaded,
    @Default([]) List<String> proxyNames,
    @Default({}) Map<String, String> proxyTypes,
    @Default([]) List<ProxyGroup> proxyGroups,
    @Default({}) Set<String> proxyProviders,
    @Default({}) Set<String> ruleTargets,
    @Default({}) Set<String> subRules,
  }) = _CustomOverwriteDate;
}

@freezed
abstract class CustomOverwriteSelectorState
    with _$CustomOverwriteSelectorState {
  const factory CustomOverwriteSelectorState({
    required bool loaded,
    required List<Proxy> proxies,
    required List<String> subRules,
    required List<String> proxyProviders,
  }) = _CustomOverwriteSelectorState;
}

@freezed
abstract class RuleTargetsSelectorState with _$RuleTargetsSelectorState {
  const factory RuleTargetsSelectorState({
    required bool loaded,
    required Set<String> ruleTargets,
    required Set<String> subRules,
  }) = _RuleTargetsSelectorState;
}

@freezed
abstract class OverwriteIncludeSelectorState
    with _$OverwriteIncludeSelectorState {
  const factory OverwriteIncludeSelectorState({
    required bool includeAll,
    required List<String> names,
  }) = _OverwriteIncludeSelectorState;
}

@freezed
abstract class RuleProvider with _$RuleProvider {
  const factory RuleProvider({required String name}) = _RuleProvider;

  factory RuleProvider.fromJson(Map<String, Object?> json) =>
      _$RuleProviderFromJson(json);
}

@freezed
abstract class ProxyProvider with _$ProxyProvider {
  const factory ProxyProvider({required String name}) = _ProxyProvider;

  factory ProxyProvider.fromJson(Map<String, Object?> json) =>
      _$ProxyProviderFromJson(json);
}

@freezed
abstract class Sniffer with _$Sniffer {
  const factory Sniffer({
    @Default(false) bool enable,
    @Default(true) @JsonKey(name: 'override-destination') bool overrideDest,
    @Default([]) List<String> sniffing,
    @Default([]) @JsonKey(name: 'force-domain') List<String> forceDomain,
    @Default([]) @JsonKey(name: 'skip-src-address') List<String> skipSrcAddress,
    @Default([]) @JsonKey(name: 'skip-dst-address') List<String> skipDstAddress,
    @Default([]) @JsonKey(name: 'skip-domain') List<String> skipDomain,
    @Default([]) @JsonKey(name: 'port-whitelist') List<String> port,
    @Default(true) @JsonKey(name: 'force-dns-mapping') bool forceDnsMapping,
    @Default(true) @JsonKey(name: 'parse-pure-ip') bool parsePureIp,
    @Default({}) Map<String, SnifferConfig> sniff,
  }) = _Sniffer;

  factory Sniffer.fromJson(Map<String, Object?> json) =>
      _$SnifferFromJson(json);
}

List<String> _formJsonPorts(List? ports) {
  return ports?.map((item) => item.toString()).toList() ?? [];
}

@freezed
abstract class SnifferConfig with _$SnifferConfig {
  const factory SnifferConfig({
    @Default([]) @JsonKey(fromJson: _formJsonPorts) List<String> ports,
    @JsonKey(name: 'override-destination') bool? overrideDest,
  }) = _SnifferConfig;

  factory SnifferConfig.fromJson(Map<String, Object?> json) =>
      _$SnifferConfigFromJson(json);
}

@freezed
abstract class Tun with _$Tun {
  const factory Tun({
    @Default(false) bool enable,
    @Default(appName) String device,
    @JsonKey(name: 'auto-route') @Default(false) bool autoRoute,
    @Default(TunStack.mixed) TunStack stack,
    @JsonKey(name: 'dns-hijack') @Default(['any:53']) List<String> dnsHijack,
    @JsonKey(name: 'route-address') @Default([]) List<String> routeAddress,
  }) = _Tun;

  factory Tun.fromJson(Map<String, Object?> json) => _$TunFromJson(json);

  factory Tun.safeFormJson(Map<String, Object?>? json) {
    if (json == null) {
      return defaultTun;
    }
    return decodeOrRestoreDefault(
      'tun config',
      () => Tun.fromJson(json),
      () => defaultTun,
    );
  }
}

extension TunExt on Tun {
  List<String> resolveRouteAddress(RouteMode routeMode) =>
      routeMode == RouteMode.bypassPrivate
      ? defaultBypassPrivateRouteAddress
      : routeAddress;

  Tun getRealTun(RouteMode routeMode) {
    final mRouteAddress = resolveRouteAddress(routeMode);
    return switch (system.isDesktop) {
      true => copyWith(autoRoute: true, routeAddress: []),
      false => copyWith(
        autoRoute: mRouteAddress.isEmpty ? true : false,
        routeAddress: mRouteAddress,
      ),
    };
  }
}

@freezed
abstract class FallbackFilter with _$FallbackFilter {
  const factory FallbackFilter({
    // 默认关，理由见 defaultFallbackFilterGeoip（开着会架空 nameserver）。
    @Default(defaultFallbackFilterGeoip) bool geoip,
    // 仅在 geoip 为 true 时有意义。保留 'CN' 不动：迁移只负责关掉 geoip，
    // 不在用户看不出差别的地方动他的配置。
    @Default('CN') @JsonKey(name: 'geoip-code') String geoipCode,
    // 内核已弃用（`config/config.go:1591` 会打 warn 让改用 nameserver-policy）。
    @Default([]) List<String> geosite,
    @Default(['240.0.0.0/4']) List<String> ipcidr,
    // 默认空，理由见 defaultFallbackFilterDomains。
    @Default(defaultFallbackFilterDomains) List<String> domain,
  }) = _FallbackFilter;

  factory FallbackFilter.fromJson(Map<String, Object?> json) =>
      _$FallbackFilterFromJson(json);
}

@freezed
abstract class Dns with _$Dns {
  const factory Dns({
    @Default(true) bool enable,
    @Default('0.0.0.0:1053') String listen,
    @Default(false) @JsonKey(name: 'prefer-h3') bool preferH3,
    @Default(true) @JsonKey(name: 'use-hosts') bool useHosts,
    @Default(true) @JsonKey(name: 'use-system-hosts') bool useSystemHosts,
    @Default(false) @JsonKey(name: 'respect-rules') bool respectRules,
    @Default(false) bool ipv6,
    @Default(['223.5.5.5'])
    @JsonKey(name: 'default-nameserver')
    List<String> defaultNameserver,
    @Default(DnsMode.fakeIp)
    @JsonKey(name: 'enhanced-mode')
    DnsMode enhancedMode,
    @Default('198.18.0.1/16')
    @JsonKey(name: 'fake-ip-range')
    String fakeIpRange,
    @Default(['*.lan', 'localhost.ptlogin2.qq.com'])
    @JsonKey(name: 'fake-ip-filter')
    List<String> fakeIpFilter,
    @Default({
      'www.baidu.com': '114.114.114.114',
      '+.internal.crop.com': '10.0.0.1',
      'geosite:cn': 'https://doh.pub/dns-query',
    })
    @JsonKey(name: 'nameserver-policy')
    Map<String, String> nameserverPolicy,
    // 默认值由 defaultNameservers 决定（境外 DoH）。
    //
    // 这一条是**真正回答问题的那一个** —— 但这不是自动成立的，而是取决于下面
    // fallbackFilter 的配置。三路判定的顺序在 `dns/resolver.go` 的 `ipExchange`：
    //   ① 命中 `nameserver-policy` → 只用那一条（见上面的 `geosite:cn`，国内域名走国内）；
    //   ② 命中 `fallback-filter.domain` → **跳过本字段，只查 `fallback`**；
    //   ③ 否则查本字段，仅当返回的 IP 命中 `fallback-filter` 的 IP 过滤器时才改口用
    //      `fallback` 的结果（而且是**无条件**采用，本字段的成功结果会被丢弃）。
    // 所以本字段能不能当主力，取决于 ② 是否为空、③ 的过滤器是否会命中：
    // 现在 `domain` 为空、`geoip` 为 false，IP 侧只剩保留段 `240.0.0.0/4`，
    // 正常公网 IP 永不命中 ⇒ **本字段负责回答，`fallback` 仅在本字段失败时顶上**。
    // ⚠️ 谁要把 `geoip` 或 `domain` 改回上游的默认值，这个结论立刻失效。
    //
    // 上游原先让本字段指向国内 DoH，等于「流量出境、解析在境内」，境外域名的
    // 查询记录会落在国内厂商手里。
    @Default(defaultNameservers) List<String> nameserver,
    // 默认值由 defaultFallback 决定（境外 DoH）。定位是**兜底**而非「第二意见」：
    // 只有主上游失败、或返回的 IP 命中了 `fallback-filter` 的 IP 过滤器时才会被采用。
    // 详见上面 `nameserver` 与下面 `defaultFallbackFilterGeoip` 的说明。
    @Default(defaultFallback) List<String> fallback,
    @Default(['https://doh.pub/dns-query'])
    @JsonKey(name: 'proxy-server-nameserver')
    List<String> proxyServerNameserver,
    @Default(FallbackFilter())
    @JsonKey(name: 'fallback-filter')
    FallbackFilter fallbackFilter,
  }) = _Dns;

  factory Dns.fromJson(Map<String, Object?> json) => _$DnsFromJson(json);

  factory Dns.safeDnsFromJson(Map<String, Object?> json) {
    return decodeOrRestoreDefault(
      'dns config',
      () => Dns.fromJson(json),
      () => const Dns(),
    );
  }
}

@freezed
abstract class Rule with _$Rule {
  const factory Rule({
    @Default(-1) int id,
    @Default(RuleAction.DOMAIN) RuleAction ruleAction,
    String? content,
    String? ruleTarget,
    String? ruleProvider,
    String? subRule,
    @Default(false) bool noResolve,
    @Default(false) bool src,
    String? order,
  }) = _Rule;

  factory Rule.init() {
    return Rule(
      ruleAction: RuleAction.DOMAIN,
      ruleTarget: RuleTarget.DIRECT.name,
    );
  }

  // Mirrors mihomo's ParseRulePayload with needTarget set.
  factory Rule.parse(String value, {int? id}) {
    id ??= snowflake.id;
    final fields = value.split(',').map((item) => item.trim()).toList();
    final type = fields.first.toUpperCase();
    if (type.isEmpty) {
      return Rule(
        id: id,
        ruleAction: RuleAction.DOMAIN,
        ruleTarget: RuleTarget.DIRECT.name,
      );
    }
    final action = RuleAction.values.firstWhere(
      (item) => item.value == type,
      orElse: () => RuleAction.DOMAIN,
    );
    final rest = fields.sublist(1);
    String? payload;
    String? target;
    var params = const <String>[];
    if (action == RuleAction.MATCH) {
      target = rest.firstOrNull;
    } else if (action.hasCommaPayload) {
      target = rest.lastOrNull;
      payload = rest.length > 1
          ? rest.sublist(0, rest.length - 1).join(',')
          : null;
    } else {
      payload = rest.elementAtOrNull(0);
      target = rest.elementAtOrNull(1);
      params = rest.skip(2).toList();
    }
    payload = payload?.isNotEmpty == true ? payload : null;
    target = target?.isNotEmpty == true ? target : null;

    return Rule(
      id: id,
      ruleAction: action,
      content: action == RuleAction.RULE_SET ? null : payload,
      ruleProvider: action == RuleAction.RULE_SET ? payload : null,
      ruleTarget: action == RuleAction.SUB_RULE ? null : target,
      subRule: action == RuleAction.SUB_RULE ? target : null,
      src: params.contains('src'),
      noResolve: params.contains('no-resolve'),
    );
  }

  factory Rule.fromJson(Map<String, Object?> json) => _$RuleFromJson(json);
}

extension RuleExt on Rule {
  Rule autoOrder(Rule rule, String? a, String? b) {
    final newRule = rule.order?.isNotEmpty != true
        ? rule.copyWith(order: indexing.generateKeyBetween(a, b))
        : rule;
    return newRule;
  }

  String? get realContent {
    return switch (ruleAction) {
      RuleAction.MATCH => null,
      RuleAction.RULE_SET => ruleProvider,
      _ => content,
    };
  }

  String? get realTarget {
    return switch (ruleAction == RuleAction.SUB_RULE) {
      true => subRule,
      false => ruleTarget,
    };
  }

  String? targetErrorTip(String invalidSubRuleTip, String invalidPolicyTip) {
    return switch (ruleAction == RuleAction.SUB_RULE) {
      true => invalidSubRuleTip,
      false => invalidPolicyTip,
    };
  }

  String get rawValue {
    final content = realContent;
    final target = realTarget;
    return [
      ruleAction.value,
      if (content?.isNotEmpty == true) content!,
      if (target?.isNotEmpty == true) target!,
      if (ruleAction.hasParams) ...[
        if (src) 'src',
        if (noResolve) 'no-resolve',
      ],
    ].join(',');
  }
}

List<Rule> _genRules(List<dynamic>? rules) {
  if (rules == null) {
    return [];
  }
  return rules.map((item) => Rule.parse(item)).toList();
}

List<String> _genList(Map<String, dynamic> json) {
  return json.entries.map((entry) => entry.key).toList();
}

@freezed
abstract class ClashConfig with _$ClashConfig {
  const factory ClashConfig({
    @Default([]) @JsonKey(name: 'proxy-groups') List<ProxyGroup> proxyGroups,
    @JsonKey(fromJson: _genRules) @Default([]) List<Rule> rules,
    @Default([]) List<Proxy> proxies,
    @JsonKey(name: 'proxy-providers', fromJson: _genList)
    @Default([])
    List<String> proxyProviders,
    @JsonKey(name: 'rule-providers', fromJson: _genList)
    @Default([])
    List<String> ruleProviders,
    @JsonKey(name: 'sub-rules', fromJson: _genList)
    @Default([])
    List<String> subRules,
    @Default({}) Map<String, String> proxyTypeMap,
  }) = _ClashConfig;

  factory ClashConfig.fromJson(Map<String, Object?> json) =>
      _$ClashConfigFromJson(json);
}

extension GeoResourceUrlMapExt on Map<GeoResource, String> {
  Map<String, String> get raw =>
      map((key, value) => MapEntry(key.configKey, value));
}

Map<GeoResource, String> _geoXUrlFromJson(Map<String, Object?>? json) {
  if (json == null) {
    return defaultGeoXUrl;
  }
  return json.map(
    (key, value) => MapEntry(GeoResource.fromJson(key), value as String),
  );
}

Map<String, String> _geoXUrlToJson(Map<GeoResource, String> value) {
  return value.raw;
}

@freezed
abstract class PatchClashConfig with _$PatchClashConfig {
  const factory PatchClashConfig({
    @Default(defaultMixedPort) @JsonKey(name: 'mixed-port') int mixedPort,
    @Default(0) @JsonKey(name: 'socks-port') int socksPort,
    @Default(0) @JsonKey(name: 'port') int port,
    @Default(0) @JsonKey(name: 'redir-port') int redirPort,
    @Default(0) @JsonKey(name: 'tproxy-port') int tproxyPort,
    @Default(Mode.rule) Mode mode,
    @Default(false) @JsonKey(name: 'allow-lan') bool allowLan,
    @Default(LogLevel.error) @JsonKey(name: 'log-level') LogLevel logLevel,
    @Default(false) bool ipv6,
    @Default(FindProcessMode.always)
    @JsonKey(
      name: 'find-process-mode',
      unknownEnumValue: FindProcessMode.always,
    )
    FindProcessMode findProcessMode,
    @Default(InterfaceNameMode.clear)
    @JsonKey(
      name: 'interface-name-mode',
      unknownEnumValue: InterfaceNameMode.clear,
    )
    InterfaceNameMode interfaceNameMode,
    @Default('') @JsonKey(name: 'interface-name') String interfaceName,
    @Default(defaultKeepAliveInterval)
    @JsonKey(name: 'keep-alive-interval')
    int keepAliveInterval,
    @Default(true) @JsonKey(name: 'unified-delay') bool unifiedDelay,
    @Default(true) @JsonKey(name: 'tcp-concurrent') bool tcpConcurrent,
    @Default(defaultTun) @JsonKey(fromJson: Tun.safeFormJson) Tun tun,
    @Default(defaultDns) @JsonKey(fromJson: Dns.safeDnsFromJson) Dns dns,
    @Default(defaultGeoXUrl)
    @JsonKey(
      name: 'geox-url',
      fromJson: _geoXUrlFromJson,
      toJson: _geoXUrlToJson,
    )
    Map<GeoResource, String> geoXUrl,
    @Default(GeodataLoader.memconservative)
    @JsonKey(name: 'geodata-loader')
    GeodataLoader geodataLoader,
    @JsonKey(name: 'global-ua') String? globalUa,
    @Default(ExternalControllerStatus.close)
    @JsonKey(name: 'external-controller')
    ExternalControllerStatus externalController,
    @Default({}) Map<String, String> hosts,
    @Default(false) @JsonKey(name: 'geo-auto-update') bool geoAutoUpdate,
    @Default(24) @JsonKey(name: 'geo-update-interval') int geoUpdateInterval,
  }) = _PatchClashConfig;

  factory PatchClashConfig.fromJson(Map<String, Object?> json) =>
      _$PatchClashConfigFromJson(json);

  factory PatchClashConfig.safeFormJson(Map<String, Object?>? json) {
    if (json == null) {
      return defaultClashConfig;
    }
    return decodeOrRestoreDefault(
      'clash config',
      () => PatchClashConfig.fromJson(json),
      () => defaultClashConfig,
    );
  }
}
