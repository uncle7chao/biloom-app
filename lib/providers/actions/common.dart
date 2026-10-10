part of '../action.dart';

@Riverpod(keepAlive: true)
class CommonAction extends _$CommonAction {
  CoreController get _core => ref.read(coreHandlerProvider);
  bool _isUpdatingTraffic = false;

  @override
  void build() {}

  /// 主连接入口（首页悬浮球、托盘菜单、快捷键）共用这一个方法。
  ///
  /// 「连接」与「断开」操作的是「接管方式」，而不只是内核进程：
  /// 内核起来了却没有接管方式时流量照样直连，那不是用户要的「已连接」；
  /// 断开却把系统代理留在打开的位置，开关会和状态自相矛盾，而且下一次
  /// 任何一次开关变动都会把它重新拉起来，用户会觉得「关不掉」。
  ///
  /// 连接前的两道闸（2026-10-10 用户拍板）：
  /// 1. 没有订阅（无任何可用代理）时「开始连接」不可运行，只弹提示 ——
  ///    裸机点了连接也不会有任何代理生效，那是假动作；
  /// 2. 首次连接时才弹「最佳设置」引导（首启不弹：裸机推荐接管方式没有意义）。
  void toggleRunning() {
    final systemAction = ref.read(systemActionProvider.notifier);
    if (ref.read(isStartProvider)) {
      systemAction.disconnect();
      return;
    }
    if (ref.read(profilesProvider).isEmpty) {
      dialogs.showNotifier(currentAppLocalizations.noProxySet);
      return;
    }
    unawaited(_connectWithFirstRunGuide());
  }

  /// 首次连接时的一次性引导：按设备能力推荐接管方式，用户可选「一键应用」。
  ///
  /// 出现条件只有「从未出现过」（shared_preferences 的一次性标记，不复用
  /// appSetting —— 那个模型加字段要跑代码生成器，为一个布尔值不值）。
  /// 选「一键应用」则 [SystemAction.applyBestPreset] 内部会把运行态拉起来，
  /// 等于这次连接顺势完成；跳过则按原逻辑继续连接。
  /// 无论选什么都标记完成：这不是一个要反复纠缠的推销位。
  Future<void> _connectWithFirstRunGuide() async {
    final prefs = await preferences.sharedPreferencesCompleter.future;
    if (prefs?.getBool('bestPresetGuideDone') != true) {
      await prefs?.setBool('bestPresetGuideDone', true);
      final confirmed = await dialogs.showMessage(
        title: currentAppLocalizations.bestPresetTitle,
        message: TextSpan(text: currentAppLocalizations.bestPresetFirstRunTip),
        confirmText: currentAppLocalizations.bestPresetApply,
      );
      if (confirmed == true) {
        await ref.read(systemActionProvider.notifier).applyBestPreset();
        return;
      }
    }
    ref.read(systemActionProvider.notifier).connect();
  }

  void updateSpeedStatistics() {
    ref
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(showTrayTitle: !state.showTrayTitle));
  }

  /// 热键循环切换出站模式（规则→全局→直连→规则）。
  ///
  /// 刻意走 [SetupAction.changeMode] 而不是直接改 patchClashConfig：切到全局
  /// 模式时要把当前分组切到 GLOBAL，仪表盘/托盘两个入口都有这个副作用，热键
  /// 此前漏了 —— 用热键切全局后，代理页会还停在普通分组上。
  void updateMode() {
    final current = ref.read(patchClashConfigProvider).mode;
    final index = Mode.values.indexWhere((item) => item == current);
    if (index == -1) return;
    final nextIndex = index + 1 > Mode.values.length - 1 ? 0 : index + 1;
    ref
        .read(setupActionProvider.notifier)
        .changeMode(Mode.values[nextIndex]);
  }

  Future<void> updateTraffic() async {
    if (_isUpdatingTraffic) {
      return;
    }
    _isUpdatingTraffic = true;
    try {
      final onlyStatisticsProxy = ref.read(
        appSettingProvider.select((state) => state.onlyStatisticsProxy),
      );
      final [traffic, totalTraffic] = await Future.wait([
        _readTraffic(() => _core.getTraffic(onlyStatisticsProxy)),
        _readTraffic(() => _core.getTotalTraffic(onlyStatisticsProxy)),
      ]);
      if (traffic != null) {
        ref.read(trafficsProvider.notifier).addTraffic(traffic);
      }
      if (totalTraffic != null) {
        ref.read(totalTrafficProvider.notifier).value = totalTraffic;
      }
    } finally {
      _isUpdatingTraffic = false;
    }
  }

  Future<Traffic?> _readTraffic(Future<Traffic> Function() request) async {
    try {
      return await request();
    } catch (error) {
      commonPrint.log(
        'updateTraffic error: $error',
        logLevel: coreFailureLogLevel(error),
      );
      return null;
    }
  }

  Future<bool> autoCheckUpdate() async {
    if (!ref.read(appSettingProvider).autoCheckUpdate) return false;
    final res = await request.checkForUpdate();
    // 自动检查只在**真的有新版本**时出声。启动时既不该因为「已是最新」打扰用户，
    // 更不该因为断网/查不到而弹窗 —— 后者是静默失败，只记日志。
    if (res.status == UpdateCheckStatus.hasUpdate) {
      await checkUpdateResultHandle(result: res);
    }
    return res.status == UpdateCheckStatus.hasUpdate;
  }

  /// 首启一次性引导已移除（2026-10-10 用户拍板）：引导挪到首次连接时弹
  /// （见 [_connectWithFirstRunGuide]）—— 裸机首启推荐接管方式没有意义。

  TextSpan _releaseSpan(BuildContext context, String tagName, String? body) {
    final textTheme = context.textTheme;
    final version = parseReleaseChangelog(body);
    return TextSpan(
      text: '$tagName \n',
      style: textTheme.headlineSmall,
      children: version == null
          ? [
              TextSpan(text: '\n', style: textTheme.bodyMedium),
              for (final submit in parseReleaseBody(body))
                TextSpan(text: '- $submit \n', style: textTheme.bodyMedium),
            ]
          : _changelogSpans(context, version),
    );
  }

  List<TextSpan> _changelogSpans(
    BuildContext context,
    ChangelogVersion version,
  ) {
    final textTheme = context.textTheme;
    return [
      for (final group in version.visibleGroups) ...[
        TextSpan(
          text:
              '\n${changelogGroupTitle(currentAppLocalizations, group.type)}\n',
          style: textTheme.labelLarge?.copyWith(
            color: group.type == ChangelogType.breaking
                ? context.colorScheme.error
                : context.colorScheme.primary,
          ),
        ),
        for (final entry in group.entries)
          TextSpan(text: '• ${entry.text}\n', style: textTheme.bodyMedium),
      ],
    ];
  }

  Future<void> checkUpdateResultHandle({
    required UpdateCheckResult result,
    bool isUser = false,
  }) async {
    // 「查不到」和「已是最新」必须给不同的话。混成一句，用户就会以为自己在用最新版，
    // 而这恰恰是他最需要知道「我没查到」的时候。
    if (result.status == UpdateCheckStatus.failed) {
      if (isUser) {
        unawaited(
          dialogs.showMessage(
            title: currentAppLocalizations.checkUpdate,
            message: TextSpan(text: currentAppLocalizations.checkUpdateFailed),
          ),
        );
      }
      return;
    }
    final data = result.data;
    if (data != null) {
      final context = globalState.navigatorKey.currentContext!;
      final res = await dialogs.showMessage(
        title: currentAppLocalizations.discoverNewVersion,
        message: _releaseSpan(
          context,
          data['tag_name'] as String,
          data['body'] as String?,
        ),
        confirmText: currentAppLocalizations.goDownload,
        cancelText: isUser ? null : currentAppLocalizations.noLongerRemind,
      );
      if (res == true) {
        unawaited(
          launchUrl(
            Uri.parse('https://github.com/$repository/releases/latest'),
          ),
        );
      } else if (!isUser && res == false) {
        ref
            .read(appSettingProvider.notifier)
            .update((state) => state.copyWith(autoCheckUpdate: false));
      }
    } else if (isUser) {
      unawaited(
        dialogs.showMessage(
          title: currentAppLocalizations.checkUpdate,
          message: TextSpan(text: currentAppLocalizations.checkUpdateError),
        ),
      );
    }
  }
}
