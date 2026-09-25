import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:tray/tray.dart';

import 'app_localizations.dart';
import 'l10n_labels.dart';
import 'app_ports.dart';
import 'constant.dart';
import 'provider_reader.dart';
import 'system.dart';
import 'window.dart';

class AppTray implements TrayPort {
  static AppTray? _instance;

  final bool isMacOS;
  final bool isWindows;

  bool _isShutDown = false;

  AppTray._internal({required this.isMacOS, required this.isWindows});

  factory AppTray() {
    _instance ??= AppTray._internal(
      isMacOS: system.isMacOS,
      isWindows: system.isWindows,
    );
    return _instance!;
  }

  @visibleForTesting
  factory AppTray.forPlatform({
    required bool isMacOS,
    required bool isWindows,
  }) {
    return AppTray._internal(isMacOS: isMacOS, isWindows: isWindows);
  }

  String get _trayIconSuffix {
    return isWindows ? 'ico' : 'png';
  }

  String get _trayIconDir {
    return isWindows ? 'assets/images/tray/windows' : 'assets/images/tray/unix';
  }

  String getTrayIcon({required bool isStart, required bool tunEnable}) {
    final status = switch ((isMacOS || !isStart, tunEnable)) {
      (true, _) => 1,
      (false, false) => 2,
      (false, true) => 3,
    };
    return '$_trayIconDir/status_$status.$_trayIconSuffix';
  }

  @override
  Future<void> shutdown() async {
    _isShutDown = true;
    await Tray.instance.hide();
  }

  @override
  Future<void> update({
    required TrayState trayState,
    required Traffic traffic,
    required ProviderReader read,
  }) async {
    if (_isShutDown) {
      return;
    }
    await Tray.instance.show(
      TraySpec(
        icon: TrayIcon.asset(
          getTrayIcon(
            isStart: trayState.isStart,
            tunEnable: trayState.tunEnable,
          ),
          isTemplate: isMacOS,
        ),
        toolTip: appName,
        menu: _buildMenu(trayState: trayState, read: read),
      ),
    );
    await updateTitle(showTrayTitle: trayState.showTrayTitle, traffic: traffic);
  }

  Future<void> updateTitle({
    required bool showTrayTitle,
    required Traffic traffic,
  }) async {
    if (_isShutDown || !isMacOS) {
      return;
    }
    await Tray.instance.setTitle(showTrayTitle ? traffic.trayTitle : '');
  }

  List<TrayMenuItem> _buildMenu({
    required TrayState trayState,
    required ProviderReader read,
  }) {
    final commonAction = read(commonActionProvider.notifier);
    final systemAction = read(systemActionProvider.notifier);
    final setupAction = read(setupActionProvider.notifier);
    final appLocalizations = currentAppLocalizations;

    return [
      TrayMenuAction(
        label: appLocalizations.show,
        onSelected: () {
          window?.show();
        },
      ),
      TrayMenuCheckbox(
        label: trayState.isStart
            ? appLocalizations.stop
            : appLocalizations.start,
        checked: false,
        onSelected: commonAction.toggleRunning,
      ),
      if (isMacOS)
        TrayMenuCheckbox(
          label: appLocalizations.speedStatistics,
          checked: trayState.showTrayTitle,
          onSelected: commonAction.updateSpeedStatistics,
        ),
      const TrayMenuSeparator(),
      for (final mode in Mode.values)
        TrayMenuCheckbox(
          label: mode.label,
          checked: mode == trayState.mode,
          onSelected: () {
            setupAction.changeMode(mode);
          },
        ),
      const TrayMenuSeparator(),
      // 节点快速切换：Windows 与 macOS 的原生菜单都支持子菜单（windows 端
      // tray_plugin.cpp 的 RebuildMenu 递归建 HMENU）。桌面端放开 —— 托盘
      // 切节点是高频动作，为此开主窗口太重。Linux 端插件没有子菜单实现，
      // 保持关闭。
      if (isMacOS || isWindows)
        ..._buildGroupMenu(trayState: trayState, read: read),
      if (trayState.isStart) ...[
        TrayMenuCheckbox(
          label: appLocalizations.tun,
          checked: trayState.tunEnable,
          onSelected: systemAction.updateTun,
        ),
        TrayMenuCheckbox(
          label: appLocalizations.systemProxy,
          checked: trayState.systemProxy,
          onSelected: systemAction.updateSystemProxy,
        ),
        const TrayMenuSeparator(),
      ],
      TrayMenuCheckbox(
        label: appLocalizations.autoLaunch,
        checked: trayState.autoLaunch,
        onSelected: systemAction.updateAutoLaunch,
      ),
      TrayMenuAction(
        label: appLocalizations.copyEnvVar,
        onSelected: () {
          _copyEnv(trayState.port);
        },
      ),
      const TrayMenuSeparator(),
      TrayMenuAction(
        label: appLocalizations.exit,
        onSelected: () {
          systemAction.handleExit();
        },
      ),
    ];
  }

  /// 一个组在托盘里最多展示的节点数。Win32 菜单塞几百项既卡又找不到 ——
  /// 截断到前 [trayGroupMenuMaxItems] 个（顺序沿用内核排好的：延迟升序或
  /// 名字序），当前选中的节点若不在前段里就钉在末尾，保证勾选状态可见。
  static const trayGroupMenuMaxItems = 60;

  List<TrayMenuItem> _buildGroupMenu({
    required TrayState trayState,
    required ProviderReader read,
  }) {
    if (trayState.groups.isEmpty) {
      return const [];
    }
    return [
      for (final group in trayState.groups)
        TrayMenuSubmenu(
          label: group.name,
          items: _buildGroupProxyItems(group: group, read: read),
        ),
      const TrayMenuSeparator(),
    ];
  }

  List<TrayMenuItem> _buildGroupProxyItems({
    required Group group,
    required ProviderReader read,
  }) {
    final selected = read(selectedProxyNameProvider(group.name));
    var proxies = group.all;
    if (proxies.length > trayGroupMenuMaxItems) {
      final head = proxies.take(trayGroupMenuMaxItems).toList();
      // 选中的不在展示段里就钉在末尾 —— 否则用户看不到当前用的是哪个。
      if (!head.any((proxy) => proxy.name == selected)) {
        final selectedProxy = proxies.where(
          (proxy) => proxy.name == selected,
        );
        if (selectedProxy.isNotEmpty) {
          head[head.length - 1] = selectedProxy.first;
        }
      }
      proxies = head;
    }
    return [
      for (final proxy in proxies)
        TrayMenuCheckbox(
          label: proxy.name,
          checked: selected == proxy.name,
          onSelected: () {
            read(proxiesActionProvider.notifier).changeProxy(
              groupName: group.name,
              proxyName: proxy.name,
            );
          },
        ),
    ];
  }

  Future<void> _copyEnv(int port) async {
    final url = 'http://127.0.0.1:$port';

    final cmdline = isWindows
        ? 'set \$env:all_proxy=$url'
        : 'export all_proxy=$url';

    await Clipboard.setData(ClipboardData(text: cmdline));
  }
}

final appTray = system.isDesktop ? AppTray() : null;
