part of '../action.dart';

typedef BackupDelivery = Future<bool> Function(String archivePath);

/// Returns the archive to restore, or null when the user backed out. A source
/// that downloads writes to [downloadPath], which is removed afterwards.
typedef BackupFetch = Future<String?> Function(String downloadPath);

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

  Future<bool> backup(BackupDelivery deliver) {
    return _withWorkDir((workDir) async {
      return deliver(await _createArchive(workDir));
    });
  }

  Future<bool> restore(RestoreOption option, BackupFetch fetch) {
    return _withWorkDir((workDir) async {
      final archivePath = await fetch(join(workDir, 'download.zip'));
      if (archivePath == null) {
        return false;
      }
      final stagingDirPath = join(workDir, 'staging');
      final MigrationData data;
      try {
        data = await restoreTask((
          archivePath: archivePath,
          stagingDirPath: stagingDirPath,
        ));
      } on BackupException catch (e) {
        throw MessageException(switch (e.failure) {
          BackupFailure.invalid => currentAppLocalizations.invalidBackupFile,
          BackupFailure.newerVersion =>
            currentAppLocalizations.backupFromNewerVersion,
        });
      }
      await applyRestore(data, option, stagingDirPath: stagingDirPath);
      return true;
    });
  }

  /// 生成备份 zip 并返回路径。与 [backup] 的区别：临时文件的生命周期
  /// 交给调用方 —— 局域网同步的服务端要在整个分享期间持有它，页面关掉才删。
  Future<String> createBackupFile() async {
    final workDir = Directory(
      join(await appPath.tempPath, 'lanbackup$uniqueId'),
    );
    await workDir.create(recursive: true);
    try {
      return await _createArchive(workDir.path);
    } catch (_) {
      await workDir.safeDelete(recursive: true);
      rethrow;
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
      await backup((archivePath) async {
        // workDir 在 deliver 返回后即被清理，产物必须先挪进独立临时文件。
        final tempZip = join(await appPath.tempPath, 'auto_backup$uniqueId');
        await File(archivePath).safeCopy(tempZip);
        try {
          await AutoBackupStore.createFromZip(
            tempZip,
            keepCount: settings.keepCount,
          );
        } finally {
          await File(tempZip).safeDelete();
        }
        return true;
      });
    } catch (error) {
      commonPrint.log('auto backup failed: $error', logLevel: LogLevel.warning);
    }
  }

  Future<bool> _withWorkDir(Future<bool> Function(String workDir) run) async {
    final workDir = Directory(join(await appPath.tempPath, 'backup$uniqueId'));
    await workDir.create(recursive: true);
    try {
      return await run(workDir.path);
    } finally {
      await workDir.safeDelete(recursive: true);
      await _discardLegacyStaging();
    }
  }

  /// Earlier versions staged restores in the home directory and never removed
  /// the downloaded archive.
  Future<void> _discardLegacyStaging() async {
    final homeDirPath = await appPath.homeDirPath;
    await File(join(homeDirPath, 'backup.zip')).safeDelete();
    await Directory(join(homeDirPath, 'restore')).safeDelete(recursive: true);
  }

  Future<String> _createArchive(String workDir) async {
    final databaseSnapshotPath = join(workDir, backupDatabaseName);
    await database.customStatement('VACUUM INTO ?', [databaseSnapshotPath]);
    final (profileIds, scriptIds, providers) = await (
      database.profilesDao.query().map((item) => item.id).get(),
      database.scriptsDao.query().map((item) => item.id).get(),
      database.clashProvidersDao.query().get(),
    ).wait;
    final configMap = ref.read(configProvider).toJson();
    configMap['version'] = await preferences.getVersion();
    await _fillBiLoomData(configMap);
    final archivePath = join(workDir, 'backup.zip');
    await backupTask((
      archivePath: archivePath,
      configMap: configMap,
      databaseSnapshotPath: databaseSnapshotPath,
      homeDirPath: await appPath.homeDirPath,
      entries: BackupEntries.of(
        profileIds: profileIds,
        scriptIds: scriptIds,
        providers: providers,
      ),
    ));
    return archivePath;
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

  @visibleForTesting
  Future<void> applyRestore(
    MigrationData data,
    RestoreOption option, {
    String? stagingDirPath,
  }) async {
    final configMap = data.configMap;
    final config = option == RestoreOption.onlyProfiles || configMap == null
        ? null
        // 备份文件可能来自旧版本，里面的 DNS 上游同样是「没被动过的旧默认值」——
        // 恢复备份是「换机器继续用」的路径，不该在这里把新默认值漏掉。
        : Config.fromJson(
            configMap,
          ).migrateLegacyDnsNameservers().migrateLegacyDnsFallback();
    final isOverride =
        ref.read(appSettingProvider).restoreStrategy ==
        RestoreStrategy.override;
    final previousProviders = await database.clashProvidersDao.query().get();
    final putBack = stagingDirPath == null
        ? null
        : await _copyStagedFiles(data, stagingDirPath);
    try {
      await database.restore(
        data.profiles,
        data.scripts,
        data.rules,
        data.disabledRules,
        data.proxyGroups,
        clashProviders: data.clashProviders,
        customProxies: data.customProxies,
        proxyDialers: data.proxyDialers,
        isOverride: isOverride,
      );
    } catch (_) {
      await putBack?.call();
      rethrow;
    }
    await _clearReplacedProviderCaches(previousProviders);
    await _clearOutdatedCompiledRuleSets(data.clashProviders);
    if (config == null) {
      return;
    }
    // A desktop backup carries no package lists; the apps picked here stay.
    final accessControlProps = config.vpnProps.accessControlProps.hasPackages
        ? config.vpnProps.accessControlProps
        : ref.read(vpnSettingProvider).accessControlProps;
    writeConfig(
      ref,
      config.copyWith(
        davProps: config.davProps ?? ref.read(davSettingProvider),
        vpnProps: config.vpnProps.copyWith(
          accessControlProps: accessControlProps,
        ),
      ),
    );
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

  /// The files go in before the rows that name them, so the returned callback
  /// is how a restore whose rows fail takes them back out.
  Future<Future<void> Function()> _copyStagedFiles(
    MigrationData data,
    String stagingDirPath,
  ) async {
    final homeDirPath = await appPath.homeDirPath;
    final replacedDirPath = join(stagingDirPath, 'replaced');
    final copied = <String, bool>{};
    Future<void> putBack() async {
      for (final MapEntry(key: entry, value: replaced) in copied.entries) {
        final target = BackupEntries.resolve(homeDirPath, entry);
        if (replaced) {
          await File(
            BackupEntries.resolve(replacedDirPath, entry),
          ).safeCopy(target);
        } else {
          await File(target).safeDelete();
        }
      }
    }

    try {
      for (final entry in BackupEntries.ofData(data)) {
        final staged = File(BackupEntries.resolve(stagingDirPath, entry));
        if (!await staged.exists()) {
          continue;
        }
        final target = File(BackupEntries.resolve(homeDirPath, entry));
        final replaced = await target.exists();
        if (replaced) {
          await target.safeCopy(BackupEntries.resolve(replacedDirPath, entry));
        }
        copied[entry] = replaced;
        await staged.safeCopy(target.path);
      }
    } catch (_) {
      await putBack();
      rethrow;
    }
    return putBack;
  }

  Future<void> _clearReplacedProviderCaches(
    List<ClashProvider> previousProviders,
  ) async {
    final kept = (await database.clashProvidersDao.fileNames().get()).toSet();
    for (final provider in previousProviders) {
      if (kept.contains(provider.fileName)) {
        continue;
      }
      await File(await provider.path).safeDelete();
      await File(await provider.compiledPath).safeDelete();
    }
  }

  /// A restored source outdates the mrs compiled from the one it replaced.
  Future<void> _clearOutdatedCompiledRuleSets(
    List<ClashProvider> restored,
  ) async {
    for (final provider in restored) {
      if (!provider.isRemote) {
        await File(await provider.compiledPath).safeDelete();
      }
    }
  }
}
