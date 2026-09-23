import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 「按地区生成分组」面板 —— 先看清会发生什么，再决定。
///
/// 这个动作改的是**覆写数据里真正生效**的那份策略组，所以：
///
/// - 先把计划列出来：哪个地区、多少个节点、是新建还是更新；以及哪些旧组会被移除。
/// - 移除那几条必须说清楚 —— 它们引用的节点已经不在配置里，留着会让**整份配置
///   加载失败**（内核构造策略组时找不到成员名就报错，`validateConfig` 拦不住）。
/// - 「其他」不参与生成（见 `buildRegionGroupPlan`），所以那一行只报数量、不报动作。
///
/// 计划**在面板里现算**（[readRegionGroupPlan]），算的过程只读，用户看完直接关掉
/// 不会有任何副作用。调用方要负责的就一件事：先把配置切到「自定义覆写」模式，
/// 否则写进去的分组根本不生效。
class RegionGroupPlanView extends ConsumerStatefulWidget {
  final int profileId;

  const RegionGroupPlanView({super.key, required this.profileId});

  @override
  ConsumerState<RegionGroupPlanView> createState() =>
      _RegionGroupPlanViewState();
}

class _RegionGroupPlanViewState extends ConsumerState<RegionGroupPlanView> {
  RegionGroupPlan? _plan;
  Object? _loadError;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final plan = await ref
          .read(profilesActionProvider.notifier)
          .readRegionGroupPlan(widget.profileId);
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error);
    }
  }

  Future<void> _handleApply() async {
    final plan = _plan;
    // 计划还没算出来时那颗 ✓ 根本不该出现（见 actions），这里只是兜底。
    if (plan == null || _applying) {
      return;
    }
    setState(() => _applying = true);
    final appLocalizations = context.appLocalizations;
    final int skipped;
    try {
      skipped = await ref
          .read(profilesActionProvider.notifier)
          .applyRegionGroupPlan(widget.profileId, plan);
    } finally {
      // 出错也要把锁放开 —— 卡在 `_applying = true` 上，那颗 ✓ 就再也点不动了。
      if (mounted) {
        setState(() => _applying = false);
      }
    }
    if (!mounted) {
      return;
    }
    final lines = <String>[
      appLocalizations.generateRegionGroupsDone,
      '',
      for (final draft in plan.upserts)
        '${draft.region.emoji} ${draft.region.label}   '
            '${draft.proxyNames.length}   '
            '${draft.isUpdate ? appLocalizations.update : appLocalizations.create}',
      for (final name in plan.removals) '$name   ${appLocalizations.remove}',
      // 重名被挡下是**要说出来**的：不说的话，用户会以为每个地区都建好了。
      if (skipped > 0) '',
      if (skipped > 0) appLocalizations.proxyGroupNameDuplicate,
    ];
    Navigator.of(context).pop();
    await dialogs.showMessage(
      message: TextSpan(text: lines.join('\n')),
      cancelable: false,
    );
  }

  /// 一行「地区 / 组名 + 数量 + 动作」。
  ///
  /// 数量单独占一列而不是拼进文案里：拼进文案就得给每种语言准备一条带占位符的
  /// 词条，而且数字夹在句子中间反而不好扫。列对齐之后，竖着看一眼就知道哪个
  /// 地区的节点最多。
  Widget _buildRow({
    required String label,
    required String action,
    int? count,
    bool isRemoval = false,
  }) {
    final colorScheme = context.colorScheme;
    return Padding(
      // 左右不加缩进：外层 ListView 已经给了 16，再叠一层会让行比小节标题多缩一截。
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: EmojiText(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.bodyMedium,
            ),
          ),
          if (count != null) ...[
            Text(
              '$count',
              style: context.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Text(
            action,
            style: context.textTheme.labelSmall?.copyWith(
              color: isRemoval ? colorScheme.error : colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text, {bool isError = false}) {
    final colorScheme = context.colorScheme;
    return Text(
      text,
      style: context.textTheme.labelMedium?.copyWith(
        color: isError ? colorScheme.error : colorScheme.primary,
      ),
    );
  }

  Widget _buildBody() {
    final appLocalizations = context.appLocalizations;
    final colorScheme = context.colorScheme;
    if (_loadError != null) {
      return Text(
        userFacingErrorMessage(_loadError!, appLocalizations),
        style: context.textTheme.bodyMedium?.copyWith(color: colorScheme.error),
      );
    }
    final plan = _plan;
    if (plan == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CommonCircleLoading()),
      );
    }
    if (plan.isEmpty) {
      return Text(
        appLocalizations.generateRegionGroupsEmpty,
        style: context.textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          appLocalizations.generateRegionGroupsTip,
          style: context.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        if (plan.upserts.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildSectionLabel(appLocalizations.generateRegionGroupsPreview),
          for (final draft in plan.upserts)
            _buildRow(
              label: '${draft.region.emoji} ${draft.region.label}',
              action: draft.isUpdate
                  ? appLocalizations.update
                  : appLocalizations.create,
              count: draft.proxyNames.length,
            ),
        ],
        if (plan.unknownCount > 0) ...[
          const SizedBox(height: 16),
          _buildSectionLabel(appLocalizations.generateRegionGroupsUnknown),
          // 数量照报，动作写成「保留原样」—— 用户要的是「剩下的去哪了」的答案，
          // 只说「不会归组」而不给数字，他没法判断漏掉的多不多。
          _buildRow(
            label: '${ProxyRegion.unknown.emoji} ${appLocalizations.other}',
            action: appLocalizations.generateRegionGroupsKeep,
            count: plan.unknownCount,
          ),
        ],
        if (plan.removals.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildSectionLabel(
            appLocalizations.generateRegionGroupsRemoveTip,
            isError: true,
          ),
          for (final name in plan.removals)
            _buildRow(
              label: name,
              action: appLocalizations.remove,
              isRemoval: true,
            ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final plan = _plan;
    final canApply = plan != null && !plan.isEmpty;
    return AdaptiveSheetScaffold(
      sheetTransparentToolBar: true,
      actions: [
        // 没算出计划、或没什么可做的，就不给这颗 ✓ —— 点了也不会有任何变化。
        if (canApply)
          IconButtonData(
            icon: Icons.check,
            tooltip: appLocalizations.generateRegionGroups,
            // `IconButtonData.onPressed` 不接受 null，重复点击靠 `_applying` 自己挡。
            onPressed: _handleApply,
          ),
      ],
      body: SizedBox(
        height: ref.sheetHeight(context, 0.7),
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
          ).copyWith(top: context.sheetTopPadding, bottom: 20),
          children: [_buildBody()],
        ),
      ),
      title: appLocalizations.generateRegionGroups,
    );
  }
}
