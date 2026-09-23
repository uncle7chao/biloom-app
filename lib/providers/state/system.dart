part of '../state.dart';

@riverpod
UpdateParams updateParams(Ref ref) {
  final routeMode = ref.watch(
    networkSettingProvider.select((state) => state.routeMode),
  );
  final authentication = ref.watch(
    networkSettingProvider.select((state) => state.authentication),
  );
  return ref.watch(
    patchClashConfigProvider.select(
      (state) => UpdateParams(
        tun: state.tun.getRealTun(routeMode),
        authentication: authentication.credentials,
        allowLan: state.allowLan,
        findProcessMode: state.findProcessMode,
        mode: state.mode,
        logLevel: state.logLevel,
        ipv6: state.ipv6,
        tcpConcurrent: state.tcpConcurrent,
        externalController: state.externalController,
        unifiedDelay: state.unifiedDelay,
        mixedPort: state.mixedPort,
        geoAutoUpdate: state.geoAutoUpdate,
        geoUpdateInterval: state.geoUpdateInterval,
      ),
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
      (state) =>
          (autoLaunch: state.autoLaunch, showTrayTitle: state.showTrayTitle),
    ),
  );
  final groups = ref.watch(currentGroupsStateProvider).value;
  final selectedMap = ref.watch(selectedMapProvider);

  return TrayState(
    mode: clashConfig.mode,
    port: clashConfig.mixedPort,
    autoLaunch: appSetting.autoLaunch,
    systemProxy: systemProxy,
    tunEnable: clashConfig.tunEnable,
    isStart: isStart,
    groups: groups,
    selectedMap: selectedMap,
    showTrayTitle: appSetting.showTrayTitle,
  );
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
VpnState vpnState(Ref ref) {
  final vpnProps = ref.watch(vpnSettingProvider);
  final stack = ref.watch(
    patchClashConfigProvider.select((state) => state.tun.stack),
  );
  return VpnState(stack: stack, vpnProps: vpnProps);
}

@riverpod
PackageListSelectorState packageListSelectorState(Ref ref) {
  final packages = ref.watch(packagesProvider);
  final accessControlProps = ref.watch(
    vpnSettingProvider.select((state) => state.accessControlProps),
  );
  return PackageListSelectorState(
    packages: packages,
    accessControlProps: accessControlProps,
  );
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
({bool isInit, int checkIpNum, bool containsDetection}) checkIp(Ref ref) {
  final isInit = ref.watch(initProvider);
  final checkIpNum = ref.watch(checkIpNumProvider);
  final containsDetection = ref.watch(
    dashboardStateProvider.select(
      (state) =>
          state.dashboardWidgets.contains(DashboardWidget.networkDetection),
    ),
  );
  return (
    isInit: isInit,
    checkIpNum: checkIpNum,
    containsDetection: containsDetection,
  );
}

@riverpod
bool shouldPatchSystemDns(Ref ref) {
  final autoSetSystemDns = ref.watch(
    networkSettingProvider.select((state) => state.autoSetSystemDns),
  );
  if (!autoSetSystemDns) {
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
        crashlytics: state.crashlytics,
        testUrl: state.testUrl,
      ),
    ),
  );
  final networkSetting = ref.watch(
    networkSettingProvider.select(
      (state) => (
        bypassDomain: state.bypassDomain,
        routeMode: state.routeMode,
        authenticated: state.authentication.credentials.isNotEmpty,
      ),
    ),
  );
  final clashConfig = ref.watch(
    patchClashConfigProvider.select(
      (state) => (
        stack: state.tun.stack.name,
        mixedPort: state.mixedPort,
        routeAddress: state.tun.resolveRouteAddress(networkSetting.routeMode),
      ),
    ),
  );
  final vpnSetting = ref.watch(vpnSettingProvider);
  final currentProfileName = currentProfile.label;
  final selectedMap = currentProfile.selectedMap;
  final onlyStatisticsProxy = appSetting.onlyStatisticsProxy;
  final crashlytics = appSetting.crashlytics;
  final testUrl = appSetting.testUrl;
  final stack = clashConfig.stack;
  final port = clashConfig.mixedPort;
  return SharedState(
    currentProfileName: currentProfileName,
    onlyStatisticsProxy: onlyStatisticsProxy,
    showStopAction: appSetting.showStopAction,
    stopText: currentAppLocalizations.stop,
    crashlytics: crashlytics,
    stopTip: currentAppLocalizations.stopVpn,
    startTip: currentAppLocalizations.startVpn,
    setupParams: SetupParams(selectedMap: selectedMap, testUrl: testUrl),
    vpnOptions: VpnOptions(
      enable: vpnSetting.enable,
      stack: stack,
      // VpnService.setHttpProxy cannot carry credentials, so an authenticated
      // mixed port must not be declared as the system HTTP proxy; traffic
      // still flows through TUN.
      systemProxy: vpnSetting.systemProxy && !networkSetting.authenticated,
      port: port,
      ipv6: vpnSetting.ipv6,
      dnsHijacking: vpnSetting.dnsHijacking,
      accessControlProps: vpnSetting.accessControlProps,
      allowBypass: vpnSetting.allowBypass,
      bypassDomain: networkSetting.bypassDomain,
      routeAddress: clashConfig.routeAddress,
    ),
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
