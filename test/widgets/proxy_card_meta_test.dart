import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/proxies/card.dart';
import 'package:fl_clash/views/proxies/common.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

/// 节点卡片第二行胶囊的宽度降级回归。
///
/// 01.00.31 实机翻车：窄卡上「地区胶囊 + 协议胶囊」挂 Flexible 被挤成空框。
/// 修复后按量宽预算三级降级（全名 → 旗子 → 隐藏）。
///
/// ⛔ 断言设计：期望文本与 widget 同源（resolveProxyRegion().label），失败时
/// 把实际渲染内容塞进 reason —— 输出尾部直接可读，不用翻日志找 DIAG 行。
const _proxyName = '移动-HKG-80-WS';

void main() {
  late ProviderContainer container;

  tearDown(() {
    container.dispose();
  });

  ProviderContainer buildContainer() {
    final profile = Profile.normal();
    final proxy = Proxy(name: _proxyName, type: 'Vless');
    return ProviderContainer(
      overrides: [
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        profilesProvider.overrideWith(() => TestProfiles([profile])),
        groupsProvider.overrideWithValue([
          Group(
            type: GroupType.Selector,
            name: kPrimarySelectorGroupName,
            now: proxy.name,
            all: [proxy],
          ),
        ]),
      ],
    );
  }

  Future<void> pumpCard(WidgetTester tester, {required double width}) async {
    // 地区标签读全局 AppLocalizations.current（手写 l10n），必须先显式加载
    // zh_CN（带国家码，只给 'zh' 命中不了 messages_zh_CN）。
    await AppLocalizations.load(const Locale('zh', 'CN'));
    // 第一帧：globalState.measure 在 TestApp builder 里赋值，getItemHeight
    // 和量宽降级都依赖它。
    // ⛔ includeNavigatorKey 必须为 false：TestApp 默认挂 globalState.navigatorKey
    // （全局 GlobalKey），同一个测试里连 pump 两次 TestApp 时，第二次
    // MaterialApp 会复用旧的 NavigatorState —— 保留下来的 home 还是第一棵树
    // 的 SizedBox.shrink 空壳，真卡片根本挂不上去（cardCount=0 texts=[]，
    // 且无任何异常，极难排查）。
    await tester.pumpWidget(
      const TestApp(includeNavigatorKey: false, child: SizedBox.shrink()),
    );
    final height = getItemHeight(ProxyCardType.shrink);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          includeNavigatorKey: false,
          locale: const Locale('zh'),
          child: SizedBox(
            width: width,
            height: height,
            child: ProxyCard(
              groupName: kPrimarySelectorGroupName,
              testUrl: null,
              proxy: Proxy(name: _proxyName, type: 'Vless'),
              groupType: GroupType.Selector,
              type: ProxyCardType.shrink,
            ),
          ),
        ),
      ),
    );
    // 补两帧：MaterialApp 自己的 zh_CN load 完成后触发一次重建，等它落定。
    await tester.pump();
    await tester.pump();
  }

  /// 卡片实际渲染的全部富文本 plain text + 每个胶囊的盒子尺寸。
  String diagnose(WidgetTester tester) {
    final texts = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((widget) => widget.text.toPlainText())
        .toList();
    final chips = find
        .byType(ProxyTypeChip)
        .evaluate()
        .map((chip) {
          final size = (chip.renderObject as RenderBox).size;
          return '"$size"';
        })
        .join(', ');
    return 'cardCount=${find.byType(ProxyCard).evaluate().length} '
        'chipCount=${find.byType(ProxyTypeChip).evaluate().length} '
        'texts=$texts chipBoxes=[$chips]';
  }

  double chipBoxWidth(WidgetTester tester, String text) {
    final richFinder = find.textContaining(text, findRichText: true);
    final chipFinder = find.ancestor(
      of: richFinder.first,
      matching: find.byType(ProxyTypeChip),
    );
    return tester.getSize(chipFinder.first).width;
  }

  testWidgets('wide card shows the full region chip and protocol chip', (
    tester,
  ) async {
    container = buildContainer();
    globalState.container = container;
    await pumpCard(tester, width: 760);

    final region = resolveProxyRegion(_proxyName);
    final label = region.label;
    final fullText = '${region.emoji} $label';
    final diag = diagnose(tester);

    expect(tester.takeException(), isNull, reason: diag);
    final texts = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((widget) => widget.text.toPlainText())
        .toList();
    // 期望文本与 widget 同源；失败时 reason 带上实际渲染内容。
    expect(texts, contains(fullText), reason: '期望胶囊文本[$fullText] $diag');
    expect(
      chipBoxWidth(tester, fullText),
      greaterThan(66),
      reason: '地区胶囊不能是空框 $diag',
    );
    expect(texts, contains('Vless'), reason: diag);
  });

  testWidgets('narrow card never renders an empty chip box', (tester) async {
    container = buildContainer();
    globalState.container = container;
    await pumpCard(tester, width: 260);

    final diag = diagnose(tester);
    expect(tester.takeException(), isNull, reason: diag);
    final texts = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((widget) => widget.text.toPlainText())
        .toList();
    // 协议胶囊任何档位都必须在；失败时能直接看到渲染了什么。
    expect(texts, contains('Vless'), reason: '协议胶囊缺失 $diag');
    // 核心不变式：每一个胶囊的盒子都要宽于「只剩 padding 的空框」，文本非空。
    for (final chip in find.byType(ProxyTypeChip).evaluate()) {
      final size = (chip.renderObject as RenderBox).size;
      expect(
        size.width,
        greaterThan(22),
        reason: 'chip ${chip.widget} 盒宽 ${size.width} = 空框 $diag',
      );
    }
  });
}
