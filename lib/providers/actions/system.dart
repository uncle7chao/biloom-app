part of '../action.dart';

@Riverpod(keepAlive: true)
class SystemAction extends _$SystemAction {
  CoreController get _core => ref.read(coreHandlerProvider);

  SystemExitCoordinator? _exitCoordinator;

  @override
  void build() {}

  Future<List<Package>> getPackages() async {
    if (ref.read(isMobileViewProvider)) {
      await Future.delayed(commonDuration);
    }
    ref.read(packagesProvider.notifier).value = await app?.getPackages() ?? [];
    return ref.read(packagesProvider);
  }

  Future<bool> isInstalledAppsPermissionGranted() async {
    return await app?.isInstalledAppsPermissionGranted() ?? true;
  }

  Future<bool> requestInstalledAppsPermission() async {
    return await app?.requestInstalledAppsPermission() ?? false;
  }

  Future<void> handleExit([bool needSave = true]) {
    final coordinator = _exitCoordinator ??= SystemExitCoordinator(
      watchdogDuration: exitWatchdogDuration,
      closeWindow: closeWindow,
      closeCore: closeCore,
      exitApplication: exitApplication,
    );
    return coordinator.exit(cleanup: () => cleanupExitResources(needSave));
  }

  @protected
  Duration get exitWatchdogDuration => const Duration(seconds: 3);

  @protected
  Future<void> cleanupExitResources(bool needSave) async {
    final saveOperation = needSave ? _savePreferencesSafely() : null;
    final tray = trayPort;
    if (tray != null) {
      await tray.shutdown().onError<Object>((error, stackTrace) {
        commonPrint.log(
          'Tray shutdown failed: ${compactError(error)}',
          logLevel: LogLevel.error,
        );
      });
    }
    await Future.wait([
      ?saveOperation,
      bootGuard.markClosed(),
      if (systemDnsCoordinator != null) systemDnsCoordinator!.shutdown(),
      if (proxy != null) proxy!.stopProxy(),
    ]);
  }

  Future<void> _savePreferencesSafely() async {
    try {
      await savePreferences();
    } catch (error) {
      commonPrint.log(
        'Preferences save failed: ${compactError(error)}',
        logLevel: LogLevel.error,
      );
    }
  }

  @protected
  Future<void> savePreferences() async {
    final port = windowPort;
    if (port != null) {
      try {
        final current = ref.read(windowSettingProvider);
        final geometry = await port.captureNormalGeometry(current);
        if (geometry != null) {
          ref.read(windowSettingProvider.notifier).value = geometry;
        }
      } catch (error) {
        commonPrint.log(
          'Window geometry capture failed: ${compactError(error)}',
          logLevel: LogLevel.warning,
        );
      }
    }
    await preferences.saveConfig(ref.read(configProvider));
  }

  @protected
  Future<void> closeWindow() async {
    await windowPort?.close();
  }

  @protected
  Future<void> closeCore() async {
    await _core.close();
    commonPrint.log('exit');
  }

  @protected
  Future<void> exitApplication() async {
    await system.exit();
    windowPort?.forceExit();
  }

  Future<void> handleClose([bool exit = true]) async {
    if (ref.read(appSettingProvider).minimizeOnExit || !exit) {
      if (system.isDesktop) {
        await _savePreferencesSafely();
      }
      await system.back();
      await windowPort?.hide();
    } else {
      await handleExit();
    }
  }

  Future<void> updateVisible() async {
    await windowPort?.toggle();
  }

  void updateTun() {
    final next = !ref.read(patchClashConfigProvider).tun.enable;
    ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith.tun(enable: next));
    syncRunningWithTakeover();
  }

  void updateSystemProxy() {
    final next = !ref.read(networkSettingProvider).systemProxy;
    ref
        .read(networkSettingProvider.notifier)
        .update((state) => state.copyWith(systemProxy: next));
    syncRunningWithTakeover();
  }

  /// **单向**切到 TUN 接管（区别于 [updateTun] 的取反）。
  ///
  /// 给「DNS 自检检测到未被接管」提供的修复动作：用户此时已经被明确告知
  /// 「只有 TUN 能拦住系统自己的 DNS 查询」，所以这里要的是「打开」，
  /// 不能是「切换」—— 万一 TUN 本来就是开的，切换会把它关掉，正好干成反事。
  ///
  /// 刻意复用与设置页 TUN 开关**完全相同**的两步（写开关 → 对齐运行态），
  /// 而不是自己只写 `tun.enable`：少了 `syncRunningWithTakeover()` 就会出现
  /// 「TUN 开着但没连上」的自相矛盾状态，而那正是这套机制当初要根治的毛病。
  void switchToTun() {
    ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith.tun(enable: true));
    syncRunningWithTakeover();
  }

  /// 把运行态对齐到「接管方式」（系统代理 / TUN）的开关上。
  ///
  /// 「打开系统代理」和「启动」在用户心里本来就是同一件事 —— 他拨这个开关，
  /// 意思就是「我要开始用代理」。所以这里双向绑定：打开任意一种接管方式就连上，
  /// 两种都关掉就断开，绝不留下「开关亮着却没连接」这种自相矛盾的状态
  /// （那正是本次要根治的：开关一拨，浏览器还是打不开）。
  ///
  /// 只负责对齐、不参与「谁改了开关」—— 首页卡片、设置页、托盘菜单、快捷键
  /// 最后都会落到这里，所以不会出现某个入口忘了联动这种漏网之鱼。
  void syncRunningWithTakeover() {
    // 应用还没起来时一个字都别做。bootstrap 有自己的恢复流程，而且读的就是同一个
    // takeoverOpenProvider（见 SetupAction.initStatus）—— 在那里抢先它会打架：
    // 此刻内核刚 startCore、配置还没 apply，startListener 注定失败，反而把
    // 「上次离开时是连接状态」这件事演成一次报错。
    if (!ref.read(initProvider)) return;
    // 被排除的 SSID 下本来就要求不接管，别和它对着干。
    if (ref.read(suspendProvider)) return;
    final shouldRun = ref.read(takeoverOpenProvider);
    final running = ref.read(runTimeProvider) != null;
    if (shouldRun == running) return;
    // 能走到这里就说明已经启动完成：内核进程在、配置也 apply 过，缺的只是
    // 「接管流量」这一步，所以不必再走一遍完整的 applyProfile（initialize: false）。
    unawaited(() async {
      // 动作在飞期间首页要显示「连接中」而不是「点了没反应」。
      ref.read(connectingBusyProvider.notifier).set(true);
      try {
        await globalState.safeRun(
          () => ref.read(setupActionProvider.notifier).setRunning(shouldRun),
        );
      } finally {
        if (ref.mounted) {
          ref.read(connectingBusyProvider.notifier).set(false);
        }
      }
    }());
  }

  /// 主连接按钮的「连接」语义：先确保有一种接管方式，再把运行态拉起来。
  /// 两种都关着时默认用系统代理 —— 它不要管理员权限，是代价最低的一种。
  void connect() {
    if (!ref.read(takeoverOpenProvider)) {
      ref
          .read(networkSettingProvider.notifier)
          .update((state) => state.copyWith(systemProxy: true));
    }
    syncRunningWithTakeover();
  }

  /// 主连接按钮的「断开」语义：不只停内核，还要把接管方式归零。
  /// 否则开关会停在「打开」的位置、与「未连接」互相矛盾，而且下一次任何一次
  /// 开关变动都会把它重新拉起来 —— 用户会觉得「根本关不掉」。
  void disconnect() {
    ref
        .read(networkSettingProvider.notifier)
        .update((state) => state.copyWith(systemProxy: false));
    ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith.tun(enable: false));
    syncRunningWithTakeover();
  }

  /// 按设备能力把接管方式调到当下最优，并**说清楚选了什么、为什么**。
  ///
  /// Android：VpnService 即 TUN，直接开（系统会自己弹授权）。
  /// 桌面：有管理员/授权能力走 TUN（拦截最彻底），否则退系统代理 ——
  /// 「能用的最好」而不是「理论上的最好」。
  Future<void> applyBestPreset() async {
    final appLocalizations = currentAppLocalizations;
    if (system.isAndroid) {
      ref
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith.tun(enable: true));
      syncRunningWithTakeover();
      await dialogs.showMessage(
        title: appLocalizations.bestPresetTitle,
        message: TextSpan(text: appLocalizations.bestPresetTunApplied),
        cancelable: false,
      );
      return;
    }
    final isAdmin = await system.checkIsAdmin();
    if (isAdmin) {
      ref
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith.tun(enable: true));
      syncRunningWithTakeover();
      await dialogs.showMessage(
        title: appLocalizations.bestPresetTitle,
        message: TextSpan(text: appLocalizations.bestPresetTunApplied),
        cancelable: false,
      );
      return;
    }
    ref
        .read(networkSettingProvider.notifier)
        .update((state) => state.copyWith(systemProxy: true));
    ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith.tun(enable: false));
    syncRunningWithTakeover();
    await dialogs.showMessage(
      title: appLocalizations.bestPresetTitle,
      message: TextSpan(text: appLocalizations.bestPresetSystemProxyApplied),
      cancelable: false,
    );
  }

  void updateAutoLaunch() {
    ref
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(autoLaunch: !state.autoLaunch));
  }

  Future<void> updateTray() async {
    await trayPort?.update(
      trayState: ref.read(trayStateProvider),
      traffic: ref.read(
        trafficsProvider.select(
          (state) => state.list.safeLast(const Traffic()),
        ),
      ),
      read: globalState.container.read,
    );
  }

  Future<void> updateLocalIp() async {
    ref.read(localIpProvider.notifier).value = null;
    await Future.delayed(commonDuration);
    ref.read(localIpProvider.notifier).value = await getLocalIpAddress();
  }
}
