part of '../state.dart';

/// 各订阅配置最近一次**自动/手动更新失败**的记录（profileId 字符串 → 状态）。
///
/// 自动更新在后台静默跑，失败以前只有一行日志，订阅过期要等用户手动更新
/// 才暴露（2026-09-25 自检定性）。持久层在 `common/profile_update_status.dart`
/// （shared_preferences），这里只做两件事：启动时读一次、更新成败时增删。
///
/// 手写 `AsyncNotifierProvider` 不加 `@riverpod` 注解：生成器环境故障的老
/// 问题（见 `state/proxies.dart` 里 ProxyExitStore 同样的处理）。
class ProfileUpdateStatuses
    extends AsyncNotifier<Map<String, ProfileUpdateStatus>> {
  @override
  Future<Map<String, ProfileUpdateStatus>> build() =>
      ProfileUpdateStatusStore.load();

  void recordFailure(int profileId, Object error) {
    final next = Map<String, ProfileUpdateStatus>.from(state.value ?? const {});
    next[profileId.toString()] = ProfileUpdateStatus(
      error: compactError(error),
      at: DateTime.now().millisecondsSinceEpoch,
    );
    state = AsyncData(next);
    unawaited(ProfileUpdateStatusStore.save(next));
  }

  void clear(int profileId) {
    final current = state.value;
    if (current == null || !current.containsKey(profileId.toString())) {
      return;
    }
    final next = Map<String, ProfileUpdateStatus>.from(current)
      ..remove(profileId.toString());
    state = AsyncData(next);
    unawaited(ProfileUpdateStatusStore.save(next));
  }
}

final profileUpdateStatusesProvider =
    AsyncNotifierProvider<ProfileUpdateStatuses, Map<String, ProfileUpdateStatus>>(
      ProfileUpdateStatuses.new,
    );

@riverpod
ProfilesState profilesState(Ref ref) {
  final currentProfileId = ref.watch(currentProfileIdProvider);
  final profiles = ref.watch(profilesProvider);
  return ProfilesState(profiles: profiles, currentProfileId: currentProfileId);
}

@riverpod
Profile? currentProfile(Ref ref) {
  final profileId = ref.watch(currentProfileIdProvider);
  return ref.watch(
    profilesProvider.select((state) => state.getProfile(profileId)),
  );
}

@riverpod
Profile? profile(Ref ref, int? profileId) {
  return ref.watch(
    profilesProvider.select((state) => state.getProfile(profileId)),
  );
}

@riverpod
OverwriteType overwriteType(Ref ref, int? profileId) {
  return ref.watch(
    profileProvider(
      profileId,
    ).select((state) => state?.overwriteType ?? OverwriteType.standard),
  );
}

@riverpod
Future<ClashConfig> clashConfig(Ref ref, int profileId) async {
  final configMap = await ref.read(coreHandlerProvider).getConfig(profileId);
  return clashConfigTask(configMap);
}

@riverpod
Future<SetupState> setupState(Ref ref, int? profileId) async {
  final profile = ref.watch(profileProvider(profileId));
  final scriptId = profile?.scriptId;
  final profileLastUpdateDate = profile?.lastUpdateDate?.millisecondsSinceEpoch;
  final overwriteType = profile?.overwriteType ?? OverwriteType.standard;
  final dns = ref.watch(patchClashConfigProvider.select((state) => state.dns));
  final overrideDns = ref.watch(overrideDnsProvider);
  List<ProxyGroup> proxyGroups = [];
  List<Rule> rules = [];
  List<Rule> addedRules = [];
  Script? script;
  if (profileId != null) {
    if (overwriteType == OverwriteType.standard) {
      addedRules = await database.rulesDao.queryAddedRules(profileId).get();
    } else if (overwriteType == OverwriteType.script) {
      script = scriptId == null
          ? null
          : await database.scriptsDao.get(scriptId).getSingleOrNull();
    } else {
      rules = await database.rulesDao.queryProfileCustomRules(profileId).get();
      proxyGroups = await database.proxyGroupsDao.query(profileId).get();
    }
  }
  return SetupState(
    rules: rules,
    proxyGroups: proxyGroups,
    profileId: profileId,
    profileLastUpdateDate: profileLastUpdateDate,
    overwriteType: overwriteType,
    addedRules: addedRules,
    script: script,
    overrideDns: overrideDns,
    dns: dns,
    matchTarget: overwriteType == OverwriteType.standard
        ? profile?.matchTarget
        : null,
  );
}
