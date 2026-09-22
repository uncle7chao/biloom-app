import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// DNS 泄露自检。
///
/// 这个页面只做一件事：回答「我以为我在用代理，那我的 DNS 查询到底有没有走代理？」
///
/// 它不去联网问第三方「我的 DNS 泄露了吗」—— 那种测试要么拿到的是浏览器路径的结果
/// （而泄露往往发生在浏览器之外），要么把你的解析器 IP 又交给一个新的第三方。
/// 这里用的是**本地可验证的事实**：fake-ip 模式下，内核回答任何域名都会给出
/// fake-ip 段里的地址。所以拿系统解析器去问一个平时不会访问的域名，
/// 看回来的是 fake-ip 还是真实公网 IP，就能确知这次查询有没有到内核手上。
class DnsLeakView extends ConsumerStatefulWidget {
  const DnsLeakView({super.key});

  @override
  ConsumerState<DnsLeakView> createState() => _DnsLeakViewState();
}

class _DnsLeakViewState extends ConsumerState<DnsLeakView> {
  bool _checking = false;
  DnsTakeoverProbeResult? _result;
  String? _lastSignature;

  Future<void> _runProbe() async {
    if (_checking) {
      return;
    }
    setState(() {
      _checking = true;
      _result = null;
    });
    final dns = ref.read(patchClashConfigProvider).dns;
    final result = await probeSystemDnsTakeover(
      enhancedMode: dns.enhancedMode,
      fakeIpRange: dns.fakeIpRange,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _checking = false;
      _result = result;
    });
  }

  String _takeoverText(
    AppLocalizations appLocalizations, {
    required bool running,
    required bool systemProxy,
    required bool tunEnable,
  }) {
    if (!running) {
      return appLocalizations.disconnected;
    }
    final parts = <String>[
      if (systemProxy) appLocalizations.systemProxy,
      if (tunEnable) appLocalizations.tun,
    ];
    if (parts.isEmpty) {
      return appLocalizations.disconnected;
    }
    return parts.join(' + ');
  }

  IconData _takeoverIcon({required bool running, required bool tunEnable}) {
    if (!running) {
      return Icons.link_off;
    }
    return tunEnable ? Icons.vpn_lock : Icons.lan;
  }

  Color _takeoverColor(
    ColorScheme colorScheme, {
    required bool running,
    required bool tunEnable,
  }) {
    if (!running) {
      return colorScheme.onSurfaceVariant;
    }
    // 只有 TUN 才是「全量接管」，系统代理单独出现时不足以拦住系统自己的查询，
    // 所以这里给两种状态不同的颜色，而不是笼统地都算「好的」。
    return tunEnable ? colorScheme.primary : colorScheme.tertiary;
  }

  String _outcomeText(
    AppLocalizations appLocalizations,
    DnsTakeoverOutcome outcome,
  ) {
    return switch (outcome) {
      DnsTakeoverOutcome.takenOver => appLocalizations.dnsLeakTakenOver,
      DnsTakeoverOutcome.notTakenOver => appLocalizations.dnsLeakNotTakenOver,
      DnsTakeoverOutcome.notApplicable => appLocalizations.dnsLeakNotApplicable,
      DnsTakeoverOutcome.failed => appLocalizations.dnsLeakFailed,
    };
  }

  Color _outcomeColor(ColorScheme colorScheme, DnsTakeoverOutcome outcome) {
    return switch (outcome) {
      DnsTakeoverOutcome.takenOver => colorScheme.primary,
      DnsTakeoverOutcome.notTakenOver => colorScheme.error,
      DnsTakeoverOutcome.notApplicable => colorScheme.tertiary,
      DnsTakeoverOutcome.failed => colorScheme.error,
    };
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final colorScheme = context.colorScheme;
    final systemProxy = ref.watch(
      networkSettingProvider.select((state) => state.systemProxy),
    );
    final tunEnable = ref.watch(
      patchClashConfigProvider.select((state) => state.tun.enable),
    );
    final running = ref.watch(isStartProvider);
    final dns = ref.watch(
      patchClashConfigProvider.select((state) => state.dns),
    );

    // 接管方式一变，「上次检测的结论」就不再对当前状态成立 —— 直接作废，
    // 免得用户切到 TUN 之后还看着上一轮「未被接管」的结论发懵。
    // 这里在 build 里直接改字段、不叫 setState：因为紧接着就要用这个新值渲染，
    // 再触发一次重建反而多一轮。
    final signature = '$running|$systemProxy|$tunEnable';
    if (_lastSignature != null && _lastSignature != signature) {
      _result = null;
    }
    _lastSignature = signature;

    final result = _result;
    final nameserverPolicy = dns.nameserverPolicy.entries
        .map((entry) => '${entry.key} → ${entry.value}')
        .toList();

    return BaseScaffold(
      title: appLocalizations.dnsLeakCheck,
      body: generateListView([
        ...generateSection(
          title: appLocalizations.status,
          isFirst: true,
          items: [
            ListItem(
              leading: Icon(
                _takeoverIcon(running: running, tunEnable: tunEnable),
                color: _takeoverColor(
                  colorScheme,
                  running: running,
                  tunEnable: tunEnable,
                ),
              ),
              title: Text(appLocalizations.dnsLeakMode),
              subtitle: Text(
                _takeoverText(
                  appLocalizations,
                  running: running,
                  systemProxy: systemProxy,
                  tunEnable: tunEnable,
                ),
              ),
            ),
            ListItem(
              leading: result == null
                  ? const Icon(Icons.travel_explore)
                  : Icon(
                      _outcomeIcon(result.outcome),
                      color: _outcomeColor(colorScheme, result.outcome),
                    ),
              // 页名已经在 AppBar 上了，这一行再重复一遍没有信息量 —— 所以未检测时
              // 标题写的是**动作**（开始检测），检测完才换成**结论**。
              title: Text(
                result == null
                    ? appLocalizations.dnsLeakRun
                    : _outcomeText(appLocalizations, result.outcome),
                style: result == null
                    ? null
                    : TextStyle(
                        color: _outcomeColor(colorScheme, result.outcome),
                      ),
              ),
              subtitle: Text(
                _checking
                    ? appLocalizations.dnsLeakRunning
                    : result == null
                    ? appLocalizations.dnsLeakCheckDesc
                    : _detailText(result),
              ),
              trailing: _checking
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CommonCircleLoading(),
                    )
                  : Icon(
                      Icons.play_arrow,
                      color: colorScheme.onSurfaceVariant,
                    ),
              onTap: _checking ? null : _runProbe,
            ),
            // 系统代理只作用于「认这个代理的程序」，Windows 自己发出的 DNS 查询不在其列
            // —— 这正是本页要暴露的事实。既然结论已经摆在这里，修的动作就该同屏给出，
            // 而不是让用户自己回设置页去找 TUN 开关。
            // 条件用「已连接 && TUN 未开」而不是「检测结果为未被接管」：前者在**检测之前**
            // 就已经成立，用户不必先跑一遍才知道能给什么动作；TUN 已开时则不必出现。
            if (running && !tunEnable)
              ListItem(
                leading: Icon(Icons.vpn_lock, color: colorScheme.tertiary),
                title: Text(appLocalizations.switchToTun),
                subtitle: Text(appLocalizations.switchToTunDesc),
                onTap: () =>
                    ref.read(systemActionProvider.notifier).switchToTun(),
              ),
          ],
        ),
        ...generateSection(
          title: appLocalizations.nameserver,
          items: [
            ListItem(
              title: Text(appLocalizations.nameserver),
              subtitle: Text(dns.nameserver.join('\n')),
            ),
            if (nameserverPolicy.isNotEmpty)
              ListItem(
                title: Text(appLocalizations.nameserverPolicy),
                subtitle: Text(nameserverPolicy.join('\n')),
              ),
          ],
        ),
        ...generateSection(
          title: appLocalizations.tip,
          items: [
            ListItem(
              leading: const Icon(Icons.public),
              title: Text(appLocalizations.dnsLeakOnline),
              subtitle: const Text('dnsleaktest.com'),
              onTap: () => dialogs.openUrl('https://dnsleaktest.com/'),
            ),
            Padding(
              padding: baseInfoEdgeInsets,
              child: Text(
                appLocalizations.dnsLeakExplain,
                style: context.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ]),
    );
  }

  IconData _outcomeIcon(DnsTakeoverOutcome outcome) {
    return switch (outcome) {
      DnsTakeoverOutcome.takenOver => Icons.verified_user,
      DnsTakeoverOutcome.notTakenOver => Icons.report_problem,
      DnsTakeoverOutcome.notApplicable => Icons.help_outline,
      DnsTakeoverOutcome.failed => Icons.cloud_off,
    };
  }

  String _detailText(DnsTakeoverProbeResult result) {
    final address = result.sampleAddress;
    final hosts = result.hosts.join(', ');
    if (address == null) {
      return hosts;
    }
    return '$hosts → $address';
  }
}
