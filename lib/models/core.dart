import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'generated/core.freezed.dart';
part 'generated/core.g.dart';

@freezed
abstract class SetupParams with _$SetupParams {
  const factory SetupParams({
    @JsonKey(name: 'selected-map') required Map<String, String> selectedMap,
    @JsonKey(name: 'test-url') required String testUrl,
    @Default(false) @JsonKey(name: 'skip-cert-verify') bool skipCertVerify,
    @JsonKey(includeIfNull: false) SetupBase? base,
  }) = _SetupParams;

  factory SetupParams.fromJson(Map<String, dynamic> json) =>
      _$SetupParamsFromJson(json);
}

@freezed
abstract class SetupBase with _$SetupBase {
  const factory SetupBase({required String path, required String overlay}) =
      _SetupBase;

  factory SetupBase.fromJson(Map<String, dynamic> json) =>
      _$SetupBaseFromJson(json);
}

@freezed
abstract class ProfileBase with _$ProfileBase {
  const factory ProfileBase({
    required Map<String, dynamic> config,
    required String digest,
    @Default([]) @JsonKey(name: 'match-rules') List<String> matchRules,
    @Default(0) int proxies,
    @Default(0) @JsonKey(name: 'proxy-groups') int proxyGroups,
    @Default(0) int rules,
  }) = _ProfileBase;

  factory ProfileBase.fromJson(Map<String, dynamic> json) =>
      _$ProfileBaseFromJson(json);
}

@freezed
abstract class UpdateParams with _$UpdateParams {
  const factory UpdateParams({
    @JsonKey(toJson: _tunCoreJson) required Tun tun,
    @JsonKey(name: 'mixed-port') required int mixedPort,
    @JsonKey(name: 'allow-lan') required bool allowLan,
    @JsonKey(name: 'find-process-mode')
    required FindProcessMode findProcessMode,
    required Mode mode,
    @JsonKey(name: 'log-level') required LogLevel logLevel,
    bool? ipv6,
    @JsonKey(name: 'tcp-concurrent') bool? tcpConcurrent,
    @JsonKey(name: 'external-controller')
    required ExternalControllerStatus externalController,
    @Default('') String secret,
    @JsonKey(name: 'unified-delay') bool? unifiedDelay,
    @Default([]) List<String> authentication,
    @Default(false) @JsonKey(name: 'geo-auto-update') bool geoAutoUpdate,
    @Default(24) @JsonKey(name: 'geo-update-interval') int geoUpdateInterval,
    @Default({}) @JsonKey(name: 'geox-url') Map<String, String> geoXUrl,
    @Default(false) @JsonKey(name: 'skip-cert-verify') bool skipCertVerify,
  }) = _UpdateParams;

  factory UpdateParams.fromJson(Map<String, dynamic> json) =>
      _$UpdateParamsFromJson(json);
}

Map<String, Object?> _tunCoreJson(Tun tun) => tun.coreJson;

@freezed
abstract class VpnOptions with _$VpnOptions {
  const factory VpnOptions({
    required bool enable,
    required int port,
    required bool ipv6,
    required bool dnsHijacking,
    required AccessControlProps accessControlProps,
    required bool allowBypass,
    required bool systemProxy,
    required List<String> bypassDomain,
    required String stack,
    @Default([]) List<String> routeAddress,
    @Default(0) int mtu,
    @Default('') String congestionController,
  }) = _VpnOptions;

  factory VpnOptions.fromJson(Map<String, Object?> json) =>
      _$VpnOptionsFromJson(json);
}

extension VpnOptionsExt on VpnOptions {
  /// Only what `ServiceController.start` and `VpnService.handleStart` read.
  VpnOptions get effective {
    if (!enable) {
      return const VpnOptions(
        enable: false,
        port: 0,
        ipv6: false,
        dnsHijacking: false,
        accessControlProps: AccessControlProps(),
        allowBypass: false,
        systemProxy: false,
        bypassDomain: [],
        stack: '',
      );
    }
    final accessControl = accessControlProps;
    final accepts = accessControl.mode == AccessControlMode.acceptSelected;
    return copyWith(
      port: systemProxy ? port : 0,
      bypassDomain: systemProxy ? bypassDomain : const [],
      accessControlProps: accessControl.enable
          ? AccessControlProps(
              enable: true,
              mode: accessControl.mode,
              acceptList: accepts ? accessControl.acceptList : const [],
              rejectList: accepts ? const [] : accessControl.rejectList,
            )
          : const AccessControlProps(),
    );
  }
}

@freezed
abstract class InitParams with _$InitParams {
  const factory InitParams({
    @JsonKey(name: 'home-dir') required String homeDir,
    required int version,
  }) = _InitParams;

  factory InitParams.fromJson(Map<String, Object?> json) =>
      _$InitParamsFromJson(json);
}

@freezed
abstract class ChangeProxyParams with _$ChangeProxyParams {
  const factory ChangeProxyParams({
    @JsonKey(name: 'group-name') required String groupName,
    @JsonKey(name: 'proxy-name') required String proxyName,
  }) = _ChangeProxyParams;

  factory ChangeProxyParams.fromJson(Map<String, Object?> json) =>
      _$ChangeProxyParamsFromJson(json);
}

@freezed
abstract class ChangeProxyResult with _$ChangeProxyResult {
  const factory ChangeProxyResult({
    @Default('') String message,
    @Default(false) bool changed,
  }) = _ChangeProxyResult;

  factory ChangeProxyResult.fromJson(Map<String, Object?> json) =>
      _$ChangeProxyResultFromJson(json);
}

@freezed
abstract class RouteSnapshot with _$RouteSnapshot {
  const factory RouteSnapshot({
    @JsonKey(name: 'core-epoch') @Default(0) int coreEpoch,
    @JsonKey(name: 'route-version') @Default(0) int routeVersion,
  }) = _RouteSnapshot;

  factory RouteSnapshot.fromJson(Map<String, Object?> json) =>
      _$RouteSnapshotFromJson(json);
}

/// [exit] is the Core's name for where a connection left, only compared whole.
@freezed
abstract class RouteHit with _$RouteHit {
  const factory RouteHit({
    @Default('') String host,
    @Default('') String proxy,
    @Default('') String exit,
  }) = _RouteHit;

  factory RouteHit.fromJson(Map<String, Object?> json) =>
      _$RouteHitFromJson(json);
}

@freezed
abstract class CheckRoutesParams with _$CheckRoutesParams {
  const factory CheckRoutesParams({@Default([]) List<List<RouteHit>> routes}) =
      _CheckRoutesParams;

  factory CheckRoutesParams.fromJson(Map<String, Object?> json) =>
      _$CheckRoutesParamsFromJson(json);
}

@freezed
abstract class RouteCheck with _$RouteCheck {
  const factory RouteCheck({
    @JsonKey(name: 'core-epoch') @Default(0) int coreEpoch,
    @JsonKey(name: 'route-version') @Default(0) int routeVersion,
    @Default([]) List<bool> held,
  }) = _RouteCheck;

  factory RouteCheck.fromJson(Map<String, Object?> json) =>
      _$RouteCheckFromJson(json);
}

@freezed
abstract class CoreEvent with _$CoreEvent {
  const factory CoreEvent({required CoreEventType type, dynamic data}) =
      _CoreEvent;

  factory CoreEvent.fromJson(Map<String, Object?> json) =>
      _$CoreEventFromJson(json);
}

@freezed
abstract class Delay with _$Delay {
  const factory Delay({required String name, required String url, int? value}) =
      _Delay;

  factory Delay.fromJson(Map<String, Object?> json) => _$DelayFromJson(json);
}

@freezed
abstract class ProbeParams with _$ProbeParams {
  const factory ProbeParams({
    required String url,
    @JsonKey(name: 'proxy-name') @Default('') String proxyName,
    @Default({}) Map<String, String> headers,
    required int timeout,
    @JsonKey(name: 'max-body') @Default(0) int maxBody,
  }) = _ProbeParams;

  factory ProbeParams.fromJson(Map<String, Object?> json) =>
      _$ProbeParamsFromJson(json);
}

@freezed
abstract class ProbeResult with _$ProbeResult {
  const factory ProbeResult({
    @JsonKey(name: 'status-code') @Default(0) int statusCode,
    @Default(0) int delay,
    @Default('') String body,
    @Default('') String url,
    @Default([]) List<String> chains,
    @Default('') String rule,
    @JsonKey(name: 'rule-payload') @Default('') String rulePayload,
    String? error,
    String? message,
  }) = _ProbeResult;

  factory ProbeResult.fromJson(Map<String, Object?> json) =>
      _$ProbeResultFromJson(json);
}

@freezed
abstract class OutboundIpParams with _$OutboundIpParams {
  const factory OutboundIpParams({
    @JsonKey(name: 'proxy-name') @Default('') String proxyName,
    @Default([]) List<String> urls,
    required int timeout,
  }) = _OutboundIpParams;

  factory OutboundIpParams.fromJson(Map<String, Object?> json) =>
      _$OutboundIpParamsFromJson(json);
}

@freezed
abstract class OutboundIpResult with _$OutboundIpResult {
  const factory OutboundIpResult({
    @Default('') String url,
    @Default('') String body,
    @Default(0) int delay,
    @Default([]) List<String> chains,
    String? error,
    @JsonKey(name: 'core-epoch') @Default(0) int coreEpoch,
    @JsonKey(name: 'route-version') @Default(0) int routeVersion,
    @Default([]) List<RouteHit> hits,
    @JsonKey(name: 'node-hits') @Default([]) List<RouteHit> nodeHits,
  }) = _OutboundIpResult;

  factory OutboundIpResult.fromJson(Map<String, Object?> json) =>
      _$OutboundIpResultFromJson(json);
}

@freezed
abstract class ServiceCheckParams with _$ServiceCheckParams {
  const factory ServiceCheckParams({
    @JsonKey(name: 'proxy-name') @Default('') String proxyName,
    @Default([]) List<String> names,
    required int timeout,
  }) = _ServiceCheckParams;

  factory ServiceCheckParams.fromJson(Map<String, Object?> json) =>
      _$ServiceCheckParamsFromJson(json);
}

@freezed
abstract class ServiceCheckItem with _$ServiceCheckItem {
  const factory ServiceCheckItem({
    @Default('') String name,
    @Default('') String status,
    @Default('') String region,
    @Default(0) int delay,
    @Default([]) List<String> chains,
    @JsonKey(name: 'checked-at') @Default(0) int checkedAt,
    @JsonKey(name: 'core-epoch') @Default(0) int coreEpoch,
    @JsonKey(name: 'route-version') @Default(0) int routeVersion,
    @Default([]) List<RouteHit> hits,
  }) = _ServiceCheckItem;

  factory ServiceCheckItem.fromJson(Map<String, Object?> json) =>
      _$ServiceCheckItemFromJson(json);
}

@freezed
abstract class CoreMemoryStats with _$CoreMemoryStats {
  const factory CoreMemoryStats({
    @Default(0) int rss,
    @Default(0) int heapInuse,
    @Default(0) int heapIdle,
    @Default(0) int stackInuse,
    @Default(0) int runtimeOther,
  }) = _CoreMemoryStats;

  factory CoreMemoryStats.fromJson(Map<String, Object?> json) =>
      _$CoreMemoryStatsFromJson(json);
}

extension CoreMemoryStatsExt on CoreMemoryStats {
  int get runtimeTotal => heapInuse + heapIdle + stackInuse + runtimeOther;
}

SubscriptionInfo? subscriptionInfoFormCore(Map<String, Object?>? json) {
  if (json == null) return null;
  return SubscriptionInfo(
    upload: (json['Upload'] as num?)?.toInt() ?? 0,
    download: (json['Download'] as num?)?.toInt() ?? 0,
    total: (json['Total'] as num?)?.toInt() ?? 0,
    expire: (json['Expire'] as num?)?.toInt() ?? 0,
  );
}

@freezed
abstract class ExternalProvider with _$ExternalProvider {
  const factory ExternalProvider({
    required String name,
    required String type,
    String? path,
    required int count,
    @JsonKey(name: 'subscription-info', fromJson: subscriptionInfoFormCore)
    SubscriptionInfo? subscriptionInfo,
    @JsonKey(name: 'vehicle-type') required String vehicleType,
    @JsonKey(name: 'update-at') required DateTime updateAt,
  }) = _ExternalProvider;

  factory ExternalProvider.fromJson(Map<String, Object?> json) =>
      _$ExternalProviderFromJson(json);
}

extension ExternalProviderExt on ExternalProvider {
  String get updatingKey => 'provider_$name';
}

@freezed
abstract class ProxiesData with _$ProxiesData {
  const factory ProxiesData({
    required Map<String, dynamic> proxies,
    required List<String> all,
  }) = _ProxiesData;

  factory ProxiesData.fromJson(Map<String, Object?> json) =>
      _$ProxiesDataFromJson(json);
}

/// 订阅转换结果。
///
/// 内核支持 Clash 之外的订阅格式 —— v2ray/SS/SSR 分享链接（base64 或明文）、
/// ssd:// 、sing-box 配置 —— 统一转成 Clash 配置后交回来。`changed` 为 false 时
/// 表示原内容本来就是 Clash 配置，`yaml` 与输入一致。
///
/// 这里刻意不写成 freezed：它只是内核协议的返回体，加进来会引入一次代码生成的
/// 负担，收益为零。
class ConvertSubscriptionResult {
  const ConvertSubscriptionResult({
    required this.yaml,
    required this.format,
    required this.nodeCount,
    required this.changed,
  });

  /// 转换后的 Clash 配置全文。
  final String yaml;

  /// 嗅探出的来源格式：clash / v2ray / ssd / sing-box / unknown。
  final String format;

  /// 转换出的节点数量；来源本身是 Clash 配置时为 0。
  final int nodeCount;

  /// 内容是否真的被改写过。
  final bool changed;

  factory ConvertSubscriptionResult.fromJson(Map<String, dynamic> json) {
    return ConvertSubscriptionResult(
      yaml: json['yaml'] as String? ?? '',
      format: json['format'] as String? ?? 'unknown',
      nodeCount: (json['nodeCount'] as num?)?.toInt() ?? 0,
      changed: json['changed'] as bool? ?? false,
    );
  }
}

/// 往配置里追加节点的结果。
///
/// [skipped] 不是失败：Clash 里同名节点会让整份配置加载失败，所以重名的只能留一个。
/// 内核选择跳过并如实回报，由调用方转成用户看得懂的提示（「跳过 2 个重名节点」）——
/// 静默丢弃会让用户以为加成功了，然后在节点列表里怎么都找不到。
class AddProxyNodesResult {
  const AddProxyNodesResult({
    required this.yaml,
    required this.added,
    required this.skipped,
  });

  /// 追加之后的配置全文。
  final String yaml;

  /// 真正加进去的节点名，按输入顺序。
  final List<String> added;

  /// 因为重名而被跳过的节点名。
  final List<String> skipped;

  factory AddProxyNodesResult.fromJson(Map<String, dynamic> json) {
    return AddProxyNodesResult(
      yaml: json['yaml'] as String? ?? '',
      added: (json['added'] as List?)?.whereType<String>().toList() ?? const [],
      skipped:
          (json['skipped'] as List?)?.whereType<String>().toList() ?? const [],
    );
  }
}

/// 从配置里删除节点的结果。
///
/// [missing] 不是失败：多半是面板数据已过期（节点刚被别处删掉）。引用清理
/// （策略组成员、规则出口、listeners）由内核同步完成，拿到的 [yaml] 一定加载得动。
class RemoveProxyNodesResult {
  const RemoveProxyNodesResult({
    required this.yaml,
    required this.removed,
    required this.missing,
  });

  /// 删除之后的配置全文。
  final String yaml;

  /// 真正删掉的节点名。
  final List<String> removed;

  /// 配置里没找到的节点名。
  final List<String> missing;

  factory RemoveProxyNodesResult.fromJson(Map<String, dynamic> json) {
    return RemoveProxyNodesResult(
      yaml: json['yaml'] as String? ?? '',
      removed:
          (json['removed'] as List?)?.whereType<String>().toList() ?? const [],
      missing:
          (json['missing'] as List?)?.whereType<String>().toList() ?? const [],
    );
  }
}

/// 原地更新一个节点参数的结果。名字是组员/规则/链式引用的锚点，内核不
/// 允许编辑改名，[updated] 恒等于请求里的名字（回传只为对称）。
class UpdateProxyNodeResult {
  const UpdateProxyNodeResult({required this.yaml, required this.updated});

  /// 更新之后的配置全文。
  final String yaml;

  /// 被更新的节点名。
  final String updated;

  factory UpdateProxyNodeResult.fromJson(Map<String, dynamic> json) {
    return UpdateProxyNodeResult(
      yaml: json['yaml'] as String? ?? '',
      updated: json['updated'] as String? ?? '',
    );
  }
}

/// 链式代理能引用的一项：一个节点，或者一个策略组。
///
/// [dialer] 只对节点有意义 —— 链挂在**节点**上（`dialer-proxy` 是 proxy 级选项），
/// 所以组的 [dialer] 恒为空。[type] 是给界面显示的（ss / vmess / Selector …）。
class ProfileTarget {
  const ProfileTarget({
    required this.name,
    required this.type,
    required this.dialer,
  });

  final String name;
  final String type;

  /// 该节点当前的前置代理名；没设过链时为空串。
  final String dialer;

  bool get isChained => dialer.isNotEmpty;

  factory ProfileTarget.fromJson(Map<String, dynamic> json) {
    return ProfileTarget(
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? '',
      dialer: json['dialer'] as String? ?? '',
    );
  }
}

/// 配置里可以做链式代理的候选名单。
///
/// 名单只能从**配置本身**读：节点名与策略组名共用 Clash 的命名空间，而覆写数据里
/// 并没有完整名单，运行时那份 ClashConfig 反映的又是「当前已生效的配置」——
/// 用户正在编辑的这一份未必是它。
class ProfileTargets {
  const ProfileTargets({
    required this.proxies,
    required this.groups,
    this.nodes = const [],
  });

  final List<ProfileTarget> proxies;
  final List<ProfileTarget> groups;

  /// proxies 段的完整参数（与 [proxies] 同序同名），编辑节点时预填表单用。
  final List<Map<String, dynamic>> nodes;

  static const ProfileTargets empty = ProfileTargets(
    proxies: [],
    groups: [],
    nodes: [],
  );

  factory ProfileTargets.fromJson(Map<String, dynamic> json) {
    List<ProfileTarget> read(String key) {
      final raw = json[key];
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((item) => ProfileTarget.fromJson(item.cast<String, dynamic>()))
          .toList();
    }

    final nodesRaw = json['nodes'];
    final nodes = nodesRaw is List
        ? nodesRaw
              .whereType<Map>()
              .map((item) => item.cast<String, dynamic>())
              .toList()
        : const <Map<String, dynamic>>[];

    return ProfileTargets(
      proxies: read('proxies'),
      groups: read('groups'),
      nodes: nodes,
    );
  }
}

/// 写入链式代理后的配置全文。
class SetProxyChainResult {
  const SetProxyChainResult({required this.yaml});

  final String yaml;

  factory SetProxyChainResult.fromJson(Map<String, dynamic> json) {
    return SetProxyChainResult(yaml: json['yaml'] as String? ?? '');
  }
}
