import 'proxy_region.dart';

/// 「意图分组」模板与计划层。
///
/// 与「按地区生成分组」（`proxy_region.dart`）共用同一套安全哲学：
/// 计划只读、成员全部真实存在、只动**名字对得上**的自己生成的组。
/// 不同之处在于意图分组除了建组还要写规则 —— 每个意图一张 GEOSITE 名单
/// 指向自己的组，且规则**必须排在订阅自带规则之前**才有意义（排在
/// GEOSITE,CN 直连后面就永远轮不到）。写入侧用 `RuleListMixin.put` 的
/// autoOrder（新规则天然插到最前），正好满足这条顺序要求。
///
/// 名单来源是随包的 GEOSITE.dat（v2fly 社区名单）。`category-ai-!cn` 这类
/// Meta 系名单**不在这个 dat 里**，所以 AI 意图用单列的 `openai` —— 名单
/// 是否在包里由 `subscription_defaults_test.go` 风格的内核测试守住，这里
/// 不做运行时探测。
enum IntentKey { streaming, ai, social }

class IntentTemplate {
  final IntentKey key;
  final String emoji;

  /// GEOSITE 类目名，逐个生成一条规则。同一意图内的类目是「或」的关系。
  final List<String> categories;

  const IntentTemplate({
    required this.key,
    required this.emoji,
    required this.categories,
  });
}

const intentTemplates = <IntentTemplate>[
  IntentTemplate(
    key: IntentKey.streaming,
    emoji: '🎬',
    categories: ['netflix', 'disney', 'youtube', 'spotify', 'tiktok'],
  ),
  IntentTemplate(key: IntentKey.ai, emoji: '🤖', categories: ['openai']),
  IntentTemplate(
    key: IntentKey.social,
    emoji: '💬',
    categories: ['telegram', 'instagram', 'facebook'],
  ),
];

/// 三个意图的域名互不重叠（tiktok 归流媒体，社交只收 telegram/instagram/
/// facebook），所以意图之间的规则先后顺序无所谓，落在订阅规则之前即可。
class IntentGroupDraft {
  final IntentKey key;
  final String emoji;
  final String name;
  final List<String> members;
  final List<String> categories;
  final bool isUpdate;

  const IntentGroupDraft({
    required this.key,
    required this.emoji,
    required this.name,
    required this.members,
    required this.categories,
    required this.isUpdate,
  });
}

class IntentGroupPlan {
  final List<IntentGroupDraft> upserts;
  final List<String> removals;
  const IntentGroupPlan({required this.upserts, required this.removals});
}

/// 组名与 Go 侧订阅兼容层注入的默认组保持同一拼法（`core/subscription_defaults.go`
/// 的 `defaultGroupProxies` / `defaultGroupAuto`）。意图组成员把「节点选择」
/// 排在最前 —— select 组默认选中第一项，于是新应用的意图默认跟着主开关走，
/// 与用户对「这个组是什么」的直觉一致；两个锚点组不存在（原生机场配置）时
/// 优雅退化为纯节点列表，绝不引用不存在的名字让整份配置加载失败。
const intentAnchorGroupNames = <String>['节点选择', '自动选择'];

IntentGroupPlan buildIntentGroupPlan({
  required Set<IntentKey> enabled,
  required Iterable<String> proxyNames,
  required List<ExistingRegionGroup> existingGroups,
  required String Function(IntentTemplate template) nameOf,
}) {
  final knownGroupNames = existingGroups.map((group) => group.name).toSet();
  final anchors = [
    for (final anchor in intentAnchorGroupNames)
      if (knownGroupNames.contains(anchor)) anchor,
  ];
  final proxyList = proxyNames.toList();
  final drafts = <IntentGroupDraft>[];
  for (final template in intentTemplates) {
    final name = nameOf(template);
    if (!enabled.contains(template.key)) {
      continue;
    }
    drafts.add(
      IntentGroupDraft(
        key: template.key,
        emoji: template.emoji,
        name: name,
        members: [...anchors, ...proxyList, 'DIRECT'],
        categories: template.categories,
        isUpdate: knownGroupNames.contains(name),
      ),
    );
  }
  final upsertNames = drafts.map((draft) => draft.name).toSet();
  final removals = <String>[];
  for (final template in intentTemplates) {
    final name = nameOf(template);
    if (enabled.contains(template.key) || !knownGroupNames.contains(name)) {
      continue;
    }
    if (upsertNames.contains(name)) {
      continue;
    }
    removals.add(name);
  }
  return IntentGroupPlan(upserts: drafts, removals: removals);
}
