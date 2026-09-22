import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/state.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../helpers/test_app.dart';

const _runningVersion = '0.8.95';

const _payload =
    '{"schemaVersion":2,"versions":[{"version":"0.8.96","tag":"v0.8.96",'
    '"date":"2026-08-16","prerelease":false,"groups":['
    '{"type":"breaking","entries":[{"id":"af20769","text":'
    '"Re-import backups"}]},'
    '{"type":"feat","entries":[{"id":"1a2b3c4","text":'
    '"Override scripts"}]}]}]}';

const _bulletsOnly =
    '<!-- biloom:changelog:begin -->\n'
    '- Override scripts\n'
    '<!-- biloom:changelog:end -->\n';

String _bodyWith(String payload) =>
    '$_bulletsOnly\n<!-- biloom:changelog:json\n$payload\n-->\n';

/// 一个「有新版」的结果。注意 `hasUpdate` 这个状态是**必须**显式给的 ——
/// 旧接口用 `null` 同时表示「已是最新」和「请求失败」，正是本次要修掉的歧义。
UpdateCheckResult release(String? body) => UpdateCheckResult(
  UpdateCheckStatus.hasUpdate,
  <String, dynamic>{'tag_name': 'v0.8.96', 'body': body},
);

const _upToDate = UpdateCheckResult(UpdateCheckStatus.upToDate);
const _failed = UpdateCheckResult(UpdateCheckStatus.failed);

Future<ProviderContainer> pumpApp(WidgetTester tester, {Locale? locale}) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  globalState.container = container;
  // appSettingProvider is autoDispose; in the app `configProvider` keeps it
  // alive, so the test has to hold a listener or edits are dropped.
  container.listen(appSettingProvider, (_, _) {}, fireImmediately: true);
  container
      .read(viewSizeProvider.notifier)
      .update((_) => const Size(1200, 800));

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: TestApp(
        locale: locale,
        child: const Scaffold(body: SizedBox.shrink()),
      ),
    ),
  );
  await tester.pump();
  return container;
}

/// The dialog blocks until the user answers, so tests must close it before
/// awaiting the call that opened it.
Future<void> tapCancel(WidgetTester tester) async {
  await tester.tap(find.byType(TextButton).first);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    globalState.packageInfo = PackageInfo(
      appName: 'FlClash',
      packageName: 'com.follow.clash',
      version: _runningVersion,
      buildNumber: '1',
    );
  });

  testWidgets('renders the grouped notes carried by the release', (
    tester,
  ) async {
    final container = await pumpApp(tester);

    final shown = container
        .read(commonActionProvider.notifier)
        .checkUpdateResultHandle(result: release(_bodyWith(_payload)));
    await tester.pumpAndSettle();

    expect(find.textContaining('v0.8.96'), findsOneWidget);
    expect(find.textContaining('Re-import backups'), findsOneWidget);
    expect(find.textContaining('Override scripts'), findsOneWidget);
    expect(find.textContaining('Breaking changes'), findsOneWidget);

    await tapCancel(tester);
    await shown;
  });

  testWidgets('localizes the group titles but not the entries', (tester) async {
    final container = await pumpApp(tester, locale: const Locale('zh', 'CN'));

    final shown = container
        .read(commonActionProvider.notifier)
        .checkUpdateResultHandle(result: release(_bodyWith(_payload)));
    await tester.pumpAndSettle();

    // Entry copy comes from the release payload and is English only; the group
    // headings still follow the app locale.
    expect(find.textContaining('新功能'), findsOneWidget);
    expect(find.textContaining('Override scripts'), findsOneWidget);

    await tapCancel(tester);
    await shown;
  });

  testWidgets('falls back to the bullets of a release without a payload', (
    tester,
  ) async {
    final container = await pumpApp(tester);

    final shown = container
        .read(commonActionProvider.notifier)
        .checkUpdateResultHandle(result: release(_bulletsOnly));
    await tester.pumpAndSettle();

    expect(find.textContaining('- Override scripts'), findsOneWidget);

    await tapCancel(tester);
    await shown;
  });

  testWidgets('stops reminding when an automatic check is dismissed', (
    tester,
  ) async {
    final container = await pumpApp(tester);

    final shown = container
        .read(commonActionProvider.notifier)
        .checkUpdateResultHandle(result: release(_bodyWith(_payload)));
    await tester.pumpAndSettle();
    await tapCancel(tester);
    await shown;

    expect(container.read(appSettingProvider).autoCheckUpdate, isFalse);
  });

  testWidgets('a manual check reports an unreachable server as a failure', (
    tester,
  ) async {
    final container = await pumpApp(tester);

    final shown = container
        .read(commonActionProvider.notifier)
        .checkUpdateResultHandle(result: _failed, isUser: true);
    await tester.pumpAndSettle();

    // 这条是本轮修复的核心：断网/仓库 404 时**不能**说成「已是最新版」。
    // 旧接口用 null 同时表示两种结局，于是失败被显示成成功。
    expect(
      find.text(
        'Could not reach the update server. Check your connection and try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('The app is already up to date'), findsNothing);

    await tapCancel(tester);
    await shown;
    expect(container.read(appSettingProvider).autoCheckUpdate, isTrue);
  });

  testWidgets('a manual check still reports genuinely being up to date', (
    tester,
  ) async {
    final container = await pumpApp(tester);

    final shown = container
        .read(commonActionProvider.notifier)
        .checkUpdateResultHandle(result: _upToDate, isUser: true);
    await tester.pumpAndSettle();

    expect(find.text('The app is already up to date'), findsOneWidget);

    await tapCancel(tester);
    await shown;
    expect(container.read(appSettingProvider).autoCheckUpdate, isTrue);
  });

  testWidgets('an automatic check stays silent when the server is unreachable', (
    tester,
  ) async {
    final container = await pumpApp(tester);

    await container
        .read(commonActionProvider.notifier)
        .checkUpdateResultHandle(result: _failed);
    await tester.pumpAndSettle();

    // 启动时因为查不到就弹窗属于打扰；但也不能顺手把用户的自动检查关掉
    // —— 关掉只在「用户主动点了不再提醒」时发生。
    expect(find.text('Check for updates'), findsNothing);
    expect(container.read(appSettingProvider).autoCheckUpdate, isTrue);
  });
}
