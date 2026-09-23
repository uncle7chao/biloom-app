import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 「意图分组」面板 —— 勾选要生成的意图，看清规则与成员，再应用。
///
/// 与「按地区生成分组」面板（`region_groups.dart`）同一套交互契约：
/// 计划在面板里**现算**（只读），用户看完直接关掉没有任何副作用；调用方
/// 负责先把配置切到「自定义覆写」模式，否则写进去的东西不生效。
///
/// 每个意图一行：勾选 = 生成/更新（组 + 若干条 GEOSITE 规则，规则插到
/// 订阅规则最前）；取消勾选一个已生成的意图 = 连组带规则一起删掉。
class IntentGroupPlanView extends ConsumerStatefulWidget {
  final int profileId;

  const IntentGroupPlanView({super.key, required this.profileId});

  @override
  ConsumerState<IntentGroupPlanView> createState() =>
      _IntentGroupPlanViewState();
}

class _IntentGroupPlanViewState extends ConsumerState<IntentGroupPlanView> {
  final _enabled = <IntentKey>{};
  IntentGroupPlan? _plan;
  Object? _loadError;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    // 默认全选：这个面板是用户主动点进来的，意图就是「全给我配上」，
    // 不想要的取消勾选比一个个勾上省事。
    _enabled.addAll(intentTemplates.map((template) => template.key));
    _load();
  }

  Future<void> _load() async {
    try {
      final plan = await ref
          .read(profilesActionProvider.notifier)
          .readIntentGroupPlan(widget.profileId, {..._enabled});
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

  Future<void> _toggle(IntentKey key) async {
    if (!_enabled.add(key) && !_enabled.remove(key)) {
      return;
    }
    setState(() => _plan = null);
    await _load();
  }

  Future<void> _handleApply() async {
    final plan = _plan;
    if (plan == null || _applying) {
      return;
    }
    setState(() => _applying = true);
    final appLocalizations = context.appLocalizations;
    final int skipped;
    try {
      skipped = await ref
          .read(profilesActionProvider.notifier)
          .applyIntentGroupPlan(widget.profileId, plan);
    } finally {
      if (mounted) {
        setState(() => _applying = false);
      }
    }
    if (!mounted) {
      return;
    }
    final lines = <String>[
      appLocalizations.intentGroupsDone,
      '',
      for (final draft in plan.upserts)
        '${draft.emoji} ${draft.name}   '
            '${draft.members.length}   '
            '${draft.isUpdate ? appLocalizations.update : appLocalizations.create}',
      for (final name in plan.removals) '$name   ${appLocalizations.remove}',
      if (skipped > 0) '',
      if (skipped > 0) appLocalizations.proxyGroupNameDuplicate,
    ];
    Navigator.of(context).pop();
    await dialogs.showMessage(
      message: TextSpan(text: lines.join('\n')),
      cancelable: false,
    );
  }

  Widget _buildRow(IntentTemplate template) {
    final appLocalizations = context.appLocalizations;
    final colorScheme = context.colorScheme;
    final checked = _enabled.contains(template.key);
    // 未勾选的意图不在计划里（计划只含要写的东西），名字就地用模板现拼。
    final draft = _plan?.upserts.firstWhere(
      (item) => item.key == template.key,
      orElse: () => IntentGroupDraft(
        key: template.key,
        emoji: template.emoji,
        name: '${template.emoji} ${_labelOf(template)}',
        members: const [],
        categories: template.categories,
        isUpdate: false,
      ),
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Checkbox(
                value: checked,
                onChanged: _applying ? null : (_) => _toggle(template.key),
              ),
              const SizedBox(width: 8),
              Text(template.emoji, style: context.textTheme.titleMedium),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      draft!.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.titleMedium?.toSoftBold,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${template.categories.join(' / ')}   ·   '
                      '${draft.members.length}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                draft.isUpdate
                    ? appLocalizations.update
                    : appLocalizations.create,
                style: context.textTheme.labelLarge?.copyWith(
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 0),
      ],
    );
  }

  String _labelOf(IntentTemplate template) {
    final appLocalizations = context.appLocalizations;
    return switch (template.key) {
      IntentKey.streaming => appLocalizations.intentStreaming,
      IntentKey.ai => appLocalizations.intentAi,
      IntentKey.social => appLocalizations.intentSocial,
    };
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    Widget body;
    if (_loadError != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('$_loadError'),
        ),
      );
    } else if (_plan == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              appLocalizations.intentGroupsTip,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final template in intentTemplates) _buildRow(template),
        ],
      );
    }
    return AdaptiveSheetScaffold(
      title: appLocalizations.intentGroups,
      actions: [
        // 没算出计划、或没什么可做的，就不给这颗 ✓ —— 点了也不会有任何变化。
        if (_plan != null && !_applying && _plan!.upserts.isNotEmpty)
          IconButtonData(
            icon: Icons.check,
            tooltip: appLocalizations.save,
            onPressed: _handleApply,
          ),
      ],
      body: body,
    );
  }
}
