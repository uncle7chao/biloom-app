part of '../state.dart';

@riverpod
UpdateParams updateParams(Ref ref) {
  final authentication = ref.watch(
    networkSettingProvider.select((state) => state.authentication),
  );
  final checkCertificate = ref.watch(
    appSettingProvider.select((state) => state.checkCertificate),
  );
  return ref.watch(
    patchClashConfigProvider.select(
      (state) => state.toUpdateParams(
        authentication: authentication.credentials,
        skipCertVerify: !checkCertificate,
      ),
    ),
  );
}

@riverpod
({PatchClashConfig patchConfig, bool appendSystemDns, bool bypassPrivateRoute})
setupPatch(Ref ref) {
  return (
    patchConfig: ref.watch(
      patchClashConfigProvider.select((state) => state.setupOnly),
    ),
    appendSystemDns: ref.watch(
      networkSettingProvider.select((state) => state.appendSystemDns),
    ),
    // Android's VPN service takes it on its next start instead.
    bypassPrivateRoute:
        system.isDesktop &&
        ref.watch(
          networkSettingProvider.select((state) => state.bypassPrivateRoute),
        ),
  );
}

@riverpod
TrayState trayState(Ref ref) {
  // 与 proxyState 共用同一套门控。被排除的 SSID 下内核确实已经停止接管流量，
  // 托盘却显示「运行中」、菜单还给出「停止」—— 首页、托盘、真实状态三处互相打脸。
  final isStart = ref.watch(
    proxyStateProvider.select((state) => state.isStart),
  );
  final systemProxy = ref.watch(
    networkSettingProvider.select((state) => state.systemProxy),
  );
  final clashConfig = ref.watch(
    patchClashConfigProvider.select(
      (state) => (
        mode: state.mode,
        mixedPort: state.mixedPort,
        tunEnable: state.tun.enable,
      ),
    ),
  );
  final appSetting = ref.watch(
    appSettingProvider.select(
      (state) => (
        autoLaunch: state.autoLaunch,
        showTrayTitle: state.showTrayTitle,
        monochromeTrayIcon: state.monochromeTrayIcon,
      ),
    ),
  );
  final groups = ref.watch(currentGroupsStateProvider).value;
  final selectedMap = ref.watch(selectedMapProvider);
  final safeMode = ref.watch(safeModeProvider);
  final suspended = ref.watch(suspendProvider);
  final hotKeys = _trayHotKeys(ref);

  return TrayState(
    mode: clashConfig.mode,
    port: clashConfig.mixedPort,
    autoLaunch: appSetting.autoLaunch,
    systemProxy: systemProxy,
    tunEnable: clashConfig.tunEnable,
    isStart: isStart,
    suspended: isStart && suspended,
    groups: groups,
    selectedMap: selectedMap,
    showTrayTitle: appSetting.showTrayTitle,
    monochromeTrayIcon: appSetting.monochromeTrayIcon,
    safeMode: safeMode,
    hotKeys: hotKeys,
  );
}

Map<HotAction, HotKeyAction> _trayHotKeys(Ref ref) {
  final failures = ref.watch(hotKeyFailuresProvider);
  return {
    for (final hotKeyAction in ref.watch(hotKeyActionsProvider))
      if (isValidHotKey(hotKeyAction.modifiers, hotKeyAction.key) &&
          !failures.containsKey(hotKeyAction.action))
        hotKeyAction.action: hotKeyAction,
  };
}

/// Measured delays of the proxies the tray lists, by group and then proxy
/// name. Resolved like a proxy card, so a nested group shows its selection.
@riverpod
Map<String, Map<String, int>> trayDelays(Ref ref) {
  final delayMap = ref.watch(delayDataSourceProvider);
  if (delayMap.isEmpty) {
    return const {};
  }
  final groups = ref.watch(currentGroupsStateProvider).value;
  final allGroups = ref.watch(groupsProvider);
  final selectedMap = ref.watch(selectedMapProvider);
  final defaultTestUrl = ref.watch(
    patchClashConfigProvider.select((state) => state.testUrl),
  );
  final delays = <String, Map<String, int>>{};
  for (final group in groups) {
    final testUrl = group.testUrl.takeFirstValid([defaultTestUrl]);
    final groupDelays = <String, int>{};
    for (final proxy in group.all) {
      final delay = computeProxyDelayState(
        proxyName: proxy.name,
        testUrl: testUrl,
        groups: allGroups,
        selectedMap: selectedMap,
        delayMap: delayMap,
      ).delay;
      if (delay != 0) {
        groupDelays[proxy.name] = delay;
      }
    }
    if (groupDelays.isNotEmpty) {
      delays[group.name] = groupDelays;
    }
  }
  return delays;
}

@riverpod
TrayTitleState trayTitleState(Ref ref) {
  final showTrayTitle = ref.watch(
    appSettingProvider.select((state) => state.showTrayTitle),
  );
  final traffic = ref.watch(
    trafficsProvider.select((state) => state.list.safeLast(const Traffic())),
  );
  return TrayTitleState(showTrayTitle: showTrayTitle, traffic: traffic);
}

@riverpod
HotKeyAction getHotKeyAction(Ref ref, HotAction hotAction) {
  return ref.watch(
    hotKeyActionsProvider.select((state) {
      final index = state.indexWhere((item) => item.action == hotAction);
      return index != -1 ? state[index] : HotKeyAction(action: hotAction);
    }),
  );
}

@riverpod
bool shouldPatchSystemDns(Ref ref) {
  final autoSetSystemDns = ref.watch(
    networkSettingProvider.select((state) => state.autoSetSystemDns),
  );
  if (!autoSetSystemDns || ref.watch(safeModeProvider)) {
    return false;
  }
  final isStart = ref.watch(runTimeProvider.select((state) => state != null));
  final tunEnable = ref.watch(
    patchClashConfigProvider.select((state) => state.tun.enable),
  );
  final authorizationState = ref.watch(authorizedTunEnableProvider);
  return isStart &&
      tunEnable &&
      authorizationState == TunAuthorizationState.authorized;
}

@riverpod
SharedState sharedState(Ref ref) {
  ref.watch(loadedLocaleProvider);
  final currentProfile = ref.watch(
    currentProfileProvider.select(
      (state) => CurrentProfileSelectorState(
        label: state?.label ?? '',
        selectedMap: state?.selectedMap ?? {},
      ),
    ),
  );
  final appSetting = ref.watch(
    appSettingProvider.select(
      (state) => (
        onlyStatisticsProxy: state.onlyStatisticsProxy,
        showStopAction: state.showNotificationStopAction,
        checkCertificate: state.checkCertificate,
      ),
    ),
  );
  final currentProfileName = currentProfile.label;
  final selectedMap = currentProfile.selectedMap;
  final onlyStatisticsProxy = appSetting.onlyStatisticsProxy;
  final testUrl = ref.watch(
    patchClashConfigProvider.select((state) => state.testUrl),
  );
  return SharedState(
    currentProfileName: currentProfileName,
    onlyStatisticsProxy: onlyStatisticsProxy,
    showStopAction: appSetting.showStopAction,
    stopText: currentAppLocalizations.stop,
    stopTip: currentAppLocalizations.stopVpn,
    startTip: currentAppLocalizations.startVpn,
    localNetworkTip: currentAppLocalizations.localNetworkDeniedTip,
    setupParams: SetupParams(
      selectedMap: selectedMap,
      testUrl: testUrl,
      skipCertVerify: !appSetting.checkCertificate,
    ),
    vpnOptions: ref.watch(vpnOptionsProvider).value,
  );
}

@Riverpod(keepAlive: true)
Future<List<String>> vpnRouteAddress(Ref ref) {
  final routes = ref.watch(
    patchClashConfigProvider.select(
      (state) => Tun(
        routeAddress: state.tun.routeAddress,
        routeExcludeAddress: state.tun.routeExcludeAddress,
      ),
    ),
  );
  final bypassPrivateRoute = ref.watch(
    networkSettingProvider.select((state) => state.bypassPrivateRoute),
  );
  return routes.vpnRouteAddress(bypassPrivateRoute: bypassPrivateRoute);
}

@Riverpod(keepAlive: true)
Future<VpnOptions> vpnOptions(Ref ref) async {
  final networkSetting = ref.watch(
    networkSettingProvider.select(
      (state) => (
        bypassDomain: state.bypassDomain,
        authenticated: state.authentication.credentials.isNotEmpty,
      ),
    ),
  );
  final clashConfig = ref.watch(
    patchClashConfigProvider.select(
      (state) => (tun: state.tun, mixedPort: state.mixedPort),
    ),
  );
  final vpnSetting = ref.watch(vpnSettingProvider);
  final safeMode = ref.watch(safeModeProvider);
  final routeAddress = ref.watch(vpnRouteAddressProvider.future);
  final tun = clashConfig.tun;
  return VpnOptions(
    enable: vpnSetting.enable && !safeMode,
    stack: tun.stack.name,
    // VpnService.setHttpProxy cannot carry credentials, so an authenticated
    // mixed port is left to TUN instead of declared as the system proxy.
    systemProxy:
        vpnSetting.systemProxy && !networkSetting.authenticated && !safeMode,
    port: clashConfig.mixedPort,
    ipv6: vpnSetting.ipv6,
    dnsHijacking: vpnSetting.dnsHijacking,
    accessControlProps: vpnSetting.accessControlProps,
    allowBypass: vpnSetting.allowBypass,
    bypassDomain: networkSetting.bypassDomain,
    routeAddress: await routeAddress,
    mtu: tun.mtu,
    congestionController: tun.congestionController,
  );
}

@riverpod
class AccessControlState extends _$AccessControlState
    with AutoDisposeNotifierMixin {
  @override
  AccessControlProps build() => const AccessControlProps();
}

@riverpod
bool suspend(Ref ref) {
  final currentSSID = ref.watch(currentSSIDProvider);
  final excludeSSIDs = ref.watch(excludeSSIDsProvider);
  return excludeSSIDs.contains(currentSSID);
}

/// 「接管方式」是系统代理与 TUN 的统称，也是用户表达连接意图的地方：
/// 打开任意一个就是说「我开始用代理」，两个都关就是说「我不需要代理了」。
///
/// 运行态由它派生（见 SystemAction.syncRunningWithTakeover），于是不存在
/// 「开关开着却没连接」这种自相矛盾的状态 —— 那正是这次要根治的问题。
@riverpod
bool takeoverOpen(Ref ref) {
  final systemProxy = ref.watch(
    networkSettingProvider.select((state) => state.systemProxy),
  );
  final tunEnable = ref.watch(
    patchClashConfigProvider.select((state) => state.tun.enable),
  );
  return systemProxy || tunEnable;
}

/// 首页的三态：未连接 / 连接中 / 已连接。
///
/// 「连接中」不是从内核读来的 —— 内核只有「起来了 / 没起来」两个相。
/// 这一相来自 [connectingBusyProvider]：连接动作从点下到内核回报运行态之间
/// 有几百毫秒到数秒不等的空窗（写配置、起进程、apply profile），这个空窗
/// 什么都不标的话，用户看到的就是「点了没反应」，然后再「突然连上」。
enum ConnectionPhase { disconnected, connecting, connected }

/// 一次连接/断开动作正在进行中。动作完没完成由动作方（SystemAction）标记。
class ConnectingBusy extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) {
    if (state != value) {
      state = value;
    }
  }
}

final connectingBusyProvider = NotifierProvider<ConnectingBusy, bool>(
  ConnectingBusy.new,
);

/// 三态只读视图：运行中 → 已连接；没运行但动作在飞 → 连接中；否则未连接。
///
/// 断开动作进行中仍显示「已连接」—— 内核确实还在跑，此时标「连接中」
/// 反而让用户误会成「正在连」。等内核真正停下，这一相自己会落到「未连接」。
final connectionPhaseProvider = Provider<ConnectionPhase>((ref) {
  final running = ref.watch(runTimeProvider) != null;
  if (running) {
    return ConnectionPhase.connected;
  }
  if (ref.watch(connectingBusyProvider)) {
    return ConnectionPhase.connecting;
  }
  return ConnectionPhase.disconnected;
});
