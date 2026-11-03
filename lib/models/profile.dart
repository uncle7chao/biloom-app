import 'dart:io';
import 'dart:typed_data';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'clash_config.dart';

part 'generated/profile.freezed.dart';
part 'generated/profile.g.dart';

typedef ValidateConfig =
    Future<String> Function(String path, String ageSecretKey);

/// 把任意订阅内容转成标准 Clash 配置。
///
/// [fromRemote] 区分**这些字节是从哪来的**：`true` 表示刚下载回来的响应体，
/// 这时「空」意味着链接有问题（过期/被限流/被墙），必须报错；缺省（本地文件、
/// 编辑页保存）时空内容**是合法状态**，内核会按默认值跑。
///
/// 上游没有这个维度：两处来源共用一个回调，于是那句为「下载」写的空守卫
/// 拦掉了「本地保存」——内核早就为此做好的空 profile 短路（core/subscription.go
/// 的 blankSubscription）等于没生效。
typedef ConvertSubscription = Future<Uint8List> Function(
  Uint8List bytes, {
  bool? fromRemote,
});

@freezed
abstract class SubscriptionInfo with _$SubscriptionInfo {
  const factory SubscriptionInfo({
    @Default(0) int upload,
    @Default(0) int download,
    @Default(0) int total,
    @Default(0) int expire,
  }) = _SubscriptionInfo;

  factory SubscriptionInfo.fromJson(Map<String, Object?> json) =>
      _$SubscriptionInfoFromJson(json);

  factory SubscriptionInfo.formHString(String? info) {
    if (info == null) return const SubscriptionInfo();
    final Map<String, int> map = {};
    for (final field in info.split(';')) {
      final separator = field.indexOf('=');
      if (separator == -1) continue;
      final value = _parseCount(field.substring(separator + 1).trim());
      if (value != null) {
        map[field.substring(0, separator).trim().toLowerCase()] = value;
      }
    }
    return SubscriptionInfo(
      upload: map['upload'] ?? 0,
      download: map['download'] ?? 0,
      total: map['total'] ?? 0,
      expire: map['expire'] ?? 0,
    );
  }

  static int? _parseCount(String value) {
    final count = int.tryParse(value);
    if (count != null) return count;
    final decimal = double.tryParse(value);
    return decimal != null && decimal.isFinite ? decimal.truncate() : null;
  }
}

extension SubscriptionInfoExt on SubscriptionInfo {
  double? get usage =>
      total > 0 ? ((upload + download) / total).clamp(0.0, 1.0) : null;

  DateTime? get expireDate =>
      expire > 0 ? DateTime.fromMillisecondsSinceEpoch(expire * 1000) : null;
}

@freezed
abstract class Profile with _$Profile {
  const factory Profile({
    required int id,
    @Default(ProfileType.file) ProfileType type,
    @Default('') String label,
    String? currentGroupName,
    @Default('') String url,
    @Default('') String ageSecretKey,
    DateTime? lastUpdateDate,
    required Duration autoUpdateDuration,
    SubscriptionInfo? subscriptionInfo,
    @Default(true) bool autoUpdate,
    @Default({}) Map<String, String> selectedMap,
    @Default(OverwriteType.standard) OverwriteType overwriteType,
    @Default({}) Set<String> unfoldSet,
    @Default(ExtendType.standard) ExtendType extendType,
    int? scriptId,
    String? matchTarget,
    int? order,
    @Default(ProfileOverrides())
    @JsonKey(fromJson: ProfileOverrides.safeFromJson)
    ProfileOverrides overrides,
  }) = _Profile;

  factory Profile.fromJson(Map<String, Object?> json) =>
      _$ProfileFromJson(json);

  factory Profile.normal({String? label, String url = ''}) {
    final id = snowflake.id;
    return Profile(
      type: url.isEmpty ? ProfileType.file : ProfileType.url,
      label: label ?? '',
      url: url,
      id: id,
      autoUpdateDuration: defaultUpdateDuration,
    );
  }

  factory Profile.custom({String? label}) {
    return Profile(
      id: snowflake.id,
      type: ProfileType.custom,
      label: label ?? '',
      lastUpdateDate: DateTime.now(),
      autoUpdate: false,
      autoUpdateDuration: defaultUpdateDuration,
    );
  }
}

/// A profile leaving out one of the global rules its extension would add.
@freezed
abstract class DisabledRule with _$DisabledRule {
  const factory DisabledRule({required int profileId, required int ruleId}) =
      _DisabledRule;
}

extension ProfilesExt on List<Profile> {
  Profile? getProfile(int? profileId) {
    final index = indexWhere((profile) => profile.id == profileId);
    return index == -1 ? null : this[index];
  }

  Profile optimizeLabel(Profile profile) {
    return profile.copyWith(
      label: uniqueLabelFor(
        profile.label,
        fallback: profile.defaultLabel,
        taken: (label) =>
            any((item) => item.label == label && item.id != profile.id),
      ),
    );
  }
}

extension ProfileExtension on Profile {
  bool get realAutoUpdate => type == ProfileType.url && autoUpdate;

  String get realLabel => label.takeFirstValid([defaultLabel]);

  String get defaultLabel => url.webUri?.host ?? id.toString();

  String get fileName => '$id.yaml';

  String get exportFileName {
    final label = realLabel;
    final lower = label.toLowerCase();
    if (lower.endsWith('.yaml') || lower.endsWith('.yml')) {
      return label;
    }
    return '$label.yaml';
  }

  String get updatingKey => 'profile_$id';

  Future<Profile?> checkAndUpdateAndCopy({
    required ValidateConfig validate,
    required ConvertSubscription convert,
  }) async {
    if (type != ProfileType.url) {
      return null;
    }
    final mFile = await _getFile(false);
    if (await mFile.exists()) {
      return null;
    }
    return update(validate: validate, convert: convert);
  }

  Future<File> _getFile([bool autoCreate = true]) async {
    final path = await appPath.getProfilePath(id.toString());
    final file = File(path);
    final isExists = await file.exists();
    if (!isExists && autoCreate) {
      return file.create(recursive: true);
    }
    return file;
  }

  Future<File> get file async {
    return _getFile();
  }

  Future<Profile> update({
    required ValidateConfig validate,
    required ConvertSubscription convert,
  }) async {
    final response = await request.getFileResponseForUrl(url);
    final disposition = response.headers.value('content-disposition');
    final userinfo = response.headers.value('subscription-userinfo');
    return copyWith(
      label: label.takeFirstValid([
        getFileNameForDisposition(disposition),
        defaultLabel,
      ]),
      subscriptionInfo: SubscriptionInfo.formHString(userinfo),
    ).saveFile(
      // 这是刚下载回来的响应体。正文为空是「链接有问题」而不是「本地配置是空的」，
      // 两者必须分开 —— 详见 [ConvertSubscription] 的说明。
      decompressUnlabeled(response.data ?? Uint8List.fromList([])),
      fromRemote: true,
      validate: validate,
      convert: convert,
    );
  }

  Future<Profile> saveFile(
    Uint8List bytes, {
    bool fromRemote = false,
    required ValidateConfig validate,
    required ConvertSubscription convert,
  }) async {
    // 订阅兼容层。内核能识别 Clash 之外的 v2ray/SS/SSR 分享链接订阅（base64 或明文）、
    // ssd:// 与 sing-box 配置，这里先转成标准 Clash 配置再落盘，好处是 profile 文件
    // 本身始终是人类可读的 Clash 配置 —— 编辑配置页、覆写模板、节点页、延迟测试
    // 全都不必知道订阅原本是什么格式。
    //
    // 空内容同样走这里，且**不能被拦**：本地保存一份空配置是合法状态（新建的空白
    // 配置、被用户清空的配置），转换器会原样放行，落盘后由内核按默认值跑。
    final data = await convert(bytes, fromRemote: fromRemote);
    final path = await appPath.tempFilePath;
    final tempFile = File(path);
    await tempFile.safeWriteAsBytes(data);
    final message = await validate(path, ageSecretKey);
    if (message.isNotEmpty) {
      throw MessageException(message);
    }
    final mFile = await file;
    await tempFile.copy(mFile.path);
    await tempFile.safeDelete();
    return copyWith(lastUpdateDate: DateTime.now());
  }
}


// fork 兼容：规则与订阅的挂载关系（自定义规则编辑器数据层）。
@freezed
abstract class ProfileRuleLink with _$ProfileRuleLink {
  const factory ProfileRuleLink({
    int? profileId,
    required int ruleId,
    RuleScene? scene,
    String? order,
  }) = _ProfileRuleLink;
}

extension ProfileRuleLinkExt on ProfileRuleLink {
  String get key {
    final splits = <String?>[
      profileId?.toString(),
      ruleId.toString(),
      scene?.name,
    ];
    return splits.where((item) => item != null).join('_');
  }
}
