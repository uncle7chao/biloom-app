import 'dart:io';

import 'package:test/test.dart';

/// 策略组编辑器不能把已废弃的 `relay` 类型摆给用户选。
///
/// 本内核已删除 `type: relay`（`Clash.Meta/adapter/outboundgroup/parser.go:216`
/// 对它直接返回错误）。一旦用户选了这个类型，它会存进覆写数据，然后**整份配置都
/// 加载不了** —— 报错还是一句英文的「relay type was removed」，没人能联想到是自己
/// 刚才在下拉框里选的那一项。
///
/// 所以这里做源码级断言：类型选项必须来自一份显式的白名单，而不是 `GroupType.values`
/// （后者会在上游往枚举里加东西时把 relay 一并带回来）。
///
/// 链式代理的正路是代理级的 `dialer-proxy` 字段，入口在「代理」页的
/// ⋮ → 添加链式代理（`lib/views/proxies/add_chain.dart`）。
const _groupEditor = 'lib/views/profiles/overwrite/custom/groups.dart';

void main() {
  test('策略组类型选项是一份白名单，不是 GroupType.values', () {
    final file = File(_groupEditor);
    if (!file.existsSync()) {
      fail('$_groupEditor 不存在；这个断言要跟着策略组编辑器一起搬家。');
    }
    final source = file.readAsStringSync();

    expect(
      source,
      isNot(contains('GroupType.values')),
      reason:
          '策略组编辑器用了 GroupType.values 来填类型选项。relay 已经在核心里被'
          '删掉，选到它会让整份配置加载失败，必须显式排除。',
    );
    expect(
      source,
      contains('_selectableTypes'),
      reason: '类型选项应当来自显式的白名单常量；这份白名单不见了，请确认 relay 仍被排除。',
    );
    expect(
      RegExp(r'GroupType\.Relay').hasMatch(
        source.substring(source.indexOf('_selectableTypes')),
      ),
      isFalse,
      reason: '白名单里出现了 GroupType.Relay —— 它会让用户做出加载不了的配置。',
    );
  });

  test('链式代理走的是独立的 dialer-proxy 面板', () {
    final panel = File('lib/views/proxies/add_chain.dart');
    expect(
      panel.existsSync(),
      isTrue,
      reason: '链式代理面板不见了。链只能写成代理级的 dialer-proxy，不能再靠分组类型。',
    );
    for (final api in ['readProfileTargets', 'setProxyChainOnProfile']) {
      expect(
        panel.readAsStringSync(),
        contains(api),
        reason: '链式代理面板应当通过 $api 读写配置。',
      );
    }
  });
}
