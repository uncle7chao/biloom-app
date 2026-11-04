import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'models.dart';

part 'generated/config.freezed.dart';
part 'generated/config.g.dart';

const defaultBypassDomain = [
  '*zhihu.com',
  '*zhimg.com',
  '*jd.com',
  '100ime-iat-api.xfyun.cn',
  '*360buyimg.com',
  'localhost',
  '*.local',
  '127.*',
  '10.*',
  '172.16.*',
  '172.17.*',
  '172.18.*',
  '172.19.*',
  '172.2*',
  '172.30.*',
  '172.31.*',
  '192.168.*',
];

const defaultUserAgents = ['clash-verge/v2.4.2', 'ClashforWindows/0.19.23'];

const defaultFilters = [
  Filter(
    label: 'Hong Kong',
    regex: r'(?i)🇭🇰|港|(?<![a-z])hk(?![a-z])|hong\s*kong',
  ),
  Filter(
    label: 'Taiwan',
    regex: r'(?i)🇹🇼|台湾|台灣|台北|新北|彰化|(?<![a-z])tw(?![a-z])|taiwan',
  ),
  Filter(
    label: 'Japan',
    regex: r'(?i)🇯🇵|日本|东京|東京|大阪|埼玉|(?<![a-z])jp(?![a-z])|japan|tokyo|osaka',
  ),
  Filter(
    label: 'Singapore',
    regex: r'(?i)🇸🇬|新加坡|狮城|獅城|(?<![a-z])sg(?![a-z])|singapore',
  ),
  Filter(
    label: 'United States',
    regex:
        r'(?i)🇺🇸|美国|美國|美西|美东|美東|洛杉矶|圣何塞|西雅图|硅谷|纽约'
        r'|(?<![a-z])usa?(?![a-z])|united\s*states',
  ),
  Filter(
    label: 'South Korea',
    regex: r'(?i)🇰🇷|韩国|韓國|首尔|首爾|(?<![a-z])kr(?![a-z])|korea|seoul',
  ),
  Filter(
    label: 'United Kingdom',
    regex:
        r'(?i)🇬🇧|英国|英國|伦敦|倫敦|(?<![a-z])(uk|gb)(?![a-z])'
        r'|united\s*kingdom|britain|london',
  ),
  Filter(
    label: 'Remaining Traffic',
    regex: r'(?i)剩余|剩餘|已用|流量\s*[:：]|traffic|remaining',
  ),
  Filter(label: 'Expiry Date', regex: r'(?i)到期|过期|過期|有效期|expir'),
  Filter(label: 'Traffic Reset', regex: r'(?i)重置|reset'),
  Filter(
    label: 'Website & Notices',
    regex:
        r'(?i)官网|官網|网址|網址|域名|公告|套餐|客服|群组|群組|频道|頻道'
        r'|website|telegram|(?<![a-z])tg(?![a-z])',
  ),
];

const defaultAppSettingProps = AppSettingProps();
const defaultVpnProps = VpnProps();
const defaultAuthenticationProps = AuthenticationProps();
const defaultNetworkProps = NetworkProps();
const defaultProxiesStyleProps = ProxiesStyleProps();
const defaultWindowProps = WindowProps();
const defaultAccessControlProps = AccessControlProps();
const defaultThemeProps = ThemeProps(primaryColor: defaultPrimaryColor);

HotKeyAction _defaultHotKeyAction(HotAction action, PhysicalKeyboardKey key) {
  return HotKeyAction(
    action: action,
    key: key.usbHidUsage,
    modifiers: const {KeyboardModifier.control, KeyboardModifier.alt},
  );
}

// Windows reports AltGr as Ctrl+Alt, and every letter is an AltGr character
// on some layout (@ on German Q, ś on Polish S), so a default there would fire
// while the user types.
final List<HotKeyAction> defaultHotKeyActions = system.isWindows
    ? const []
    : [
        _defaultHotKeyAction(HotAction.view, PhysicalKeyboardKey.keyV),
        _defaultHotKeyAction(HotAction.start, PhysicalKeyboardKey.keyS),
        _defaultHotKeyAction(HotAction.mode, PhysicalKeyboardKey.keyM),
        _defaultHotKeyAction(HotAction.proxy, PhysicalKeyboardKey.keyP),
        _defaultHotKeyAction(HotAction.delayTest, PhysicalKeyboardKey.keyD),
      ];

const List<DashboardWidget> defaultDashboardWidgets = [
  DashboardWidget.currentOutbound,
  DashboardWidget.networkSpeed,
  DashboardWidget.outboundMode,
  DashboardWidget.vpnButton,
  DashboardWidget.networkTakeover,
  DashboardWidget.intranetIp,
  DashboardWidget.serviceStatus,
  DashboardWidget.profiles,
  DashboardWidget.proxyGroups,
  DashboardWidget.connectionStats,
];

/// A phone starts without the VPN switch and the diagnostic cards, which stay
/// addable. The field default keeps the shared list because it must be const.
final List<DashboardWidget> platformDefaultDashboardWidgets = system.isAndroid
    ? const [
        DashboardWidget.currentOutbound,
        DashboardWidget.networkSpeed,
        DashboardWidget.outboundMode,
        DashboardWidget.profiles,
        DashboardWidget.proxyGroups,
      ]
    : defaultDashboardWidgets;

const _legacyDefaultDashboardWidgets = {
  'networkSpeed',
  'systemProxyButton',
  'tunButton',
  'outboundMode',
  'networkDetection',
  'trafficUsage',
  'intranetIp',
};

/// The run time has no replacement: it moved onto the current outbound card,
/// as did the outbound IP, whose card became the intranet one.
const _legacyDashboardWidgets = {
  'networkDetection': DashboardWidget.intranetIp,
  'outboundModeV2': DashboardWidget.outboundMode,
  'systemProxyButton': DashboardWidget.networkTakeover,
  'tunButton': DashboardWidget.networkTakeover,
  'connections': DashboardWidget.connectionStats,
  'requests': DashboardWidget.connectionStats,
  'dnsQueries': DashboardWidget.connectionStats,
  'trafficUsage': DashboardWidget.networkSpeed,
};

const _retiredDashboardWidgets = {
  'runTime',
  'overrideDnsButton',
  'overrideNtpButton',
};

/// The current outbound card cannot be removed: a list without it predates it.
List<DashboardWidget> dashboardWidgetsFromJson(
  List<dynamic>? dashboardWidgets,
) {
  if (dashboardWidgets == null) {
    return platformDefaultDashboardWidgets;
  }
  final byName = DashboardWidget.values.asNameMap();
  if (dashboardWidgets.contains(DashboardWidget.currentOutbound.name)) {
    return dashboardWidgets
        .map((e) => _legacyDashboardWidgets[e] ?? byName[e])
        .nonNulls
        .toSet()
        .toList();
  }
  final names = {
    for (final name in dashboardWidgets)
      name == 'outboundModeV2' ? DashboardWidget.outboundMode.name : name,
  };
  if (names.length == _legacyDefaultDashboardWidgets.length &&
      names.containsAll(_legacyDefaultDashboardWidgets)) {
    return platformDefaultDashboardWidgets;
  }
  final kept = dashboardWidgets
      .map((e) => _legacyDashboardWidgets[e] ?? byName[e])
      .nonNulls;
  if (kept.isEmpty &&
      !dashboardWidgets.every(_retiredDashboardWidgets.contains)) {
    return platformDefaultDashboardWidgets;
  }
  return {DashboardWidget.currentOutbound, ...kept}.toList();
}

Object? _readSidebarExpanded(Map<dynamic, dynamic> json, String key) {
  return json.containsKey(key) ? json[key] : json['showLabel'];
}

Object? _readTabAnimation(Map<dynamic, dynamic> json, String key) {
  if (json.containsKey(key)) {
    return json[key];
  }
  return switch (json['isAnimateToPage']) {
    true => TabAnimation.slide.name,
    false => TabAnimation.fade.name,
    _ => null,
  };
}

Object? _readUserAgents(Map<dynamic, dynamic> json, String key) {
  if (json.containsKey(key)) {
    return json[key];
  }
  final legacy = json['customUserAgent'];
  if (legacy is! String) {
    return null;
  }
  final custom = legacy.trim();
  if (custom.isEmpty || defaultUserAgents.contains(custom)) {
    return null;
  }
  return [...defaultUserAgents, custom];
}

@freezed
abstract class Filter with _$Filter {
  const factory Filter({required String label, required String regex}) =
      _Filter;

  factory Filter.fromJson(Map<String, Object?> json) => _$FilterFromJson(json);
}

@freezed
abstract class AppSettingProps with _$AppSettingProps {
  const factory AppSettingProps({
    String? locale,
    @Default(defaultDashboardWidgets)
    @JsonKey(fromJson: dashboardWidgetsFromJson)
    List<DashboardWidget> dashboardWidgets,
    @Default(false) bool onlyStatisticsProxy,
    @Default(true) bool showNotificationStopAction,
    @Default(false) bool autoLaunch,
    @Default(false) bool silentLaunch,
    @Default(false) bool autoRun,
    @Default(false) bool openLogs,
    @Default(true) bool closeConnections,
    @Default(defaultDelayTestTimeout) int delayTestTimeout,
    @Default(TabAnimation.fade)
    @JsonKey(readValue: _readTabAnimation)
    TabAnimation tabAnimation,
    @Default(true) bool floatingNavigationBar,
    @Default(true) bool autoCheckUpdate,
    @Default(false) bool disclaimerAccepted,
    // BiLoom: no longer read anywhere - Firebase was removed from the fork, so
    // the data-collection notice keyed off this flag was dropped. Kept so
    // existing config.json files stay loadable.
    @Default(false) bool crashlyticsTip,
    // BiLoom: this flag no longer refers to Firebase. It only gates the extra
    // ApplicationExitInfo probe inside BootGuard.
    @Default(false) bool crashlytics,
    @Default(true)
    @JsonKey(readValue: _readSidebarExpanded)
    bool sidebarExpanded,
    @Default(0) int acceptedDisclaimerVersion,
    @Default(true) bool minimizeOnExit,
    @Default(false) bool hidden,
    @Default(false) bool developerMode,
    @Default(RestoreStrategy.compatible) RestoreStrategy restoreStrategy,
    @Default(true) bool showTrayTitle,
    @Default(true) bool monochromeTrayIcon,
    @Default(true) bool checkCertificate,
    @Default(defaultUserAgents)
    @JsonKey(readValue: _readUserAgents)
    List<String> userAgents,
    @Default(defaultFilters) List<Filter> filters,
    @Default(false) bool hideIp,
    @Default(false) bool editorLineWrap,
    @Default(EditorFontSize.standard) EditorFontSize editorFontSize,
    @Default([]) List<String> serviceOrder,
    @Default([]) List<String> disabledServices,
    @Default({}) Map<String, Map<String, double>> tableColumnWidths,
  }) = _AppSettingProps;

  factory AppSettingProps.fromJson(Map<String, Object?> json) =>
      _$AppSettingPropsFromJson(json);

  factory AppSettingProps.safeFromJson(Map<String, Object?>? json) {
    if (json == null) {
      return defaultAppSettingProps;
    }
    return decodeSalvaging('app settings', json, AppSettingProps.fromJson);
  }
}

@freezed
abstract class AccessControlProps with _$AccessControlProps {
  const factory AccessControlProps({
    @Default(false) bool enable,
    @Default(AccessControlMode.rejectSelected) AccessControlMode mode,
    @Default([]) List<String> acceptList,
    @Default([]) List<String> rejectList,
    @Default(AccessSortType.none) AccessSortType sort,
    @Default(true) bool isFilterSystemApp,
    @Default(true) bool isFilterNonInternetApp,
  }) = _AccessControlProps;

  factory AccessControlProps.fromJson(Map<String, Object?> json) =>
      _$AccessControlPropsFromJson(json);
}

extension AccessControlPropsExt on AccessControlProps {
  bool get hasPackages => acceptList.isNotEmpty || rejectList.isNotEmpty;

  List<String> get currentList => switch (mode) {
    AccessControlMode.acceptSelected => acceptList,
    AccessControlMode.rejectSelected => rejectList,
  };

  AccessControlProps copyWithNewList(List<String> value) => switch (mode) {
    AccessControlMode.acceptSelected => copyWith(acceptList: value),
    AccessControlMode.rejectSelected => copyWith(rejectList: value),
  };
}

@freezed
abstract class WindowProps with _$WindowProps {
  const factory WindowProps({
    @Default(0) double width,
    @Default(0) double height,
    double? top,
    double? left,
    double? scale,
  }) = _WindowProps;

  factory WindowProps.fromJson(Map<String, Object?>? json) =>
      json == null ? const WindowProps() : _$WindowPropsFromJson(json);
}

/// Four dashboard columns at full density beside the expanded sidebar, with
/// room for the Windows and Linux title bar.
const defaultWindowSize = Size(1280, 880);

extension WindowPropsExt on WindowProps {
  Size? get savedSize {
    final size = Size(width, height);
    return size.isEmpty ? null : size;
  }

  Size get size => savedSize ?? defaultWindowSize;
}

@freezed
abstract class VpnProps with _$VpnProps {
  const factory VpnProps({
    @Default(true) bool enable,
    @Default(true) bool systemProxy,
    @Default(false) bool ipv6,
    @Default(true) bool allowBypass,
    @Default(false) bool dnsHijacking,
    @Default(defaultAccessControlProps) AccessControlProps accessControlProps,
  }) = _VpnProps;

  factory VpnProps.fromJson(Map<String, Object?>? json) =>
      json == null ? defaultVpnProps : _$VpnPropsFromJson(json);
}

@freezed
abstract class AuthenticationProps with _$AuthenticationProps {
  const factory AuthenticationProps({
    @Default(false) bool enable,
    @Default('') String username,
    @Default('') String password,
  }) = _AuthenticationProps;

  factory AuthenticationProps.fromJson(Map<String, Object?>? json) =>
      json == null
      ? defaultAuthenticationProps
      : _$AuthenticationPropsFromJson(json);
}

extension AuthenticationPropsExt on AuthenticationProps {
  List<String> get credentials =>
      enable && username.isNotEmpty ? ['$username:$password'] : [];
}

@freezed
abstract class NetworkProps with _$NetworkProps {
  const factory NetworkProps({
    // 默认关。这个开关现在与「连接」是同一件事（拨开就自动连接），
    // 所以它必须诚实反映「此刻有没有在用代理」。默认开着会让新用户看到一个
    // 亮着的开关却什么都没发生，连不上还以为是软件坏了 —— 那正是要根治的
    // 「开关骗人」。默认关 + 拨开即连接，用户的心智模型只有一步。
    @Default(false) bool systemProxy,
    @Default(defaultBypassDomain) List<String> bypassDomain,
    @Default(true) bool bypassPrivateRoute,
    @Default(true) bool autoSetSystemDns,
    @Default(false) bool appendSystemDns,
    @Default(defaultAuthenticationProps) AuthenticationProps authentication,
  }) = _NetworkProps;

  factory NetworkProps.fromJson(Map<String, Object?>? json) =>
      json == null ? const NetworkProps() : _$NetworkPropsFromJson(json);
}

/// Reads the styles named `standard`, `icon` and `none` before they became
/// [ProxiesIconStyle.filled], [ProxiesIconStyle.plain] and
/// [ProxiesIconStyle.hidden].
ProxiesIconStyle proxiesIconStyleSafeFromJson(Object? iconStyle) {
  return switch (iconStyle) {
    'filled' || 'standard' => ProxiesIconStyle.filled,
    'plain' || 'icon' => ProxiesIconStyle.plain,
    'hidden' || 'none' => ProxiesIconStyle.hidden,
    _ => ProxiesIconStyle.filled,
  };
}

ProxyCardType proxyCardTypeSafeFromJson(Object? cardType) {
  return switch (cardType) {
    'loose' || 'expand' => ProxyCardType.loose,
    'standard' || 'shrink' => ProxyCardType.standard,
    'compact' || 'min' => ProxyCardType.compact,
    _ => ProxyCardType.standard,
  };
}

@freezed
abstract class ProxiesStyleProps with _$ProxiesStyleProps {
  const factory ProxiesStyleProps({
    @Default(ProxiesType.tab) ProxiesType type,
    // 出厂默认「按延迟」：节点列表一测速就自动把快节点顶上去（2026-10-01 用户
    // 要求）。存量配置靠 Migration v1→v2 一次性迁移，见 common/migration.dart。
    @Default(ProxiesSortType.delay) ProxiesSortType sortType,
    @Default(ProxiesLayout.standard) ProxiesLayout layout,
    @Default(ProxiesIconStyle.filled)
    @JsonKey(fromJson: proxiesIconStyleSafeFromJson)
    ProxiesIconStyle iconStyle,
    @Default(ProxyCardType.standard)
    @JsonKey(fromJson: proxyCardTypeSafeFromJson)
    ProxyCardType cardType,
    @Default(false) bool hideTimeoutProxies,
  }) = _ProxiesStyleProps;

  factory ProxiesStyleProps.fromJson(Map<String, Object?>? json) => json == null
      ? defaultProxiesStyleProps
      : _$ProxiesStylePropsFromJson(json);
}

@freezed
abstract class TextScale with _$TextScale {
  const factory TextScale({
    @Default(false) bool enable,
    @Default(1.0) double scale,
  }) = _TextScale;

  factory TextScale.fromJson(Map<String, Object?> json) =>
      _$TextScaleFromJson(json);
}

// Older configs name one of Material's nine scheme variants instead.
Object? _readColorStyle(Map<dynamic, dynamic> json, String key) {
  if (json.containsKey(key)) {
    return json[key];
  }
  return switch (json['schemeVariant']) {
    'monochrome' => ColorStyle.monochrome.name,
    'tonalSpot' || 'neutral' => ColorStyle.soft.name,
    _ => null,
  };
}

// Older configs say whether glass is on.
Object? _readLiquidGlass(Map<dynamic, dynamic> json, String key) {
  return switch (json[key]) {
    true => LiquidGlassMode.standard.name,
    false => LiquidGlassMode.none.name,
    final value => value,
  };
}

@freezed
abstract class ThemeProps with _$ThemeProps {
  const factory ThemeProps({
    int? primaryColor,
    @Default(defaultPrimaryColors) List<int> primaryColors,
    @Default(ThemeMode.system) ThemeMode themeMode,
    @Default(ColorStyle.vivid)
    @JsonKey(readValue: _readColorStyle)
    ColorStyle colorStyle,
    @Default(false) bool pureBlack,
    @Default(false) bool sidebarBlur,
    @Default(LiquidGlassMode.none)
    @JsonKey(readValue: _readLiquidGlass)
    LiquidGlassMode liquidGlass,
    @Default(TextScale()) TextScale textScale,
    // `fontFamily` held the names of a removed enum, which old configs may
    // still carry.
    @JsonKey(name: 'systemFontFamily') String? fontFamily,
  }) = _ThemeProps;

  factory ThemeProps.fromJson(Map<String, Object?> json) =>
      _$ThemePropsFromJson(json);

  factory ThemeProps.safeFromJson(Map<String, Object?>? json) {
    if (json == null) {
      return defaultThemeProps;
    }
    final props = decodeSalvaging('theme settings', json, ThemeProps.fromJson);
    // 品牌色迁移：默认种子色由 iOS 灰粉换成品牌青绿后，存量配置里
    // 仍等于旧默认值的 primaryColor 一并迁移（无法与「主动选了旧默认色」
    // 区分，按「从未动过主题色」处理）。
    if (props.primaryColor == legacyDefaultPrimaryColor) {
      return props.copyWith(primaryColor: defaultPrimaryColor);
    }
    return props;
  }
}

@freezed
abstract class Config with _$Config {
  const factory Config({
    int? currentProfileId,
    @Default([]) List<HotKeyAction> hotKeyActions,
    @JsonKey(fromJson: AppSettingProps.safeFromJson)
    @Default(defaultAppSettingProps)
    AppSettingProps appSettingProps,
    DAVProps? davProps,
    @Default(defaultNetworkProps) NetworkProps networkProps,
    @Default(defaultVpnProps) VpnProps vpnProps,
    @JsonKey(fromJson: ThemeProps.safeFromJson) required ThemeProps themeProps,
    @Default(defaultProxiesStyleProps) ProxiesStyleProps proxiesStyleProps,
    // A new key opens every window once at defaultWindowSize.
    @Default(defaultWindowProps)
    @JsonKey(name: 'windowGeometry')
    WindowProps windowProps,
    @Default(defaultClashConfig) PatchClashConfig patchClashConfig,
    @Default([]) List<String> excludeSSIDs,
  }) = _Config;

  factory Config.fromJson(Map<String, Object?> json) =>
      decodeSalvaging('config', json, Config.strictFromJson);

  factory Config.strictFromJson(Map<String, Object?> json) =>
      _withLegacyOverrideDns(
        _$ConfigFromJson(_withLegacyTestUrl(_withLegacyRouteMode(json))),
        json,
      );

  factory Config.realFromJson(Map<String, Object?>? json) {
    if (json == null) {
      return Config(
        themeProps: defaultThemeProps,
        hotKeyActions: defaultHotKeyActions,
        appSettingProps: AppSettingProps(
          dashboardWidgets: platformDefaultDashboardWidgets,
        ),
      );
    }
    return Config.fromJson(json);
  }
}

extension ConfigMigration on Config {
  /// 把「还是出厂默认值」的 DNS 上游升级成新默认值。
  ///
  /// 为什么需要这一步：整份 Config（含 DNS）是持久化在 SharedPreferences 里的，
  /// 改 `Dns` 的 `@Default` 只影响全新安装 —— 存量用户读回来的仍然是自己那份旧配置。
  /// 所以上一个版本默认用国内 DoH 的人，升级后依然在把境外域名的查询交给国内厂商。
  ///
  /// 为什么只做精确比对：判断「用户是否动过这个设置」没有别的可靠办法，
  /// 而误判的代价不对称 —— 把用户精心填过的上游覆盖掉是灾难，漏迁移一次只是没变好。
  /// 所以宁可漏，不可错：只有与旧默认值**逐项相等**时才改写。
  ///
  /// 这是幂等的：改过之后再读回来就不等于旧默认值了。
  Config migrateLegacyDnsNameservers() {
    final dns = patchClashConfig.dns;
    if (!_sameList(dns.nameserver, legacyDefaultNameservers)) {
      return this;
    }
    return copyWith(
      patchClashConfig: patchClashConfig.copyWith.dns(
        nameserver: List<String>.from(defaultNameservers),
      ),
    );
  }

  /// 把「还是出厂默认值」的 DNS 备用上游、`fallback-filter.domain` 与
  /// `fallback-filter.geoip` 一并升级。
  ///
  /// 与 `migrateLegacyDnsNameservers` 同理：改 `@Default` 只影响全新安装，
  /// 存量用户读回来的仍是自己那份旧配置。
  ///
  /// 这里要修的是同一个问题的三面 —— 上游那套默认值是**围绕「主上游=国内 DoH」**
  /// 设计的，主上游换成境外 DoH 之后，那三处配置从「有用」变成了「架空主上游」：
  ///   · `fallback-filter.domain`：命中它的域名**跳过主上游、只查备用上游**
  ///     （内核 `dns/resolver.go:279-310` 的 `shouldOnlyQueryFallback`）。
  ///     上游把 google/facebook/youtube 放进列表，配上「主=国内、备=境外」是对的；
  ///     主上游已境外出 DoH 后，它反让这三个域族绕开新默认值、继续依赖 DoT:853。
  ///   · `fallback-filter.geoip: true` + `geoip-code: CN`：主上游解析出非 CN 的 IP 时，
  ///     内核**丢弃主上游的成功结果、改用备用上游的结果**（`ipExchange` 末段无条件返回），
  ///     等于让 `nameserver` 形同虚设。这条启发式只在主上游会被投毒（国内 DoH）时成立。
  ///   · `fallback` 本身：从 DoT:853 换成 DoH:443（853 特征明显，更易被干扰）。
  ///
  /// 三个字段**各自独立判定、独立改写**：用户可能只动过其中一个（例如自己加过
  /// 备用上游），那就只升级另两个没被动过的，不因为一个动过就把其他也放过。
  /// 同样遵循「宁可漏，不可错」——只在与旧默认值精确相等时才改写。
  ///
  /// `geoip` 的判据额外要求 `geoip-code` **也**还是出厂值：只看 `geoip` 分不清
  /// 「原样没动过」和「用户特意开着」，而同时看到 code 也是 `CN`，才说明这一组确实是
  /// 上游原样。用户换过国家的（例如 `JP`）一律不碰 —— 那是他自己配的，不是我们的默认值。
  Config migrateLegacyDnsFallback() {
    final dns = patchClashConfig.dns;
    final filter = dns.fallbackFilter;
    final shouldUpgradeFallback = _sameList(dns.fallback, legacyDefaultFallback);
    final shouldUpgradeDomains = _sameList(
      filter.domain,
      legacyFallbackFilterDomains,
    );
    final shouldUpgradeGeoip =
        filter.geoip == legacyFallbackFilterGeoip &&
        filter.geoipCode == legacyFallbackFilterGeoipCode;
    if (!shouldUpgradeFallback &&
        !shouldUpgradeDomains &&
        !shouldUpgradeGeoip) {
      return this;
    }
    return copyWith(
      patchClashConfig: patchClashConfig.copyWith.dns(
        fallback: shouldUpgradeFallback
            ? List<String>.from(defaultFallback)
            : dns.fallback,
        fallbackFilter: (shouldUpgradeDomains || shouldUpgradeGeoip)
            ? filter.copyWith(
                domain: shouldUpgradeDomains
                    ? List<String>.from(defaultFallbackFilterDomains)
                    : filter.domain,
                geoip: shouldUpgradeGeoip
                    ? defaultFallbackFilterGeoip
                    : filter.geoip,
              )
            : filter,
      ),
    );
  }
}

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

const _legacyOverrideDnsKey = 'overrideDns';

/// An off `overrideDns` left a profile's own DNS section alone.
Config _withLegacyOverrideDns(Config config, Map<String, Object?> json) {
  if (!json.containsKey(_legacyOverrideDnsKey)) {
    return config;
  }
  final keys = json[_legacyOverrideDnsKey] == true
      ? config.patchClashConfig.dnsOverrideKeys.intersection(
          DnsOverrideKey.normalProfileKeys,
        )
      : <DnsOverrideKey>{};
  return config.copyWith.patchClashConfig(dnsOverrideKeys: keys);
}

/// The test URL moved from the app settings into the general overrides.
Map<String, Object?> _withLegacyTestUrl(Map<String, Object?> json) {
  final app = json['appSettingProps'];
  final testUrl = app is Map ? app['testUrl'] : null;
  final clash = json['patchClashConfig'] ?? const <String, Object?>{};
  if (testUrl is! String ||
      testUrl.isEmpty ||
      clash is! Map ||
      clash.containsKey(GeneralOverrideKey.testUrl.path)) {
    return json;
  }
  return {
    ...json,
    'patchClashConfig': {
      ...Map<String, Object?>.from(clash),
      GeneralOverrideKey.testUrl.path: testUrl,
    },
  };
}

Map<String, Object?> _withLegacyRouteMode(Map<String, Object?> json) {
  final network = json['networkProps'];
  if (network is! Map ||
      !network.containsKey('routeMode') ||
      network.containsKey('bypassPrivateRoute')) {
    return json;
  }
  final bypassPrivate = network['routeMode'] == 'bypassPrivate';
  final clash = json['patchClashConfig'];
  final tun = clash is Map ? clash['tun'] : null;
  return {
    ...json,
    'networkProps': {
      ...Map<String, Object?>.from(network),
      'bypassPrivateRoute': bypassPrivate,
    },
    if (bypassPrivate && clash is Map && tun is Map)
      'patchClashConfig': {
        ...Map<String, Object?>.from(clash),
        'tun': {...Map<String, Object?>.from(tun), 'route-address': <String>[]},
      },
  };
}
