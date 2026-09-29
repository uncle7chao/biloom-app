part of '../action.dart';

@Riverpod(keepAlive: true)
class BackupAction extends _$BackupAction {
  /// BiLoom 自有数据在备份 configMap 里的附加键。
  ///
  /// 链式代理与节点收藏都持久化在 shared_preferences（见 [ProxyChainStore] /
  /// [ProxyFavoritesStore]），不在 [Config] 的序列化范围内 —— 不补这两个键，
  /// 恢复备份后链和收藏会全部丢失。放 configMap 顶层附加键而不是给 Config
  /// 加字段：未知键在 json 解码里天然被忽略，旧版本读新备份、新版本读旧备份
  /// 都不炸，也绕开了改 freezed 模型必须重新生成代码的依赖。
  static const kBiLoomProxyChainsKey = 'biLoomProxyChains';
  static const kBiLoomProxyFavoritesKey = 'biLoomProxyFavorites';

  @override
  void build() {}

  Future<bool> consumeBackup(Future<bool> Function(String path) send) async {
    final path = await createBackupFile();
    if (path.isEmpty) {
      return false;
    }
    try {
      return await send(path);
    } finally {
      await File(path).safeDelete();
    }
  }

  /// 生成备份 zip 并返回路径。与 [consumeBackup] 的区别：临时文件的生命周期
  /// 交给调用方 —— 局域网同步的服务端要在整个分享期间持有它，页面关掉才删。
  Future<String> createBackupFile() {
    return backup();
  }

  @visibleForTesting
  Future<String> backup() async {
    final res = await Future.wait([
      database.profilesDao.fileNames().get(),
      database.scriptsDao.fileNames().get(),
    ]);
    final profileFileNames = res[0];
    final scriptFileNames = res[1];
    final configMap = ref.read(configProvider).toJson();
    configMap['version'] = await preferences.getVersion();
    await _fillBiLoomData(configMap);
    return backupTask(configMap, [...profileFileNames, ...scriptFileNames]);
  }

  /// 把 BiLoom 自有数据（链 + 收藏）塞进备份 configMap。空数据不写键：
  /// 恢复侧靠「键存在且非空」判断，避免拿空列表覆盖对方已有的数据。
  Future<void> _fillBiLoomData(Map<String, dynamic> configMap) async {
    final chains = await ProxyChainStore.load();
    if (chains.isNotEmpty) {
      configMap[kBiLoomProxyChainsKey] = [
        for (final chain in chains) chain.toJson(),
      ];
    }
    final favorites = await ProxyFavoritesStore.load();
    if (favorites.isNotEmpty) {
      configMap[kBiLoomProxyFavoritesKey] = favorites;
    }
  }

  Future<void> restore(RestoreOption option) async {
    final restoreDirPath = await appPath.restoreDirPath;
    final restoreDir = Directory(restoreDirPath);
    try {
      final migrationData = await restoreTask();
      if (!await restoreDir.exists()) {
        throw MessageException(currentAppLocalizations.restoreException);
      }
      await applyRestore(migrationData, option);
    } finally {
      await restoreDir.safeDelete(recursive: true);
    }
  }

  @visibleForTesting
  Future<void> applyRestore(MigrationData data, RestoreOption option) async {
    final restoreStrategy = ref.read(
      appSettingProvider.select((state) => state.restoreStrategy),
    );
    final isOverride = restoreStrategy == RestoreStrategy.override;
    final configMap = data.configMap;
    final config = option == RestoreOption.onlyProfiles || configMap == null
        ? null
        // 备份文件可能来自旧版本，里面的 DNS 上游同样是「没被动过的旧默认值」——
        // 恢复备份是「换机器继续用」的路径，不该在这里把新默认值漏掉。
        : Config.fromJson(
            configMap,
          ).migrateLegacyDnsNameservers().migrateLegacyDnsFallback();
    await database.restore(
      data.profiles,
      data.scripts,
      data.rules,
      data.links,
      data.proxyGroups,
      isOverride: isOverride,
    );
    if (config == null) {
      return;
    }
    ref.read(davSettingProvider.notifier).update((_) => config.davProps);
    ref.read(patchClashConfigProvider.notifier).value = config.patchClashConfig;
    ref.read(appSettingProvider.notifier).value = config.appSettingProps;
    ref.read(currentProfileIdProvider.notifier).value = config.currentProfileId;
    ref.read(themeSettingProvider.notifier).value = config.themeProps;
    ref.read(windowSettingProvider.notifier).value = config.windowProps;
    ref.read(vpnSettingProvider.notifier).value = config.vpnProps;
    ref.read(proxiesStyleSettingProvider.notifier).value =
        config.proxiesStyleProps;
    ref.read(overrideDnsProvider.notifier).value = config.overrideDns;
    ref.read(networkSettingProvider.notifier).value = config.networkProps;
    ref.read(hotKeyActionsProvider.notifier).value = config.hotKeyActions;
    await _restoreBiLoomData(configMap);
  }

  /// 恢复 BiLoom 自有数据（链式代理 + 节点收藏）。
  ///
  /// 只在「恢复全部数据」路径上执行 —— config == null 的 onlyProfiles 模式
  /// 明确表示「不动设置」，链与收藏随 Config 一起走。恢复后：
  ///  · 收藏：SP 落盘 + 直接把内存态 [proxyFavoritesProvider] 置为新值；
  ///    profileId 在数据库恢复时原样保留，收藏映射不会错位。
  ///  · 链：SP 落盘后重应用当前配置，让代理页签里的链条目刷新 —— 与
  ///    「添加/删除链」动作的收尾一致。
  Future<void> _restoreBiLoomData(Map<String, Object?>? configMap) async {
    final rawChains = configMap?[kBiLoomProxyChainsKey];
    if (rawChains is List) {
      final chains = <ProxyChain>[];
      for (final item in rawChains) {
        if (item is! Map) continue;
        final chain = ProxyChain.fromJson(Map<String, dynamic>.from(item));
        if (chain != null) {
          chains.add(chain);
        }
      }
      if (chains.isNotEmpty) {
        await ProxyChainStore.save(chains);
        ref
            .read(setupActionProvider.notifier)
            .applyProfileDebounce(silence: true);
      }
    }
    final rawFavorites = configMap?[kBiLoomProxyFavoritesKey];
    if (rawFavorites is Map) {
      final favorites = <String, List<String>>{};
      rawFavorites.forEach((key, value) {
        if (key is String && value is List) {
          favorites[key] = value.whereType<String>().toList();
        }
      });
      await ProxyFavoritesStore.save(favorites);
      ref.read(proxyFavoritesProvider.notifier).replaceAll(favorites);
    }
  }

  /// 自动备份：按触发开关执行，产物收进本地 auto_backups 目录（滚动保留）。
  ///
  /// 两个设计决定：① **只落本地**，不上传 WebDAV —— 远程那份文件名固定、
  /// 会被整包覆盖，自动备份把用户手动备份的远端版本顶掉属于事故；
  /// ② **失败静默**——它是「添加/删除订阅」的后台搭车动作，弹窗打断主流程
  /// 得不偿失，只记日志。
  Future<void> runAutoBackup({required AutoBackupTrigger trigger}) async {
    try {
      final settings = await AutoBackupStore.loadSettings();
      if (!settings.enabledFor(trigger)) {
        return;
      }
      final zipPath = await createBackupFile();
      try {
        await AutoBackupStore.createFromZip(
          zipPath,
          keepCount: settings.keepCount,
        );
      } finally {
        await File(zipPath).safeDelete();
      }
    } catch (error) {
      commonPrint.log('auto backup failed: $error', logLevel: LogLevel.warning);
    }
  }
}
