part of '../action.dart';

@Riverpod(keepAlive: true)
class ProfilesAction extends _$ProfilesAction {
  CoreController get _core => ref.read(coreHandlerProvider);

  @override
  void build() {}

  void updateCurrentSelectedMap(String groupName, String proxyName) {
    final currentProfile = ref.read(currentProfileProvider);
    if (currentProfile != null &&
        currentProfile.selectedMap[groupName] != proxyName) {
      final selectedMap = Map<String, String>.from(currentProfile.selectedMap)
        ..[groupName] = proxyName;
      ref
          .read(profilesProvider.notifier)
          .put(currentProfile.copyWith(selectedMap: selectedMap));
    }
  }

  Future<void> deleteProfile(int id) async {
    await ref.read(profilesProvider.notifier).del(id);
    await clearEffect(id);
    final currentProfileId = ref.read(currentProfileIdProvider);
    if (currentProfileId == id) {
      final profiles = ref.read(profilesProvider);
      if (profiles.isNotEmpty) {
        final updateId = profiles.first.id;
        ref.read(currentProfileIdProvider.notifier).value = updateId;
      } else {
        ref.read(currentProfileIdProvider.notifier).value = null;
        unawaited(ref.read(setupActionProvider.notifier).setRunning(false));
      }
    }
  }

  Future<String> validateConfigWithData(String data) async {
    return _core.validateConfigWithData(data);
  }

  /// 订阅兼容层：把内核能识别的任意订阅格式统一转成标准 Clash 配置。
  ///
  /// 内核报出来的都是面向用户的中文说明，这里统一改包成 [MessageException]，
  /// 好让它走和「配置校验失败」一样的提示通道（同一个错误弹窗）。
  ///
  /// [fromRemote] 表示字节是刚下载回来的响应体。只有这种来源下「空内容」才是错误；
  /// 本地保存空配置（新建空白配置、清空编辑器）是合法状态，必须放行 —— 见
  /// [ConvertSubscription] 的说明。
  Future<Uint8List> convertSubscription(
    Uint8List bytes, {
    bool? fromRemote,
  }) async {
    if (bytes.isEmpty) {
      // 「服务端响应了、正文却是空的」只可能发生在下载路径上：链接过期、被限流、被墙。
      if (fromRemote == true) {
        throw const MessageException('订阅内容为空，请检查链接是否可以正常访问');
      }
      // 本地空配置。这里直接原样返回，**不再问内核**：内核的 handleConvertSubscription
      // 是给「刚下载的内容」写的，对空输入同样回上面那句「订阅内容为空」—— 对本地
      // 场景文不对题；而读磁盘那条路径（subscriptionToProfileYAML）早就为这个场景
      // 做了 blankSubscription 短路。上游把两处来源混在一个回调里，才让那句为下载
      // 写的提示拦掉了本地保存。
      return bytes;
    }
    try {
      final result = await _core.convertSubscription(
        utf8.decode(bytes, allowMalformed: true),
      );
      // 没有发生转换（本来就是 Clash 配置）时原样返回入参。
      // 走一遍 decode(allowMalformed) → encode 是有损的：用 GBK/ANSI 存过的配置
      // （中文节点名在国内很常见）会被静默写成一片 U+FFFD 替换符，而且校验还会
      // 通过，用户以为导入正常，直到看见节点名全成了乱码。
      if (!result.changed) {
        return bytes;
      }
      return Uint8List.fromList(utf8.encode(result.yaml));
    } on CoreMethodException catch (e) {
      throw MessageException(e.message);
    }
  }

  Future<void> autoUpdateProfiles() async {
    for (final profile in ref.read(profilesProvider)) {
      if (!profile.autoUpdate) continue;
      final isNotNeedUpdate = profile.lastUpdateDate
          ?.add(profile.autoUpdateDuration)
          .isBeforeNow;
      if (isNotNeedUpdate == false || profile.type == ProfileType.file) {
        continue;
      }
      try {
        await updateProfile(profile);
      } catch (e) {
        commonPrint.log(compactError(e), logLevel: LogLevel.warning);
      }
    }
  }

  void putProfile(Profile profile) {
    ref.read(profilesProvider.notifier).put(profile);
    if (ref.read(currentProfileIdProvider) != null) return;
    ref.read(currentProfileIdProvider.notifier).value = profile.id;
  }

  Future<void> updateProfiles() async {
    for (final profile in ref.read(profilesProvider)) {
      if (profile.type == ProfileType.file) continue;
      await updateProfile(profile);
    }
  }

  Future<void> updateProfile(
    Profile profile, {
    bool showLoading = false,
  }) async {
    // 自定义配置（本地文件型）没有远程订阅可拉。以前这里对 file 型是「静默跳过」，
    // 用户点「更新」毫无反应（2026-09-25 用户报障）。现在语义改为：重新应用——
    // 把本地文件重新过一遍转换器 + 校验，内核转换逻辑升级或外部编辑后点一下即生效。
    if (profile.type == ProfileType.file) {
      return reapplyProfile(profile, showLoading: showLoading);
    }
    final operation = showLoading
        ? ref.read(updatingKeysProvider.notifier).start(profile.updatingKey)
        : null;
    try {
      ref.read(profilesProvider.notifier).put(profile);
      final newProfile = await profile.update(
        validate: (path) => _core.validateConfig(path),
        convert: convertSubscription,
      );
      ref.read(profilesProvider.notifier).put(newProfile);
      if (profile.id == ref.read(currentProfileIdProvider)) {
        ref
            .read(setupActionProvider.notifier)
            .applyProfileDebounce(silence: true);
      }
    } finally {
      if (operation != null) {
        ref
            .read(updatingKeysProvider.notifier)
            .stop(profile.updatingKey, operation);
      }
    }
  }

  /// 重新应用一份本地配置：读当前文件字节 → convert（订阅兼容层重跑）→
  /// 校验 → 落盘 → 若是当前配置则重新 setup。失败时原文件未被触碰
  /// （saveFile 先写临时文件、校验通过才覆盖），错误会正常抛给调用方展示。
  Future<void> reapplyProfile(
    Profile profile, {
    bool showLoading = false,
  }) async {
    final operation = showLoading
        ? ref.read(updatingKeysProvider.notifier).start(profile.updatingKey)
        : null;
    try {
      final mFile = await profile.file;
      final bytes = mFile.readAsBytesSync();
      final newProfile = await profile.saveFile(
        bytes,
        validate: (path) => _core.validateConfig(path),
        convert: convertSubscription,
      );
      ref.read(profilesProvider.notifier).put(newProfile);
      if (profile.id == ref.read(currentProfileIdProvider)) {
        ref
            .read(setupActionProvider.notifier)
            .applyProfileDebounce(silence: true);
      }
    } finally {
      if (operation != null) {
        ref
            .read(updatingKeysProvider.notifier)
            .stop(profile.updatingKey, operation);
      }
    }
  }

  Future<void> addProfileFormFile() async {
    final platformFile = await globalState.safeRun(picker.pickerFile);
    if (platformFile == null) return;
    final bytes = await platformFile.readBytes();
    globalState.navigatorKey.currentState?.popUntil((route) => route.isFirst);
    ref.read(currentPageLabelProvider.notifier).toProfiles();
    final profile = await globalState.loadingRun(
      tag: LoadingTag.profiles,
      () async {
        return Profile.normal(label: platformFile.name).saveFile(
          bytes,
          validate: (path) => _core.validateConfig(path),
          convert: convertSubscription,
        );
      },
      title: currentAppLocalizations.addProfile,
    );
    if (profile != null) {
      putProfile(profile);
    }
  }

  /// 新建一份空白配置。
  ///
  /// 空配置是内核认可的合法状态（`core/subscription.go` 的 blankSubscription 专门为它
  /// 短路，否则新建的配置一加载就报「无法识别的订阅」）。落盘后 makeRealProfile 会补齐
  /// 端口/DNS/TUN/rules 等脚手架，所以它是一份「合法、但还没有节点的完整配置」。
  ///
  /// 这是唯一一条**不依赖任何外部来源**（订阅链接 / 本地文件 / 二维码）的入口 ——
  /// 用户的诉求就是「像别的软件那样先建个空的，再自己往里加节点」。
  Future<void> addProfileFormBlank([String label = '']) async {
    final trimmed = label.trim();
    final profile = await globalState.loadingRun(
      tag: LoadingTag.profiles,
      () async {
        return Profile.normal(label: trimmed.isEmpty ? null : trimmed).saveFile(
          // 真的落 0 字节：不替用户写任何「模板」。约定就是「空 = 按默认值跑」，
          // 塞一份骨架反而会让内核那条短路失去意义。
          Uint8List(0),
          validate: (path) => _core.validateConfig(path),
          convert: convertSubscription,
        );
      },
      title: currentAppLocalizations.createProfile,
    );
    if (profile == null) return;
    ref.read(currentPageLabelProvider.notifier).toProfiles();
    putProfile(profile);
  }

  Future<void> addProfileFormURL(String url) async {
    if (globalState.navigatorKey.currentState?.canPop() ?? false) {
      globalState.navigatorKey.currentState?.popUntil((route) => route.isFirst);
    }
    ref.read(currentPageLabelProvider.notifier).value = PageLabel.profiles;
    final profile = await globalState.loadingRun(
      tag: LoadingTag.profiles,
      () async {
        return Profile.normal(url: url).update(
          validate: (path) => _core.validateConfig(path),
          convert: convertSubscription,
        );
      },
      title: currentAppLocalizations.addProfile,
    );
    if (profile != null) {
      putProfile(profile);
    }
  }

  void setProfileAndAutoApply(Profile profile) {
    ref.read(profilesProvider.notifier).put(profile);
    if (profile.id == ref.read(currentProfileIdProvider)) {
      ref.read(setupActionProvider.notifier).applyProfileDebounce();
    }
  }

  Future<void> addProfileFormQrCode() async {
    final url = await globalState.safeRun(picker.pickerConfigQRCode);
    if (url == null) return;
    unawaited(addProfileFormURL(url));
  }

  void reorder(List<Profile> profiles) {
    ref.read(profilesProvider.notifier).reorder(profiles);
  }

  Future<void> clearEffect(int profileId) async {
    final profilePath = await appPath.getProfilePath(profileId.toString());
    final profileFile = File(profilePath);
    final isExists = await profileFile.exists();
    if (isExists) {
      await profileFile.safeDelete(recursive: true);
    }
    try {
      final error = await _core.clearEffect(profileId);
      if (error.isNotEmpty) {
        commonPrint.log(error, logLevel: LogLevel.warning);
      }
    } catch (error) {
      commonPrint.log(
        'clearEffect($profileId) failed: $error',
        logLevel: coreFailureLogLevel(error),
      );
    }
  }

  /// 三个「改配置」动作共用的一段收尾：整份写回 + 落库 + 必要时重新应用。
  ///
  /// 为什么整份写回、而不是在文件末尾追加一段文本：配置的其余部分是由内核在
  /// **语法树层面**原样带回来的（注释、这版内核还不认识的顶层键都在），Dart 侧
  /// 全程不解析 YAML，所以不存在「拼错一个缩进毁掉整份配置」的可能。
  ///
  /// 写回仍然过一遍 validate：用户手写的 YAML 片段里可能带内核不认的字段
  /// （比如 type 写错），那必须当场报错 —— 让它一路落盘、直到下次连接时才
  /// 加载失败，排查成本高得多。
  Future<void> _saveEditedProfile(Profile profile, String yaml) async {
    final saved = await profile.saveFile(
      Uint8List.fromList(utf8.encode(yaml)),
      validate: (path) => _core.validateConfig(path),
      convert: convertSubscription,
    );
    setProfileAndAutoApply(saved);
  }

  /// 往指定配置里追加节点，返回内核的处理结果（失败时返回 null）。
  ///
  /// [nodes] 同时接受分享链接（可多行批量粘贴）与 YAML 片段，由内核自己判断是哪
  /// 一种 —— 所以界面上只需要一个粘贴框，不必先让用户选「你要加哪种」。
  ///
  /// 返回体里的 `skipped` 是重名被跳过的节点：Clash 里同名节点会让整份配置加载
  /// 失败，所以只能留一个。调用方应当把这件事提示给用户 —— 静默跳过会让他以为
  /// 加成功了，然后在节点列表里怎么都找不到。
  Future<AddProxyNodesResult?> addProxyNodesToProfile({
    required int profileId,
    required String nodes,
  }) async {
    return globalState.loadingRun(tag: LoadingTag.profiles, () async {
      final profile = ref.read(profilesProvider).getProfile(profileId);
      if (profile == null) {
        throw const MessageException('找不到这份配置，可能已被删除');
      }
      final file = await profile.file;
      final edited = await _core.addProxyNodes(
        yaml: await file.readAsString(),
        nodes: nodes,
      );
      if (edited.added.isEmpty && edited.skipped.isEmpty) {
        throw const MessageException('没有解析出任何节点');
      }
      await _saveEditedProfile(profile, edited.yaml);
      return edited;
    }, title: currentAppLocalizations.addProxyNode);
  }

  /// 从指定配置里删除节点，返回内核的处理结果（失败时返回 null）。
  ///
  /// 删除是内核侧的文档级编辑：策略组成员、指向该节点的规则、listeners 引用
  /// 都由内核同步清理 —— 这些地方漏掉任何一个，整份配置加载失败。Dart 侧只管
  /// 读文件、调内核、保存。
  Future<RemoveProxyNodesResult?> removeProxyNodesFromProfile({
    required int profileId,
    required List<String> names,
  }) async {
    return globalState.loadingRun(tag: LoadingTag.profiles, () async {
      final profile = ref.read(profilesProvider).getProfile(profileId);
      if (profile == null) {
        throw const MessageException('找不到这份配置，可能已被删除');
      }
      final file = await profile.file;
      final edited = await _core.removeProxyNodes(
        yaml: await file.readAsString(),
        names: names,
      );
      await _saveEditedProfile(profile, edited.yaml);
      return edited;
    }, title: currentAppLocalizations.manageNodes);
  }

  /// 列出这份配置里可以做链式代理的节点与策略组。
  ///
  /// 不套 [globalState.loadingRun]：界面自己有一层加载态，这里再盖一层全屏遮罩
  /// 只会让「打开面板」这个动作闪一下白。失败照常往外抛，由调用方决定怎么说。
  Future<ProfileTargets> readProfileTargets(int profileId) async {
    final profile = ref.read(profilesProvider).getProfile(profileId);
    if (profile == null) {
      throw const MessageException('找不到这份配置，可能已被删除');
    }
    final file = await profile.file;
    return _core.readProfileTargets(yaml: await file.readAsString());
  }

  /// 给某个节点挂上（[dialer] 非空）或解除（[dialer] 为空）前置代理。
  ///
  /// 链式代理写的是配置里的 `dialer-proxy` 字段 —— 本内核已经没有 `type: relay`
  /// 这种分组了（见 `core/profile_edit.go` 的说明），所以链只能挂在节点上。
  ///
  /// 指向不存在的名字会让整份配置加载失败，但 `validateConfig` **拦不住**它
  /// （那道校验只做 UnmarshalRawConfig，不解析 dialer 解析），所以成环、重名、
  /// 目标不是节点这些判断全部放在内核的 handleSetProxyChain 里。
  Future<void> setProxyChainOnProfile({
    required int profileId,
    required String target,
    required String dialer,
  }) async {
    return globalState.loadingRun(tag: LoadingTag.profiles, () async {
      final profile = ref.read(profilesProvider).getProfile(profileId);
      if (profile == null) {
        throw const MessageException('找不到这份配置，可能已被删除');
      }
      final file = await profile.file;
      final edited = await _core.setProxyChain(
        yaml: await file.readAsString(),
        target: target,
        dialer: dialer,
      );
      await _saveEditedProfile(profile, edited.yaml);
    }, title: currentAppLocalizations.addProxyChain);
  }

  /// 把订阅配置转为本地配置。
  ///
  /// 做法就是把 url 清空 —— 配置类型与自动更新都由「url 是否为空」推导
  /// （见 ProfileExtension 的 type / realAutoUpdate），所以清空之后这份配置既不会再被
  /// 自动更新，手动点「更新」也不会重新下载覆盖。
  ///
  /// 这是「往订阅配置里加节点」唯一能让改动长期留下来的办法：订阅正文每次更新都是
  /// 整份覆盖，加进去的节点必然丢。代价是原订阅链接不再保存在配置里，所以调用方
  /// 必须先把链接原文给用户看过、并得到明确确认。
  Future<void> convertProfileToLocal(int profileId) async {
    final profile = ref.read(profilesProvider).getProfile(profileId);
    if (profile == null || profile.url.isEmpty) return;
    ref
        .read(profilesProvider.notifier)
        .put(profile.copyWith(url: '', autoUpdate: false));
  }

  /// 把配置切到「自定义覆写」模式，并在自定义分组还是空的时候用当前分组填充一遍。
  ///
  /// 为什么必须先做这一步：自定义策略组存在**覆写数据**里（见
  /// [database.setProfileCustomData]），只有 `overwriteType == custom` 时才生效。
  /// 用户直接切过去会看到一个空列表 —— 而且此刻生效配置里一个分组都没有。上游的做法
  /// 是弹出「检测到配置数据，一键填充」让用户点一下，这里把同一件事替他做掉。
  ///
  /// 只在自定义分组**确实是空**的时候才填充，绝不覆盖用户已经编好的自定义分组。
  Future<void> ensureCustomOverwrite(int profileId) async {
    final profile = ref.read(profilesProvider).getProfile(profileId);
    if (profile == null) return;
    if (profile.overwriteType != OverwriteType.custom) {
      setProfileAndAutoApply(
        profile.copyWith(overwriteType: OverwriteType.custom),
      );
    }
    final count = await ref.read(proxyGroupsCountProvider(profileId).future);
    if (count > 0) return;
    final clashConfig = await ref.read(clashConfigProvider(profileId).future);
    if (clashConfig.proxyGroups.isEmpty && clashConfig.rules.isEmpty) return;
    await database.setProfileCustomData(
      profileId,
      clashConfig.proxyGroups,
      clashConfig.rules,
    );
  }

  /// 读出「按地区生成分组」的计划 —— **只读，不写任何东西**。
  ///
  /// 节点名单取自**这份配置本身**（内核解析 profile 文件得到的），不是运行中的
  /// 内核：用户正在编辑的这一份未必是当前生效的那份（见 [ProfileTargets] 的说明）。
  /// 计划里出现的每个节点名都真实存在于配置里，所以生成出来的分组一定不会
  /// 因为「引用了不存在的节点」而让整份配置加载失败。
  Future<RegionGroupPlan> readRegionGroupPlan(int profileId) async {
    final targets = await readProfileTargets(profileId);
    final groups = await ref.read(proxyGroupsProvider(profileId).future);
    // 实测过落地的节点按真实出口归组 —— 「应用归类」要应用的就是这个真相；
    // 没测过的按名字认。库只存新鲜记录，这里不用再判时间。
    final landing = await ref.read(proxyExitStoreProvider.future);
    return buildRegionGroupPlan(
      nodeNames: targets.proxies.map((target) => target.name),
      existingGroups: [
        for (final group in groups)
          ExistingRegionGroup(
            name: group.name,
            proxyNames: group.proxies ?? const <String>[],
            hasProviderSource: (group.use ?? const <String>[]).isNotEmpty,
          ),
      ],
      // 组名按当前界面语言生成，并带国旗前缀 —— 与「代理」页那些芯片上的写法一致，
      // 用户在两个页面之间认的是同一个名字。
      nameOf: (region) => '${region.emoji} ${region.label}',
      landingByProxy: {
        for (final entry in landing.entries)
          entry.key: entry.value.countryCode,
      },
    );
  }

  /// 落盘 [RegionGroupPlan] 的计划。返回**没能写成**的条数（重名被挡下的）。
  ///
  /// 不套 `loadingRun`：写入走的是 `ProxyGroups` 的乐观更新，界面立刻就能看到结果，
  /// 再盖一层全屏遮罩只会闪一下。与 [ensureCustomOverwrite] 的处理一致。
  ///
  /// 顺序是**先删后写**：删掉的那些组名与要新建的组名理论上不会撞（组名由地区推导），
  /// 但先删干净再写能保证 `put` 不会因为「同名不同 id」被挡下来。
  Future<int> applyRegionGroupPlan(int profileId, RegionGroupPlan plan) async {
    // 拿 id 要重新读一次现有分组：计划是用户点开面板那一刻算的，中间可能已经变过。
    final existing = await ref.read(proxyGroupsProvider(profileId).future);
    final idOfName = <String, int>{
      for (final group in existing) group.name: group.id,
    };
    final notifier = ref.read(proxyGroupsProvider(profileId).notifier);
    for (final name in plan.removals) {
      notifier.del(name);
    }
    var skipped = 0;
    for (final draft in plan.upserts) {
      final group = ProxyGroup(
        // 命中旧组就复用它的 id —— `put` 会顺带把引用它的规则、以及引用它的
        // 分组一起改名，重名冲突也由它挡下。
        id: idOfName[draft.existingName] ?? snowflake.id,
        name: draft.name,
        type: GroupType.Selector,
        proxies: draft.proxyNames,
      );
      if (!notifier.put(group)) {
        skipped++;
        commonPrint.log(
          'region group "${draft.name}" skipped: name already taken',
        );
      }
    }
    return skipped;
  }

  /// 读出「意图分组」的计划 —— **只读，不写任何东西**。与 [readRegionGroupPlan]
  /// 同一哲学：成员名单全部来自这份配置真实存在的节点与分组，组名锚点
  /// （节点选择/自动选择）只在现有分组里真的有才引用。
  Future<IntentGroupPlan> readIntentGroupPlan(
    int profileId,
    Set<IntentKey> enabled,
  ) async {
    final targets = await readProfileTargets(profileId);
    final groups = await ref.read(proxyGroupsProvider(profileId).future);
    return buildIntentGroupPlan(
      enabled: enabled,
      proxyNames: targets.proxies.map((target) => target.name),
      existingGroups: [
        for (final group in groups)
          ExistingRegionGroup(
            name: group.name,
            proxyNames: group.proxies ?? const <String>[],
            hasProviderSource: (group.use ?? const <String>[]).isNotEmpty,
          ),
      ],
      nameOf: (template) => '${template.emoji} ${intentLabelOf(template)}',
    );
  }

  /// 组名按当前界面语言生成 —— 与「按地区生成分组」的组名同一套语言注入。
  String intentLabelOf(IntentTemplate template) {
    final appLocalizations = currentAppLocalizations;
    return switch (template.key) {
      IntentKey.streaming => appLocalizations.intentStreaming,
      IntentKey.ai => appLocalizations.intentAi,
      IntentKey.social => appLocalizations.intentSocial,
    };
  }

  /// 落盘「意图分组」计划：每个意图一个 select 组 + 若干条 GEOSITE 规则。
  ///
  /// 规则必须排在订阅自带规则**之前**（排在 GEOSITE,CN 直连后面就永远轮不到），
  /// `ProfileCustomRules.put` 的 autoOrder 恰好把新规则插到最前 —— 依赖这个
  /// 行为而不是自己拼 order 键。取消勾选的意图会连同它的规则一起删掉。
  Future<int> applyIntentGroupPlan(
    int profileId,
    IntentGroupPlan plan,
  ) async {
    final existing = await ref.read(proxyGroupsProvider(profileId).future);
    final idOfName = <String, int>{
      for (final group in existing) group.name: group.id,
    };
    final groupNotifier = ref.read(proxyGroupsProvider(profileId).notifier);
    final rulesNotifier = ref.read(
      profileCustomRulesProvider(profileId).notifier,
    );
    // 先删：被取消的意图组连同指向它的规则一起收掉。规则按 ruleTarget 反查。
    for (final name in plan.removals) {
      groupNotifier.del(name);
      final deadRules = ref
          .read(profileCustomRulesProvider(profileId))
          .value
          ?.where((rule) => rule.ruleTarget == name)
          .toList();
      rulesNotifier.delAll((deadRules ?? const []).map((rule) => rule.id));
    }
    var skipped = 0;
    for (final draft in plan.upserts) {
      final group = ProxyGroup(
        id: idOfName[draft.name] ?? snowflake.id,
        name: draft.name,
        type: GroupType.Selector,
        proxies: draft.members,
      );
      if (!groupNotifier.put(group)) {
        skipped++;
        commonPrint.log(
          'intent group "${draft.name}" skipped: name already taken',
        );
        continue;
      }
      // 旧规则先清再写：类目名单调整过（比如上一版 AI 只有 openai，新版
      // 又加了别的）时，靠「先删后写」保证不残留指向同一组的旧条目。
      final staleRules = ref
          .read(profileCustomRulesProvider(profileId))
          .value
          ?.where((rule) => rule.ruleTarget == draft.name)
          .toList();
      rulesNotifier.delAll((staleRules ?? const []).map((rule) => rule.id));
      for (final category in draft.categories) {
        rulesNotifier.put(
          Rule(
            ruleAction: RuleAction.GEOSITE,
            content: category,
            ruleTarget: draft.name,
          ),
        );
      }
    }
    return skipped;
  }
}
