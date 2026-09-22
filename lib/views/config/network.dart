import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef _VpnUpdate<T> = VpnProps Function(VpnProps state, T value);

typedef _NetworkUpdate<T> = NetworkProps Function(NetworkProps state, T value);

typedef _TunUpdate<T> =
    PatchClashConfig Function(PatchClashConfig state, T value);

ConfigWriter<T> _vpnWriter<T>(_VpnUpdate<T> update) {
  return (ref, value) => ref
      .read(vpnSettingProvider.notifier)
      .update((state) => update(state, value));
}

ConfigWriter<T> _networkWriter<T>(_NetworkUpdate<T> update) {
  return (ref, value) => ref
      .read(networkSettingProvider.notifier)
      .update((state) => update(state, value));
}

ConfigWriter<T> _tunWriter<T>(_TunUpdate<T> update) {
  return (ref, value) => ref
      .read(patchClashConfigProvider.notifier)
      .update((state) => update(state, value));
}

/// 「接管方式」开关（系统代理 / TUN）共用同一个语义：打开它就等于「我要开始用代理」。
///
/// 所以写入之后统一把运行态对齐到用户意图（细节见 SystemAction.ensureRunning）。
/// 包在 writer 层、而不是逐个改 onChanged，是因为这两个开关入口很多 —— 首页卡片、
/// 设置页、托盘菜单、快捷键 —— 逐个改迟早会漏掉一个，而漏掉的那一个就是 Bug。
ConfigWriter<bool> _takeoverWriter(ConfigWriter<bool> write) {
  return (ref, value) {
    write(ref, value);
    // 与首页卡片、托盘菜单走的是同一条对齐逻辑：开关动完，运行态跟着动。
    ref.read(systemActionProvider.notifier).syncRunningWithTakeover();
  };
}

ConfigToggleItem _vpnToggle({
  required ConfigLabel title,
  required bool Function(VpnProps state) select,
  required _VpnUpdate<bool> update,
  ConfigLabel? subtitle,
}) {
  return ConfigToggleItem(
    title: title,
    subtitle: subtitle,
    selector: vpnSettingProvider.select(select),
    onChanged: _vpnWriter(update),
  );
}

ConfigToggleItem _networkToggle({
  required ConfigLabel title,
  required bool Function(NetworkProps state) select,
  required _NetworkUpdate<bool> update,
  ConfigLabel? subtitle,
  bool takeover = false,
}) {
  final writer = _networkWriter(update);
  return ConfigToggleItem(
    title: title,
    subtitle: subtitle,
    selector: networkSettingProvider.select(select),
    onChanged: takeover ? _takeoverWriter(writer) : writer,
  );
}

class VPNItem extends ConsumerWidget {
  const VPNItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    return _vpnToggle(
      title: (l) => 'VPN',
      subtitle: (l) => l.vpnEnableDesc,
      select: (state) => state.enable,
      update: (state, value) => state.copyWith(enable: value),
    );
  }
}

class TUNItem extends ConsumerWidget {
  const TUNItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    return ConfigToggleItem(
      title: (l) => l.tun,
      subtitle: (l) => l.tunDesc,
      selector: patchClashConfigProvider.select((state) => state.tun.enable),
      onChanged: _takeoverWriter(
        _tunWriter<bool>((state, value) => state.copyWith.tun(enable: value)),
      ),
    );
  }
}

class AllowBypassItem extends ConsumerWidget {
  const AllowBypassItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    return _vpnToggle(
      title: (l) => l.allowBypass,
      subtitle: (l) => l.allowBypassDesc,
      select: (state) => state.allowBypass,
      update: (state, value) => state.copyWith(allowBypass: value),
    );
  }
}

class VpnSystemProxyItem extends ConsumerWidget {
  const VpnSystemProxyItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final authenticationEnable = ref.watch(
      networkSettingProvider.select((state) => state.authentication.enable),
    );
    return _vpnToggle(
      title: (l) => l.systemProxy,
      subtitle: (l) => authenticationEnable
          ? l.authenticationSystemProxyDesc
          : l.systemProxyDesc,
      select: (state) => state.systemProxy,
      update: (state, value) => state.copyWith(systemProxy: value),
    );
  }
}

class SystemProxyItem extends ConsumerWidget {
  const SystemProxyItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    return _networkToggle(
      title: (l) => l.systemProxy,
      subtitle: (l) => l.systemProxyDesc,
      select: (state) => state.systemProxy,
      update: (state, value) => state.copyWith(systemProxy: value),
    );
  }
}

class Ipv6Item extends ConsumerWidget {
  const Ipv6Item({super.key});

  @override
  Widget build(BuildContext context, ref) {
    return _vpnToggle(
      title: (l) => 'IPv6',
      subtitle: (l) => l.ipv6InboundDesc,
      select: (state) => state.ipv6,
      update: (state, value) => state.copyWith(ipv6: value),
    );
  }
}

class AutoSetSystemDnsItem extends ConsumerWidget {
  const AutoSetSystemDnsItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    return _networkToggle(
      title: (l) => l.autoSetSystemDns,
      select: (state) => state.autoSetSystemDns,
      update: (state, value) => state.copyWith(autoSetSystemDns: value),
    );
  }
}

class DNSHijackingItem extends ConsumerWidget {
  const DNSHijackingItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    return _vpnToggle(
      title: (l) => l.dnsHijacking,
      select: (state) => state.dnsHijacking,
      update: (state, value) => state.copyWith(dnsHijacking: value),
    );
  }
}

class TunStackItem extends ConsumerWidget {
  const TunStackItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    return ConfigOptionsItem<TunStack>(
      title: (l) => l.stackMode,
      options: TunStack.values,
      textBuilder: (stack) => stack.name,
      selector: patchClashConfigProvider.select((state) => state.tun.stack),
      onChanged: _tunWriter((state, value) => state.copyWith.tun(stack: value)),
    );
  }
}

class InterfaceNameModeItem extends ConsumerWidget {
  const InterfaceNameModeItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final appLocalizations = context.appLocalizations;
    return ConfigOptionsItem<InterfaceNameMode>(
      title: (l) => l.interfaceNameMode,
      options: InterfaceNameMode.values,
      textBuilder: (mode) => switch (mode) {
        InterfaceNameMode.clear => appLocalizations.interfaceNameModeClear,
        InterfaceNameMode.follow => appLocalizations.interfaceNameModeFollow,
        InterfaceNameMode.custom => appLocalizations.interfaceNameModeCustom,
      },
      selector: patchClashConfigProvider.select(
        (state) => state.interfaceNameMode,
      ),
      onChanged: _tunWriter(
        (state, value) => state.copyWith(interfaceNameMode: value),
      ),
    );
  }
}

class InterfaceNameItem extends ConsumerWidget {
  const InterfaceNameItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final isCustom = ref.watch(
      patchClashConfigProvider.select(
        (state) => state.interfaceNameMode == InterfaceNameMode.custom,
      ),
    );
    if (!isCustom) {
      return Container();
    }
    return ConfigTextItem(
      title: (l) => l.interfaceName,
      subtitle: (l) => l.interfaceNameDesc,
      maxLength: TextInputLimits.name,
      selector: patchClashConfigProvider.select((state) => state.interfaceName),
      onChanged: _tunWriter(
        (state, value) => state.copyWith(interfaceName: value.trim()),
      ),
    );
  }
}

class RouteModeItem extends ConsumerWidget {
  const RouteModeItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    return ConfigOptionsItem<RouteMode>(
      title: (l) => l.routeMode,
      options: RouteMode.values,
      textBuilder: (mode) => mode.label,
      selector: networkSettingProvider.select((state) => state.routeMode),
      onChanged: _networkWriter(
        (state, value) => state.copyWith(routeMode: value),
      ),
    );
  }
}

class BypassDomainItem extends ConsumerWidget {
  const BypassDomainItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    return ConfigListInputItem(
      title: (l) => l.bypassDomain,
      subtitle: (l) => l.bypassDomainDesc,
      itemMaxLength: TextInputLimits.domain,
      selector: networkSettingProvider.select((state) => state.bypassDomain),
      onChanged: _networkWriter(
        (state, value) => state.copyWith(bypassDomain: value),
      ),
    );
  }
}

class RouteAddressItem extends ConsumerWidget {
  const RouteAddressItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final bypassPrivate = ref.watch(
      networkSettingProvider.select(
        (state) => state.routeMode == RouteMode.bypassPrivate,
      ),
    );
    if (bypassPrivate) {
      return Container();
    }
    return ConfigListInputItem(
      title: (l) => l.routeAddress,
      subtitle: (l) => l.routeAddressDesc,
      itemMaxLength: TextInputLimits.cidr,
      maxWidth: 360,
      selector: patchClashConfigProvider.select(
        (state) => state.tun.routeAddress,
      ),
      onChanged: _tunWriter(
        (state, value) => state.copyWith.tun(routeAddress: value),
      ),
    );
  }
}

List<Widget> networkOptionsItems({
  required bool isDesktop,
  required bool isMacOS,
}) {
  return [
    if (isDesktop) const TUNItem(),
    if (isMacOS) const AutoSetSystemDnsItem(),
    const TunStackItem(),
    // mihomo's DefaultSocketHook ignores interface-name on Android
    // (core/lib.go installHooks, vendored dialer.go), so these rows only
    // apply on desktop.
    if (isDesktop) ...[
      const InterfaceNameModeItem(),
      const InterfaceNameItem(),
    ],
    if (!isDesktop) ...[const RouteModeItem(), const RouteAddressItem()],
  ];
}

class NetworkListView extends StatelessWidget {
  const NetworkListView({super.key});

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return generateListView([
      if (system.isAndroid) const VPNItem(),
      if (system.isAndroid)
        ...generateSection(
          title: 'VPN',
          items: [
            const VpnSystemProxyItem(),
            const BypassDomainItem(),
            const AllowBypassItem(),
            const Ipv6Item(),
            const DNSHijackingItem(),
          ],
        ),
      if (system.isDesktop)
        ...generateSection(
          title: appLocalizations.system,
          items: [const SystemProxyItem(), const BypassDomainItem()],
        ),
      ...generateSection(
        title: appLocalizations.options,
        items: networkOptionsItems(
          isDesktop: system.isDesktop,
          isMacOS: system.isMacOS,
        ),
      ),
    ]);
  }
}
