part of '../action.dart';

enum _SetupTaskResult { completed, handoffToCoreRestart, failed }

typedef _SetupInputs = (
  SetupState,
  PatchClashConfig,
  NetworkProps,
  SetupParams,
);

typedef BuiltProfile = ({
  String yaml,
  String md5,
  ConfigCounts counts,
  SetupBase? base,
});

class _RunRequest {
  final bool running;
  final bool initialize;

  /// Adopts a run the Android service has, config and groups alike.
  final bool resume;
  final DateTime? previousStartTime;

  const _RunRequest({
    required this.running,
    required this.initialize,
    required this.resume,
    required this.previousStartTime,
  });
}

@Riverpod(keepAlive: true)
class SetupAction extends _$SetupAction {
  CoreController get _core => ref.read(coreHandlerProvider);

  Timer? _runtimeTimer;
  final _setupScheduler = SerialTaskScheduler();
  final _listenerScheduler = SerialTaskScheduler();
  _RunRequest? _latestRunRequest;
  DateTime? _startTime;
  _SetupInputs? _appliedInputs;
  var _lastPushDuration = Duration.zero;
  var _pendingForceApply = false;

  bool get _isRunning => _startTime != null && _startTime!.isBeforeNow;

  @override
  void build() {
    ref.onDispose(_stopRuntimeTicker);
    ref.listen(appVisibleProvider, (_, _) => _syncRuntimeTicker());
    ref.listen(
      appSettingProvider.select((state) => state.showTrayTitle),
      (_, _) => _syncRuntimeTicker(),
    );
  }

  bool get _isTrafficShown =>
      ref.read(appVisibleProvider) ||
      (system.isMacOS &&
          !ref.read(safeModeProvider) &&
          ref.read(appSettingProvider).showTrayTitle);

  SetupParams get _setupParams {
    final selectedMap = ref.read(selectedMapProvider);
    final appSetting = ref.read(appSettingProvider);
    return SetupParams(
      selectedMap: selectedMap,
      testUrl: ref.read(patchClashConfigProvider).testUrl,
      skipCertVerify: !appSetting.checkCertificate,
    );
  }

  // The selection reaches the Core through changeProxy, not through an apply.
  SetupParams get _appliedParams =>
      _setupParams.copyWith(selectedMap: const {});

  Future<bool> fullSetup() async {
    if (!ref.read(initProvider)) return true;
    ref.read(proxiesActionProvider.notifier).cancelDelayTests();
    ref.read(delayDataSourceProvider.notifier).value = {};
    final setupResult = applyProfile(force: true);
    ref.read(logsProvider.notifier).value = FixedList(maxLogsLength);
    ref.read(requestsProvider.notifier).value = FixedList(maxRequestsLength);
    ref.read(dnsQueriesProvider.notifier).value = FixedList(
      maxDnsQueriesLength,
    );
    ref.read(dnsQueryCountProvider.notifier).value = 0;
    ref.read(requestCountProvider.notifier).value = 0;
    try {
      return await setupResult;
    } catch (e, s) {
      commonPrint.log('fullSetup ===> ${compactError(e)}, $s');
      return false;
    }
  }

  void _setLocalRunning(bool running) {
    _stopRuntimeTicker();
    if (!running) {
      _startTime = null;
      debouncer.cancel(FunctionTag.applyProfile);
      _pendingForceApply = false;
      _updateRunTime();
      return;
    }

    _startTime ??= DateTime.now();
    _updateRunTime();
    _syncRuntimeTicker();
  }

  void _syncRuntimeTicker() {
    if (_startTime == null || !_isTrafficShown) {
      _stopRuntimeTicker();
      return;
    }
    if (_runtimeTimer != null) {
      return;
    }
    _refreshRunningState();
    _runtimeTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _refreshRunningState(),
    );
  }

  void _stopRuntimeTicker() {
    _runtimeTimer?.cancel();
    _runtimeTimer = null;
  }

  void _refreshRunningState() {
    _updateRunTime();
    unawaited(ref.read(commonActionProvider.notifier).updateTraffic());
  }

  void _updateRunTime() {
    final startTime = _startTime;
    ref.read(runTimeProvider.notifier).value = startTime == null
        ? null
        : DateTime.now().millisecondsSinceEpoch -
              startTime.millisecondsSinceEpoch;
  }

  @protected
  Future<DateTime?> serviceStartTime() async => service?.getRunTime();

  Future<void> initStatus() async {
    if (!globalState.needInitStatus) {
      return;
    }
    commonPrint.log('init status');
    _startTime = await serviceStartTime();
    // 「接管方式还开着」（系统代理 / TUN）同样代表用户希望处在连接状态 ——
    // 那是他上次离开时的选择，打开软件就该恢复。有了这一条，系统代理的默认值
    // 才真正等于「打开即用」，而不是一个亮着却什么也没做的开关。
    final shouldRun =
        _isRunning ||
        ref.read(appSettingProvider).autoRun ||
        ref.read(takeoverOpenProvider);
    if (shouldRun) {
      globalState.lastConfigMd5 = await preferences.getAppliedConfigMd5();
      await setRunning(true, initialize: true);
    } else {
      await globalState.safeRun(() => applyProfile(force: true));
    }
  }

  Future<bool> setRunning(bool running, {bool initialize = false}) {
    if (running && !initialize && !ref.read(initProvider)) {
      return Future.value(true);
    }
    return _run(running, initialize: running && initialize);
  }

  Future<bool> _run(
    bool running, {
    required bool initialize,
    bool resume = false,
  }) {
    final request = _RunRequest(
      running: running,
      initialize: initialize,
      resume: resume,
      previousStartTime: _startTime,
    );
    _latestRunRequest = request;
    _setLocalRunning(running);
    if (request.initialize) {
      globalState.needInitStatus = false;
    }
    return running ? _start(request) : _stop(request);
  }

  /// 内核进程已经退出了 —— 运行态必须在本地就地清掉。
  ///
  /// 这里不能图省事直接调 setRunning(false)：那条路径会走 stopListener()，而内核
  /// 已经死了，IPC 必然失败抛错，_rollbackRunning 反而把状态改回「运行中」。后果是
  /// 首页计时器继续走、托盘仍显示运行中、系统代理一直指着那个没人监听的端口 ——
  /// 用户看到的是「连接正常但所有网页都打不开」，而且点「停止」也停不下来。
  ///
  /// 作废 _latestRunRequest 是必要的：任何还在飞行中的请求都不该再回来改状态。
  void handleCoreCrash() {
    if (_startTime == null) return;
    commonPrint.log(
      'core is gone, clearing the running state',
      logLevel: LogLevel.warning,
    );
    _latestRunRequest = null;
    _setLocalRunning(false);
  }

  Future<bool> _start(_RunRequest request) async {
    if (request.initialize) {
      var applied = false;
      try {
        applied = await applyProfile(
          force: !request.resume,
          preloadInvoke: () => _startCoreRunning(request),
        );
      } catch (e, s) {
        // 调用方只拿到一个 bool，异常在这里被静默吞掉的话，出问题时日志里就只剩
        // 「启动失败」四个字，连是哪一步炸的都查不出来 —— 而这条路径恰恰是用户
        // 「拨了开关却连不上」时唯一能留下的线索。
        commonPrint.log(
          'start failed: ${compactError(e)}, $s',
          logLevel: LogLevel.error,
        );
        applied = false;
      }
      if (!applied && _isCurrent(request)) {
        await globalState.safeRun(() => setRunning(false));
      }
      return applied;
    }

    try {
      await _startCoreRunning(request);
    } catch (_) {
      _rollbackRunning(request);
      rethrow;
    }
    final applied = await inputsApplied();
    if (_isCurrent(request) && !applied) {
      applyProfileDebounce(force: true, silence: true);
    }
    return true;
  }

  Future<void> _startCoreRunning(_RunRequest request) async {
    if (!await _setCoreRunning(request) && _isCurrent(request)) {
      throw _unanswered(CoreMethod.startListener);
    }
  }

  Future<bool> _stop(_RunRequest request) async {
    final bool answered;
    try {
      answered = await _setCoreRunning(request);
    } catch (_) {
      _rollbackRunning(request);
      rethrow;
    }
    if (!_isCurrent(request)) {
      return true;
    }
    resetCoreTraffic();
    ref.read(trafficsProvider.notifier).clear();
    ref.read(totalTrafficProvider.notifier).value = const Traffic();
    // A silent Core is gone or hung; running again would proxy traffic to it.
    if (!answered) {
      throw _unanswered(CoreMethod.stopListener);
    }
    return true;
  }

  Future<bool> _setCoreRunning(_RunRequest request) {
    return _listenerScheduler.run(() async {
      if (!_isCurrent(request)) {
        return true;
      }
      if (request.running && ref.read(suspendProvider)) {
        return true;
      }
      if (ref.read(safeModeProvider)) {
        return true;
      }
      return _setListening(request.running);
    });
  }

  Future<bool> _setListening(bool running) async {
    final vpnOptions = await ref.read(vpnOptionsProvider.future);
    final answered = await setCoreRunning(running);
    ref.read(runningVpnOptionsProvider.notifier).value = running && answered
        ? vpnOptions
        : null;
    return answered;
  }

  CoreMethodException _unanswered(CoreMethod method) => CoreMethodException(
    code: 'no_response',
    message: 'Core did not answer ${method.name}',
  );

  /// An excluded SSID parks the listener without ending the run.
  void syncSuspend() {
    debouncer.call(FunctionTag.suspend, () {
      return _listenerScheduler.run(() async {
        if (!ref.read(isStartProvider) || ref.read(safeModeProvider)) {
          return;
        }
        await _setListening(!ref.read(suspendProvider));
      });
    });
  }

  Future<void> restartVpn() async {
    if (!ref.read(isStartProvider)) {
      return;
    }
    await setRunning(false);
    await setRunning(true);
  }

  void _rollbackRunning(_RunRequest request) {
    if (!_isCurrent(request)) {
      return;
    }
    _startTime = request.previousStartTime;
    _setLocalRunning(!request.running);
  }

  bool _isCurrent(_RunRequest request) => identical(_latestRunRequest, request);

  Future<void> updateConfigDebounce() async {
    debouncer.call(FunctionTag.updateConfig, updateConfig);
  }

  @protected
  Future<bool> setCoreRunning(bool running) {
    return running ? _core.startListener() : _core.stopListener();
  }

  @protected
  void resetCoreTraffic() {
    _core.resetTraffic();
  }

  @visibleForTesting
  Future<void> updateConfig() async {
    await globalState.safeRun(() async {
      final patchConfig = ref.read(patchClashConfigProvider);
      final shouldContinueSetup = await requestAdmin(patchConfig.tun.enable);
      if (!shouldContinueSetup) {
        await _restartCoreAfterAuthorization();
        return;
      }
      final networkSetting = ref.read(networkSettingProvider);
      final message = await _core.updateConfig(
        _effectivePatchConfig(patchConfig).toUpdateParams(
          authentication: networkSetting.authentication.credentials,
          skipCertVerify: !ref.read(appSettingProvider).checkCertificate,
        ),
      );
      if (message.isNotEmpty) throw MessageException(message);
    });
  }

  @protected
  Duration get minApplyDebounce => const Duration(seconds: 2);

  /// A push held up by a rule-set download or a Core timeout says little
  /// about the load, yet would hold back every apply after it.
  @protected
  Duration get maxApplyDebounce => const Duration(seconds: 10);

  void applyProfileDebounce({bool silence = false, bool force = false}) {
    _pendingForceApply |= force;
    debouncer.call(
      FunctionTag.applyProfile,
      (silence) {
        final force = _pendingForceApply;
        _pendingForceApply = false;
        applyProfile(silence: silence, force: force);
      },
      args: [silence],
      duration: Duration(
        microseconds: _lastPushDuration.inMicroseconds.clamp(
          minApplyDebounce.inMicroseconds,
          maxApplyDebounce.inMicroseconds,
        ),
      ),
    );
  }

  void changeMode(Mode mode) {
    ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(mode: mode));
    if (mode == Mode.global) {
      ref
          .read(proxiesActionProvider.notifier)
          .updateCurrentGroupName(GroupName.GLOBAL.name);
    }
  }

  /// For leaving an editor: a profile whose inputs match the config the Core
  /// already runs is not rebuilt, which on a large profile takes a while.
  void autoApplyProfile() {
    runAfterFrame(() async {
      if (!await inputsApplied()) {
        await applyProfile();
      }
    });
  }

  void applyIfGlobalRulesUsed() {
    final profile = ref.read(currentProfileProvider);
    if (profile == null ||
        profile.type == ProfileType.custom ||
        profile.extendType != ExtendType.standard) {
      return;
    }
    applyProfileDebounce(silence: true);
  }

  /// Whether the Core runs what the current profile and settings make now.
  Future<bool> inputsApplied() async {
    final applied = _appliedInputs;
    if (applied == null) {
      return false;
    }
    final profileId = ref.read(currentProfileIdProvider);
    final SetupState setupState;
    try {
      setupState = await ref.read(setupStateProvider(profileId).future);
    } catch (_) {
      return false;
    }
    return applied ==
        (
          setupState,
          _effectivePatchConfig(ref.read(patchClashConfigProvider)),
          ref.read(networkSettingProvider),
          _appliedParams,
        );
  }

  // False means building the profile, the config write, or the Core setup
  // step failed; a profile that fails to build is still pushed to the Core
  // as the empty config so it never keeps serving the previous one.
  // authorizeCore failures still throw.
  Future<bool> applyProfile({
    bool silence = false,
    bool force = false,
    Future<void> Function()? preloadInvoke,
  }) async {
    final result = await _runSetup(
      force: force,
      silence: silence,
      preloadInvoke: preloadInvoke,
    );
    return result != _SetupTaskResult.failed;
  }

  Future<_SetupTaskResult> _runSetup({
    bool silence = false,
    bool force = false,
    Future<void> Function()? preloadInvoke,
  }) async {
    final result = await _setupScheduler.run(() {
      return _setupConfig(
        force: force,
        silence: silence,
        preloadInvoke: preloadInvoke,
        onUpdated: () async {
          await ref.read(proxiesActionProvider.notifier).updateGroups();
          await ref.read(providersProvider.notifier).syncProviders();
        },
      );
    });
    if (result != _SetupTaskResult.handoffToCoreRestart) {
      return result;
    }
    // Release the current serial task before restartCore reapplies the profile.
    final restarted = await _restartCoreAfterAuthorization();
    return restarted ? _SetupTaskResult.completed : _SetupTaskResult.failed;
  }

  Future<bool> _restartCoreAfterAuthorization() async {
    try {
      return await ref.read(coreActionProvider.notifier).restartCore();
    } catch (_) {
      ref.read(authorizedTunEnableProvider.notifier).value =
          TunAuthorizationState.none;
      rethrow;
    }
  }

  /// With a base, [BuiltProfile.yaml] is only the overlay the Core applies.
  Future<BuiltProfile> getProfile({
    required SetupState setupState,
    required PatchClashConfig patchConfig,
  }) async {
    final profileId = setupState.profileId;
    if (profileId == null) {
      // 没有生效配置就没有链注入，展示过滤的名单必须清空，
      // 不然换配置后旧名单还挂着，会把新配置里的同名节点藏掉。
      ref.read(chainInjectedNamesProvider.notifier).set((
        dialers: const {},
        chains: const {},
        groupName: '',
      ));
      return (yaml: '', md5: '', counts: configCountsOf(const {}), base: null);
    }
    final defaultUA = globalState.packageInfo.ua;
    final networkSetting = ref.read(
      networkSettingProvider.select(
        (state) => (
          appendSystemDns: state.appendSystemDns,
          bypassPrivateRoute: state.bypassPrivateRoute,
          authentication: state.authentication,
        ),
      ),
    );
    final appendSystemDns = networkSetting.appendSystemDns;
    final isCustom = setupState.profileType == ProfileType.custom;
    final scriptContent =
        !isCustom && setupState.extendType == ExtendType.script
        ? await setupState.script?.content
        : null;
    final hasScript = scriptContent?.isNotEmpty == true;
    final profileBase = !isCustom && !hasScript
        ? await _core.getProfileBase(profileId)
        : null;
    Map<String, dynamic> rawConfig = isCustom
        ? {
            'proxies': appProxiesPayload(
              setupState.appProxies,
              dialers: setupState.proxyDialers,
              groups: setupState.proxyGroups,
            ),
          }
        : profileBase?.base.config ?? await _core.getConfig(profileId);
    final proxyGroups = isCustom ? setupState.proxyGroups : <ProxyGroup>[];
    final rules = isCustom ? setupState.rules : <Rule>[];
    if (hasScript) {
      rawConfig = await handleEvaluate(scriptContent!, rawConfig);
    }
    // 链式代理：链不落在 profile 文件里（订阅更新冲不掉、原始配置保持纯净），
    // 组装运行时配置时在这里注入 —— 链节点 + 固定「链式代理」分组（永远显性、
    // 排在「自动选择」后面）。放在脚本覆写之后（脚本产出的节点同样可以做出口），
    // 智能抗检测之前（链节点与快照注入的前置节点同样被补齐指纹）。
    var chainGroupName = '';
    var chainNames = const <String>[];
    // 展示层过滤名单只跟**当前生效**的配置走：预览其他配置也走 getProfile，
    // 但那条路径不能动名单 —— 不然预览完 A 配置的过滤名单会漏进 B 配置
    // （A 的链从 B 的页签里消失，或 B 的链漏进 A），直到下次切换配置才恢复。
    final isActiveProfile = profileId == ref.read(currentProfileIdProvider);
    try {
      // 全局索引模型（2026-09-27 定稿）：链不属于任何配置，全部链在每份配置
      // 的运行时里都尝试装配；「链式代理」分组常驻注入（没有有效链时成员是
      // DIRECT 占位），页签在任何配置下都显示。
      final chains = await ProxyChainStore.load();
      final injected = injectProxyChains(
        rawConfig,
        chains: chains,
        // 配置层固定名（不走 l10n，理由见 kProxyChainGroupName 的文档）。
        groupName: kProxyChainGroupName,
        autoGroupName: '自动选择',
        selectorGroupName: kPrimarySelectorGroupName,
        // 自定义覆写模式会整体替换 proxy-groups，rawConfig 里的组活不到
        // 最后 —— 组前置的有效性按覆写列表判，不然 dialer-proxy 悬空。
        finalGroupNames:
            setupState.overwriteType == OverwriteType.custom &&
                proxyGroups.isNotEmpty
            ? {for (final group in proxyGroups) group.name}
            : null,
      );
      chainGroupName = injected.groupName;
      chainNames = injected.chainNames;
      // 展示层过滤名单（2026-09-30 用户拍板）：链节点只在「链式代理」页签
      // 展示，不再落到出口所在的任何其他页签（GLOBAL / 节点选择 / 地区组）。
      // 内核成员数据不动 —— 规则 7 并进「节点选择」的链名照旧，链卡片点击
      // 改道生效选择器，选中照常生效；这份名单只让卡片不在别的页签露面。
      // 快照前置节点（dialers）维持原样：纯技术性存在，从 GLOBAL 摘掉。
      if (isActiveProfile) {
        ref.read(chainInjectedNamesProvider.notifier).set((
          dialers: {...injected.injectedDialerNames},
          chains: {...injected.chainNames},
          groupName: injected.groupName,
        ));
      }
    } catch (_) {
      // 存储读挂了不能拖垮整份配置的组装 —— 没有链式代理，应用照常能跑。
      if (isActiveProfile) {
        ref.read(chainInjectedNamesProvider.notifier).set((
          dialers: const {},
          chains: const {},
          groupName: '',
        ));
      }
    }
    // 自定义覆写模式会在 makeRealProfileTask 里**整体替换** proxy-groups ——
    // 上面注入的组会被顶掉。把链组以 ProxyGroup 形态补进覆写列表末尾
    // （用户自设计的分组里锚点组未必存在，固定追加在最后）。非 custom 模式
    // 不会替换 proxy-groups，rawConfig 里注入的组原样生效。
    // ⛔ 先剔掉覆写列表里的同名组再追加：旧模型残留的「链式代理」组可能被
    // ensureCustomOverwrite 种进覆写数据，直接追加会产出两个同名组，
    // 整份配置加载失败 —— 与 rawConfig 注入路径的残留清理语义保持一致。
    if (chainGroupName.isNotEmpty &&
        setupState.overwriteType == OverwriteType.custom &&
        proxyGroups.isNotEmpty) {
      proxyGroups.removeWhere((group) => group.name == chainGroupName);
      proxyGroups.add(
        ProxyGroup(
          id: 0,
          name: chainGroupName,
          type: GroupType.Selector,
          proxies: chainNames.isNotEmpty ? chainNames : const ['DIRECT'],
        ),
      );
      // 链名并入「节点选择」（injectProxyChains 规则 7 的覆写侧补齐）：
      // rawConfig 里追加的那份会被整体替换顶掉，对覆写列表里的同名组再来一次。
      // 覆写设计里没有「节点选择」组时跳过 —— 链仍可从「链式代理」页签与
      // GLOBAL 选择，不写坏任何东西。
      if (chainNames.isNotEmpty) {
        for (var i = 0; i < proxyGroups.length; i++) {
          final group = proxyGroups[i];
          if (group.name != kPrimarySelectorGroupName ||
              group.type != GroupType.Selector) {
            continue;
          }
          final members = [...?group.proxies];
          var changed = false;
          for (final name in chainNames) {
            if (!members.contains(name)) {
              members.add(name);
              changed = true;
            }
          }
          if (changed) {
            proxyGroups[i] = group.copyWith(proxies: members);
          }
          break;
        }
      }
    }
    // 智能抗检测：给缺省指纹的节点补默认值/轮换覆盖值。放在覆写脚本之后，
    // 脚本产出的节点同样被补齐；只补缺省，显式值不动（原则见 smart_params.dart）。
    if (ref.read(smartAntidetectionStateProvider)) {
      final overrides = await SmartFingerprintStore.load();
      smartFillProxies(rawConfig, overrides: overrides);
    }
    final directory = await appPath.profilesPath;
    final injected = await _resolveInjectedProviders(
      setupState,
      proxyGroups: proxyGroups,
      rules: rules,
    );
    final res = await makeRealProfileTask(
      MakeRealProfileState(
        rules: rules,
        proxyGroups: proxyGroups,
        injectedProxyProviders: injected.proxies,
        injectedRuleProviders: injected.rules,
        profilesPath: directory,
        profileId: profileId,
        rawConfig: rawConfig,
        realPatchConfig: patchConfig,
        overrides: setupState.overrides,
        bypassPrivateRoute: networkSetting.bypassPrivateRoute,
        keepEmptyDnsOverrides: setupState.profileType != ProfileType.custom,
        appendSystemDns: appendSystemDns,
        addedRules: setupState.addedRules,
        defaultUA: defaultUA,
        authentication: networkSetting.authentication.credentials,
        matchTarget:
            profileBase == null ||
                setupState.matchTarget?.trim().isNotEmpty == true
            ? setupState.matchTarget
            : lastMatchTarget(profileBase.base.matchRules),
        safeMode: ref.read(safeModeProvider),
      ),
    );
    if (profileBase == null) {
      return (yaml: res.yaml, md5: res.md5, counts: res.counts, base: null);
    }
    final (:base, :path) = profileBase;
    return (
      yaml: res.yaml,
      md5: '${res.md5}${base.digest}'.toMd5(),
      counts: (
        groups: res.counts.groups + base.proxyGroups,
        proxies: res.counts.proxies + base.proxies,
        rules: res.counts.rules + base.rules,
      ),
      base: SetupBase(path: path, overlay: res.yaml),
    );
  }

  /// Only what the custom profile actually references is injected, so an
  /// app-level provider costs nothing in the profiles that never name it.
  Future<({Map<String, dynamic> proxies, Map<String, dynamic> rules})>
  _resolveInjectedProviders(
    SetupState setupState, {
    required List<ProxyGroup> proxyGroups,
    required List<Rule> rules,
  }) async {
    final usedProxyProviders = <String>{
      for (final proxyGroup in proxyGroups) ...?proxyGroup.use,
    };
    final usedRuleProviders = <String>{
      for (final rule in rules) ...rule.ruleSets,
      if (setupState.profileType == ProfileType.custom)
        ...setupState.overrides.ruleSets,
    };
    if (usedProxyProviders.isEmpty && usedRuleProviders.isEmpty) {
      return (
        proxies: const <String, dynamic>{},
        rules: const <String, dynamic>{},
      );
    }
    final options = setupState.overrides.proxyProviders;
    final proxies = <String, dynamic>{};
    for (final entry in setupState.profileProviders.entries) {
      if (!usedProxyProviders.contains(entry.key)) {
        continue;
      }
      proxies[entry.key] = {
        'type': 'file',
        'path': await appPath.getProfilePath(entry.value.toString()),
        ...?options[entry.key]?.definition,
      };
    }
    final clashProvidersAction = ref.read(
      clashProvidersActionProvider.notifier,
    );
    final ruleProviders = <String, dynamic>{};
    for (final provider in setupState.clashProviders) {
      if (!usedRuleProviders.contains(provider.label)) {
        continue;
      }
      final prepared = await clashProvidersAction.prepare(provider);
      ruleProviders[prepared.label] = prepared.definition(
        await prepared.corePath,
      );
    }
    return (proxies: proxies, rules: ruleProviders);
  }

  Future<String> getProfileWithId(int profileId) async {
    try {
      final setupState = await ref.read(setupStateProvider(profileId).future);
      final patchClashConfig = ref.read(patchClashConfigProvider);
      final res = await getProfile(
        setupState: setupState,
        patchConfig: patchClashConfig,
      );
      return switch (res.base) {
        final base? => await _core.buildProfile(base),
        null => res.yaml,
      };
    } catch (e) {
      dialogs.showNotifier(
        userFacingErrorMessage(e, currentAppLocalizations),
        level: MessageLevel.error,
      );
    }
    return '';
  }

  PatchClashConfig _effectivePatchConfig(PatchClashConfig patchConfig) {
    if (ref.read(safeModeProvider)) {
      return patchConfig.copyWith(
        tun: patchConfig.tun.copyWith(enable: false),
        externalController: ExternalControllerStatus.close,
      );
    }
    final authorized =
        ref.read(authorizedTunEnableProvider) ==
        TunAuthorizationState.authorized;
    return patchConfig.copyWith(
      tun: patchConfig.tun.copyWith(
        enable: patchConfig.tun.enable && authorized,
      ),
      externalController: patchConfig.secret.isEmpty
          ? ExternalControllerStatus.close
          : patchConfig.externalController,
    );
  }

  @protected
  Future<AuthorizeCode> authorizeCore() {
    return system.authorizeCore();
  }

  @visibleForTesting
  Future<bool> requestAdmin(bool enableTun) async {
    if (!enableTun || ref.read(safeModeProvider)) {
      return true;
    }
    final authorizationState = ref.read(authorizedTunEnableProvider);
    if (authorizationState != TunAuthorizationState.none) {
      return true;
    }

    final authorizationNotifier = ref.read(
      authorizedTunEnableProvider.notifier,
    );
    authorizationNotifier.value = TunAuthorizationState.unauthorized;

    final code = await authorizeCore();

    switch (code) {
      case AuthorizeCode.success:
        authorizationNotifier.value = TunAuthorizationState.authorized;
        return false;
      case AuthorizeCode.none:
        authorizationNotifier.value = TunAuthorizationState.authorized;
        return true;
      case AuthorizeCode.error:
        authorizationNotifier.value = TunAuthorizationState.none;
        ref
            .read(patchClashConfigProvider.notifier)
            .update((state) => state.copyWith.tun(enable: false));
        dialogs.showNotifier(
          currentAppLocalizations.tunAuthorizationFailed,
          level: MessageLevel.error,
        );
        return true;
    }
  }

  /// An empty profile list is left alone: it is the first-run state, and it is
  /// what the profile stream holds before its first emission.
  @visibleForTesting
  Profile? recoverMissingProfile() {
    final profileId = ref.read(currentProfileIdProvider);
    if (profileId == null) return null;
    final profiles = ref.read(profilesProvider);
    if (profiles.isEmpty) return null;
    final fallback = profiles.first;
    commonPrint.log(
      'profile $profileId is missing, falling back to ${fallback.id}',
      logLevel: LogLevel.warning,
    );
    ref.read(currentProfileIdProvider.notifier).value = fallback.id;
    return fallback;
  }

  Future<_SetupTaskResult> _setupConfig({
    bool force = false,
    bool silence = false,
    Future<void> Function()? preloadInvoke,
    FutureOr Function()? onUpdated,
  }) async {
    var profile = ref.read(currentProfileProvider) ?? recoverMissingProfile();
    // A refresh failure is surfaced by safeRun; setup keeps the old profile.
    final nextProfile = await globalState.safeRun(
      () => profile?.checkAndUpdateAndCopy(
        validate: (path, key) => _core.validateProfile(path, key),
        convert: ref.read(profilesActionProvider.notifier).convertSubscription,
      ),
    );
    if (nextProfile != null) {
      profile = nextProfile;
      ref.read(profilesProvider.notifier).put(nextProfile);
    }
    commonPrint.log('setup ===> ${profile?.realLabel}');
    final patchConfig = ref.read(patchClashConfigProvider);
    final shouldContinueSetup = await requestAdmin(patchConfig.tun.enable);
    if (!shouldContinueSetup) {
      return _SetupTaskResult.handoffToCoreRestart;
    }
    final pushWatch = Stopwatch()..start();
    final realPatchConfig = _effectivePatchConfig(patchConfig);
    final networkSetting = ref.read(networkSettingProvider);
    SetupState? setupState;
    final realProfile = await globalState.safeRun(() async {
      final state = await ref.read(setupStateProvider(profile?.id).future);
      setupState = state;
      return getProfile(setupState: state, patchConfig: realPatchConfig);
    }, title: 'build profile');
    final profileFailed = realProfile == null;
    final setupParams = _setupParams.copyWith(base: realProfile?.base);
    final inputs = switch (setupState) {
      final state? when !profileFailed => (
        state,
        realPatchConfig,
        networkSetting,
        _appliedParams,
      ),
      _ => null,
    };
    final yamlString = realProfile?.yaml ?? '';
    final yamlMd5 = realProfile?.md5 ?? '';
    if (!profileFailed && yamlMd5 == globalState.lastConfigMd5 && !force) {
      _appliedInputs = inputs;
      globalState.lastConfigCounts = realProfile.counts;
      await preloadInvoke?.call();
      return _SetupTaskResult.completed;
    }
    // Go answers a config it rejects by running its built-in default, which
    // has no proxies, so until this push succeeds no applied config is known.
    _appliedInputs = null;
    globalState.lastConfigMd5 = null;
    globalState.lastConfigCounts = null;
    if (system.isAndroid) {
      await ref.read(vpnOptionsProvider.future);
      await preferences.saveShareState(ref.read(sharedStateProvider));
      await preferences.saveAppliedConfigMd5(null);
    }
    // Recaptured so _start's catch can roll back after safeRun swallows it.
    (Object, StackTrace)? handoffFailure;
    var setupFailed = false;
    await globalState.loadingRun(
      () async {
        try {
          if (setupParams.base == null) {
            final configFilePath = await appPath.configFilePath;
            await File(configFilePath).writeAsStringAtomically(yamlString);
          }
          final profileId = profile?.id;
          if (profileId != null) {
            await appPath.ensureProviderDirs(profileId);
          }
          final message = await _core.setupConfig(
            params: setupParams,
            preloadInvoke: preloadInvoke,
          );
          if (message.isNotEmpty) {
            globalState.lastConfigCounts = configCountsOf(const {});
            await globalState.safeRun(() => onUpdated?.call());
            throw MessageException(message);
          }
        } catch (e, s) {
          setupFailed = true;
          if (preloadInvoke != null) {
            handoffFailure = (e, s);
          }
          rethrow;
        }
        globalState.lastConfigMd5 = yamlMd5;
        globalState.lastConfigCounts =
            realProfile?.counts ?? configCountsOf(const {});
        _appliedInputs = inputs;
        if (system.isAndroid) {
          await preferences.saveAppliedConfigMd5(yamlMd5);
        }
        await onUpdated?.call();
      },
      silence: true,
      tag: !silence ? LoadingTag.proxies : null,
    );
    _lastPushDuration = pushWatch.elapsed;
    if (handoffFailure != null) {
      Error.throwWithStackTrace(handoffFailure!.$1, handoffFailure!.$2);
    }
    if (setupFailed || profileFailed) {
      return _SetupTaskResult.failed;
    }
    return _SetupTaskResult.completed;
  }
}
