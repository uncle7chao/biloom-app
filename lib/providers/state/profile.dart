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
ExtendType extendType(Ref ref, int? profileId) {
  return ref.watch(
    profileProvider(
      profileId,
    ).select((state) => state?.extendType ?? ExtendType.standard),
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
  final type = ref.read(profileProvider(profileId))?.type;
  if (type == ProfileType.custom) {
    return const ClashConfig();
  }
  final outbounds = await ref
      .read(coreHandlerProvider)
      .getProfileOutbounds(profileId);
  return clashConfigTask(outbounds);
}

@riverpod
Future<SetupState> setupState(Ref ref, int? profileId) async {
  final profile = ref.watch(profileProvider(profileId));
  final scriptId = profile?.scriptId;
  final profileLastUpdateDate = profile?.lastUpdateDate?.millisecondsSinceEpoch;
  final profileType = profile?.type ?? ProfileType.file;
  final extendType = profile?.extendType ?? ExtendType.standard;
  final overrides = profileType == ProfileType.custom
      ? ref.watch(
          patchClashConfigProvider.select(
            (state) => (profile?.overrides ?? const ProfileOverrides())
                .overAppTun(state.tunOverride, state.tunOverrideKeys),
          ),
        )
      : ref.watch(
          patchClashConfigProvider.select(
            (state) => ProfileOverrides(
              dns: state.dns,
              dnsOverrideKeys: state.dnsOverrideKeys.intersection(
                DnsOverrideKey.normalProfileKeys,
              ),
              tun: state.tunOverride,
              tunOverrideKeys: state.tunOverrideKeys,
            ),
          ),
        );
  final allProfileProviders = ref.watch(profileProvidersProvider);
  List<ProxyGroup> proxyGroups = [];
  List<Rule> rules = [];
  List<Rule> addedRules = [];
  List<ClashProvider> clashProviders = [];
  Map<String, int> profileProviders = const {};
  List<CustomProxy> appProxies = [];
  Map<int, String> proxyDialers = const {};
  Script? script;
  if (profileId != null) {
    if (profileType == ProfileType.custom) {
      rules = await database.rulesDao.queryProfileRules(profileId).get();
      proxyGroups = await database.proxyGroupsDao.query(profileId).get();
      clashProviders = await database.clashProvidersDao.query().get();
      profileProviders = allProfileProviders;
      appProxies = await database.customProxiesDao.query().get();
      proxyDialers = {
        for (final dialer
            in await database.proxyDialersDao.query(profileId).get())
          dialer.proxyId: dialer.target,
      };
    } else if (extendType == ExtendType.standard) {
      addedRules = await database.rulesDao.queryAddedRules(profileId).get();
    } else if (extendType == ExtendType.script) {
      script = scriptId == null
          ? null
          : await database.scriptsDao.get(scriptId).getSingleOrNull();
    }
  }
  return SetupState(
    clashProviders: clashProviders,
    profileProviders: profileProviders,
    appProxies: appProxies,
    proxyDialers: proxyDialers,
    rules: rules,
    proxyGroups: proxyGroups,
    profileId: profileId,
    profileLastUpdateDate: profileLastUpdateDate,
    profileType: profileType,
    extendType: extendType,
    overwriteType:
        profile?.overwriteType ?? OverwriteType.standard,
    addedRules: addedRules,
    script: script,
    overrides: overrides,
    matchTarget:
        profileType != ProfileType.custom && extendType == ExtendType.standard
        ? profile?.matchTarget
        : null,
  );
}

/// Subscription profiles double as proxy providers for custom profiles.
@riverpod
Map<String, int> profileProviders(Ref ref) {
  final profiles = ref.watch(profilesProvider);
  return {
    for (final profile in profiles)
      if (profile.type != ProfileType.custom) profile.realLabel: profile.id,
  };
}
