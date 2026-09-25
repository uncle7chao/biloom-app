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
  }) = _SetupParams;

  factory SetupParams.fromJson(Map<String, dynamic> json) =>
      _$SetupParamsFromJson(json);
}

@freezed
abstract class UpdateParams with _$UpdateParams {
  const factory UpdateParams({
    required Tun tun,
    @JsonKey(name: 'mixed-port') required int mixedPort,
    @JsonKey(name: 'allow-lan') required bool allowLan,
    @JsonKey(name: 'find-process-mode')
    required FindProcessMode findProcessMode,
    required Mode mode,
    @JsonKey(name: 'log-level') required LogLevel logLevel,
    required bool ipv6,
    @JsonKey(name: 'tcp-concurrent') required bool tcpConcurrent,
    @JsonKey(name: 'external-controller')
    required ExternalControllerStatus externalController,
    @JsonKey(name: 'unified-delay') required bool unifiedDelay,
    @Default([]) List<String> authentication,
    @Default(false) @JsonKey(name: 'geo-auto-update') bool geoAutoUpdate,
    @Default(24) @JsonKey(name: 'geo-update-interval') int geoUpdateInterval,
  }) = _UpdateParams;

  factory UpdateParams.fromJson(Map<String, dynamic> json) =>
      _$UpdateParamsFromJson(json);
}

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
  }) = _VpnOptions;

  factory VpnOptions.fromJson(Map<String, Object?> json) =>
      _$VpnOptionsFromJson(json);
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
abstract class UpdateGeoDataParams with _$UpdateGeoDataParams {
  const factory UpdateGeoDataParams({
    @JsonKey(name: 'geo-type') required String geoType,
    @JsonKey(name: 'geo-name') required String geoName,
  }) = _UpdateGeoDataParams;

  factory UpdateGeoDataParams.fromJson(Map<String, Object?> json) =>
      _$UpdateGeoDataParamsFromJson(json);
}

@freezed
abstract class CoreEvent with _$CoreEvent {
  const factory CoreEvent({required CoreEventType type, dynamic data}) =
      _CoreEvent;

  factory CoreEvent.fromJson(Map<String, Object?> json) =>
      _$CoreEventFromJson(json);
}

@freezed
abstract class InvokeMessage with _$InvokeMessage {
  const factory InvokeMessage({required InvokeMessageType type, dynamic data}) =
      _InvokeMessage;

  factory InvokeMessage.fromJson(Map<String, Object?> json) =>
      _$InvokeMessageFromJson(json);
}

@freezed
abstract class Delay with _$Delay {
  const factory Delay({required String name, required String url, int? value}) =
      _Delay;

  factory Delay.fromJson(Map<String, Object?> json) => _$DelayFromJson(json);
}

@freezed
abstract class Now with _$Now {
  const factory Now({required String name, required String value}) = _Now;

  factory Now.fromJson(Map<String, Object?> json) => _$NowFromJson(json);
}

@freezed
abstract class ProviderSubscriptionInfo with _$ProviderSubscriptionInfo {
  const factory ProviderSubscriptionInfo({
    @JsonKey(name: 'UPLOAD') @Default(0) int upload,
    @JsonKey(name: 'DOWNLOAD') @Default(0) int download,
    @JsonKey(name: 'TOTAL') @Default(0) int total,
    @JsonKey(name: 'EXPIRE') @Default(0) int expire,
  }) = _ProviderSubscriptionInfo;

  factory ProviderSubscriptionInfo.fromJson(Map<String, Object?> json) =>
      _$ProviderSubscriptionInfoFromJson(json);
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
  const ProfileTargets({required this.proxies, required this.groups});

  final List<ProfileTarget> proxies;
  final List<ProfileTarget> groups;

  static const ProfileTargets empty = ProfileTargets(
    proxies: [],
    groups: [],
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

    return ProfileTargets(proxies: read('proxies'), groups: read('groups'));
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
