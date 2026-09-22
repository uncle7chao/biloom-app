import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/dns_leak.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

/// 让**所有**域名都解析到给定地址。
///
/// 刻意不看 host：页面内部是随机从池子里挑域名的，测试不该去猜它挑了哪两个，
/// 只该规定「不管问哪个，解析器都这么答」。这同时也顺带证明了随机挑选对结论无影响。
void _resolve(List<String> addresses) {
  lookupHosts = (host) async => addresses.map(InternetAddress.new).toList();
}

void _failEverything() {
  lookupHosts = (host) async => throw const SocketException('no such host');
}

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [profilesProvider.overrideWith(TestProfiles.new)],
    );
    globalState.container = container;
    container.read(viewSizeProvider.notifier).value = const Size(1400, 1000);
  });

  tearDown(() {
    // 必须还原：这个 seam 是全局变量，漏还原会把假结果漏给同一进程里的其他测试。
    lookupHosts = (host) => InternetAddress.lookup(host);
    container.dispose();
  });

  Future<void> pumpView(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: DnsLeakView()),
      ),
    );
    await tester.pump();
  }

  /// 改状态**必须在页面挂载之后**再做。
  ///
  /// 原因不是语义，而是 riverpod 的调度器：`container.read` 在 `widget` 之后关闭订阅时
  /// 会挂一个「零延迟 Timer」来延后销毁，而这个 Timer 只有在跑帧时才会被清掉。
  /// 在 `pumpWidget` 之前改，等于在一个没人推帧的时刻留下 Timer，测试收尾会直接报
  /// `A Timer is still pending even after the widget tree was disposed`。
  /// 多推一帧是为了确保这次变更自身引发的调度也被排空。
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  /// 把连接状态设成「已启动」，可选地开启系统代理 / TUN。
  Future<void> connect(
    WidgetTester tester, {
    bool systemProxy = false,
    bool tun = false,
  }) async {
    // isStartProvider 就是 `runTimeProvider != null`，所以「已连接」等价于塞一个启动时间。
    container
        .read(runTimeProvider.notifier)
        .update((_) => DateTime(2026).millisecondsSinceEpoch);
    container
        .read(networkSettingProvider.notifier)
        .update((state) => state.copyWith(systemProxy: systemProxy));
    if (tun) {
      container
          .read(patchClashConfigProvider.notifier)
          .update(
            (state) => state.copyWith(tun: state.tun.copyWith(enable: true)),
          );
    }
    await settle(tester);
  }

  Future<void> setDnsMode(WidgetTester tester, DnsMode mode) async {
    container
        .read(patchClashConfigProvider.notifier)
        .update(
          (state) => state.copyWith(dns: state.dns.copyWith(enhancedMode: mode)),
        );
    await settle(tester);
  }

  /// 点「开始检测」并把结果推进到落地。
  ///
  /// 这里不用 `pumpAndSettle`：检测中会显示 `CommonCircleLoading`，那是个**永不停**的
  /// 旋转动画，`pumpAndSettle` 会一直等它停而超时。注入的查询是同步完成的，
  /// 帧推两下足够。
  Future<void> runCheck(WidgetTester tester) async {
    await tester.tap(find.text('Run check'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('默认状态', () {
    testWidgets('未连接时接管方式显示断开，且不谎称已检测', (tester) async {
      await pumpView(tester);

      expect(find.text('Current takeover'), findsOneWidget);
      expect(find.text('Disconnected'), findsOneWidget);

      // 标题是**动作**而不是页名 —— 页名已经在 AppBar 上了，重复一遍没有信息量。
      expect(find.text('Run check'), findsOneWidget);
      expect(
        find.text('Check whether the system DNS is taken over by the core'),
        findsOneWidget,
      );
      expect(tester.takeException(), null);
    });

    testWidgets('列出当前 nameserver 与分流策略', (tester) async {
      await pumpView(tester);

      // 新版默认上游应当是境外 DoH —— 这条断言同时守住了「A 改动没被回退」。
      expect(find.textContaining('https://1.1.1.1/dns-query'), findsOneWidget);
      expect(find.text('Nameserver policy'), findsOneWidget);
    });
  });

  group('接管方式的呈现', () {
    testWidgets('仅系统代理时标 System proxy', (tester) async {
      await pumpView(tester);
      await connect(tester, systemProxy: true);

      expect(find.text('System proxy'), findsOneWidget);
      expect(tester.takeException(), null);
    });

    testWidgets('TUN 开启时标 TUN', (tester) async {
      await pumpView(tester);
      await connect(tester, tun: true);

      expect(find.text('TUN'), findsOneWidget);
      expect(tester.takeException(), null);
    });

    testWidgets('两者同时开启时并列表述', (tester) async {
      await pumpView(tester);
      await connect(tester, systemProxy: true, tun: true);

      expect(find.text('System proxy + TUN'), findsOneWidget);
      expect(tester.takeException(), null);
    });
  });

  group('改用 TUN 的修复动作', () {
    testWidgets('仅系统代理时给出动作，点一下就真的切到 TUN', (tester) async {
      await pumpView(tester);
      await connect(tester, systemProxy: true);

      expect(find.text('Switch to TUN'), findsOneWidget);

      await tester.tap(find.text('Switch to TUN'));
      await settle(tester);

      // 写的是 tun.enable —— 与设置页那个 TUN 开关同一个字段，不是另搞一套。
      expect(container.read(patchClashConfigProvider).tun.enable, isTrue);
      // 接管方式跟着变，而动作本身随即消失（TUN 已经开了，没什么可修的了）。
      expect(find.text('System proxy + TUN'), findsOneWidget);
      expect(find.text('Switch to TUN'), findsNothing);
    });

    testWidgets('TUN 已开时不给这个动作', (tester) async {
      await pumpView(tester);
      await connect(tester, tun: true);

      expect(find.text('Switch to TUN'), findsNothing);
    });

    testWidgets('未连接时不给这个动作', (tester) async {
      await pumpView(tester);

      // 还没开始用代理，谈不上「改用 TUN」——不要在这里制造焦虑。
      expect(find.text('Switch to TUN'), findsNothing);
    });
  });

  group('检测结论', () {
    testWidgets('拿到 fake-ip 地址即判定已被内核接管', (tester) async {
      _resolve(['198.18.0.5']);
      await pumpView(tester);
      await connect(tester, tun: true);

      await runCheck(tester);

      expect(find.text('Taken over by the core'), findsOneWidget);
      expect(find.textContaining('198.18.0.5'), findsOneWidget);
      expect(tester.takeException(), null);
    });

    testWidgets('拿到真实公网 IP 即判定未被接管', (tester) async {
      // 这正是「仅系统代理」下的真实结果：系统自己的查询没经过内核。
      _resolve(['93.184.216.34']);
      await pumpView(tester);
      await connect(tester, systemProxy: true);

      await runCheck(tester);

      expect(find.text('Not taken over'), findsOneWidget);
      expect(find.textContaining('93.184.216.34'), findsOneWidget);
      expect(tester.takeException(), null);
    });

    testWidgets('redir-host 模式老实说测不了，而不是给一个误导结论', (tester) async {
      // 该模式下内核自己返回真实 IP，和「没接管」长得一模一样 —— 必须区分开。
      _resolve(['93.184.216.34']);
      await pumpView(tester);
      await setDnsMode(tester, DnsMode.redirHost);
      await connect(tester, tun: true);

      await runCheck(tester);

      expect(find.text('Cannot be judged in this mode'), findsOneWidget);
      expect(find.text('Not taken over'), findsNothing);
      expect(tester.takeException(), null);
    });

    testWidgets('问不到任何解析器时与「未被接管」区分开', (tester) async {
      _failEverything();
      await pumpView(tester);
      await connect(tester, tun: true);

      await runCheck(tester);

      expect(find.text('No resolver answered'), findsOneWidget);
      expect(find.text('Not taken over'), findsNothing);
      expect(tester.takeException(), null);
    });
  });

  group('结论作废', () {
    testWidgets('接管方式一变，上一轮结论立刻作废', (tester) async {
      _resolve(['198.18.0.5']);
      await pumpView(tester);
      await connect(tester, systemProxy: true);

      await runCheck(tester);
      expect(find.text('Taken over by the core'), findsOneWidget);

      // 切到 TUN：此时那个「已接管」的结论是上一套接管方式下的产物，不能再挂着。
      container
          .read(patchClashConfigProvider.notifier)
          .update(
            (state) => state.copyWith(tun: state.tun.copyWith(enable: true)),
          );
      await settle(tester);

      expect(find.text('Taken over by the core'), findsNothing);
      expect(find.text('Run check'), findsOneWidget);
      expect(tester.takeException(), null);
    });
  });
}
