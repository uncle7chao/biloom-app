import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
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

const defaultAppSettingProps = AppSettingProps();
const defaultVpnProps = VpnProps();
const defaultAuthenticationProps = AuthenticationProps();
const defaultNetworkProps = NetworkProps();
const defaultProxiesStyleProps = ProxiesStyleProps();
const defaultWindowProps = WindowProps();
const defaultAccessControlProps = AccessControlProps();
const defaultThemeProps = ThemeProps(primaryColor: defaultPrimaryColor);

const List<DashboardWidget> defaultDashboardWidgets = [
  DashboardWidget.networkSpeed,
  DashboardWidget.systemProxyButton,
  DashboardWidget.tunButton,
  DashboardWidget.outboundMode,
  DashboardWidget.networkDetection,
  DashboardWidget.trafficUsage,
  DashboardWidget.intranetIp,
];

List<DashboardWidget> dashboardWidgetsSafeFormJson(
  List<dynamic>? dashboardWidgets,
) {
  return decodeOrRestoreDefault(
    'dashboard widgets',
    () =>
        dashboardWidgets
            ?.map((e) => $enumDecode(_$DashboardWidgetEnumMap, e))
            .toList() ??
        defaultDashboardWidgets,
    () => defaultDashboardWidgets,
  );
}

@freezed
abstract class AppSettingProps with _$AppSettingProps {
  const factory AppSettingProps({
    String? locale,
    @Default(defaultDashboardWidgets)
    @JsonKey(fromJson: dashboardWidgetsSafeFormJson)
    List<DashboardWidget> dashboardWidgets,
    @Default(false) bool onlyStatisticsProxy,
    @Default(true) bool showNotificationStopAction,
    @Default(false) bool autoLaunch,
    @Default(false) bool silentLaunch,
    @Default(false) bool autoRun,
    @Default(false) bool openLogs,
    @Default(true) bool closeConnections,
    @Default(defaultTestUrl) String testUrl,
    @Default(true) bool isAnimateToPage,
    @Default(true) bool autoCheckUpdate,
    @Default(false) bool showLabel,
    @Default(false) bool disclaimerAccepted,
    // BiLoom: no longer read anywhere - Firebase was removed from the fork, so
    // the data-collection notice keyed off this flag was dropped. Kept so
    // existing config.json files stay loadable.
    @Default(false) bool crashlyticsTip,
    // BiLoom: this flag no longer refers to Firebase. It only gates the extra
    // ApplicationExitInfo probe inside BootGuard.
    @Default(false) bool crashlytics,
    @Default(true) bool minimizeOnExit,
    @Default(false) bool hidden,
    @Default(false) bool developerMode,
    @Default(RestoreStrategy.compatible) RestoreStrategy restoreStrategy,
    @Default(true) bool showTrayTitle,
    @Default(true) bool checkCertificate,
    @Default('') String customUserAgent,
  }) = _AppSettingProps;

  factory AppSettingProps.fromJson(Map<String, Object?> json) =>
      _$AppSettingPropsFromJson(json);

  factory AppSettingProps.safeFromJson(Map<String, Object?>? json) {
    if (json == null) {
      return defaultAppSettingProps;
    }
    return decodeOrRestoreDefault(
      'app settings',
      () => AppSettingProps.fromJson(json),
      () => defaultAppSettingProps,
    );
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
  }) = _WindowProps;

  factory WindowProps.fromJson(Map<String, Object?>? json) =>
      json == null ? const WindowProps() : _$WindowPropsFromJson(json);
}

extension WindowPropsExt on WindowProps {
  Size get _size => Size(width, height);

  Size get size => _size.isEmpty ? const Size(680, 580) : _size;
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
    @Default(RouteMode.config) RouteMode routeMode,
    @Default(true) bool autoSetSystemDns,
    @Default(false) bool appendSystemDns,
    @Default(defaultAuthenticationProps) AuthenticationProps authentication,
  }) = _NetworkProps;

  factory NetworkProps.fromJson(Map<String, Object?>? json) =>
      json == null ? const NetworkProps() : _$NetworkPropsFromJson(json);
}

@freezed
abstract class ProxiesStyleProps with _$ProxiesStyleProps {
  const factory ProxiesStyleProps({
    @Default(ProxiesType.tab) ProxiesType type,
    @Default(ProxiesSortType.none) ProxiesSortType sortType,
    @Default(ProxiesLayout.standard) ProxiesLayout layout,
    @Default(ProxiesIconStyle.standard) ProxiesIconStyle iconStyle,
    @Default(ProxyCardType.expand) ProxyCardType cardType,
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

@freezed
abstract class ThemeProps with _$ThemeProps {
  const factory ThemeProps({
    int? primaryColor,
    @Default(defaultPrimaryColors) List<int> primaryColors,
    @Default(ThemeMode.dark) ThemeMode themeMode,
    @Default(DynamicSchemeVariant.content) DynamicSchemeVariant schemeVariant,
    @Default(false) bool pureBlack,
    @Default(TextScale()) TextScale textScale,
  }) = _ThemeProps;

  factory ThemeProps.fromJson(Map<String, Object?> json) =>
      _$ThemePropsFromJson(json);

  factory ThemeProps.safeFromJson(Map<String, Object?>? json) {
    if (json == null) {
      return defaultThemeProps;
    }
    return decodeOrRestoreDefault(
      'theme settings',
      () => ThemeProps.fromJson(json),
      () => defaultThemeProps,
    );
  }
}

@freezed
abstract class Config with _$Config {
  const factory Config({
    int? currentProfileId,
    @Default(false) bool overrideDns,
    @Default([]) List<HotKeyAction> hotKeyActions,
    @JsonKey(fromJson: AppSettingProps.safeFromJson)
    @Default(defaultAppSettingProps)
    AppSettingProps appSettingProps,
    DAVProps? davProps,
    @Default(defaultNetworkProps) NetworkProps networkProps,
    @Default(defaultVpnProps) VpnProps vpnProps,
    @JsonKey(fromJson: ThemeProps.safeFromJson) required ThemeProps themeProps,
    @Default(defaultProxiesStyleProps) ProxiesStyleProps proxiesStyleProps,
    @Default(defaultWindowProps) WindowProps windowProps,
    @Default(defaultClashConfig) PatchClashConfig patchClashConfig,
    @Default([]) List<String> excludeSSIDs,
  }) = _Config;

  factory Config.fromJson(Map<String, Object?> json) => _$ConfigFromJson(json);

  factory Config.realFromJson(Map<String, Object?>? json) {
    if (json == null) {
      return const Config(themeProps: defaultThemeProps);
    }
    return _$ConfigFromJson(json);
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
