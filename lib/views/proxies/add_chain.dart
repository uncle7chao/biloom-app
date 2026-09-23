import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 「添加链式代理」面板。
///
/// **为什么链式代理是一张「出口 + 前置」的表单，而不是一个策略组类型**：
/// FlClash 上游的策略组编辑器里确实有一个 `relay` 类型，但本内核已经把它删掉了
/// （`Clash.Meta/adapter/outboundgroup/parser.go:216` 对它返回错误），存进去会让
/// **整份配置加载失败**。现在的做法是代理级的 `dialer-proxy` 字段：写在出口节点上，
/// 值可以是另一个节点、也可以是一个策略组名。所以这个面板只需要两件事 ——
/// 「哪个节点做出口」和「先经过谁」，链的方向是 `前置 → 出口 → 目标`。
///
/// 面板自己不做任何 YAML 解析：候选名单与写入都交给内核，Dart 侧永远不碰配置内容。
class AddProxyChainView extends ConsumerStatefulWidget {
  final int profileId;

  const AddProxyChainView({super.key, required this.profileId});

  @override
  ConsumerState<AddProxyChainView> createState() => _AddProxyChainViewState();
}

class _AddProxyChainViewState extends ConsumerState<AddProxyChainView> {
  ProfileTargets? _targets;
  Object? _loadError;

  /// 出口节点名 —— 链挂在它身上。
  String? _target;

  /// 前置名 —— 可以是节点，也可以是策略组。
  String? _dialer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 这份配置是不是订阅来的。
  ///
  /// 与「新增节点」是同一个问题：链写在配置正文里，订阅更新会整份覆盖。所以提示
  /// 与「转为本地配置」的出口要一并给到 —— 链式代理通常是一次设好长期不动的，
  /// 转为本地配置对它比新增节点更自然。
  bool get _isSubscription =>
      (ref.read(profileProvider(widget.profileId))?.url ?? '').isNotEmpty;

  Future<void> _load() async {
    try {
      final targets = await ref
          .read(profilesActionProvider.notifier)
          .readProfileTargets(widget.profileId);
      if (!mounted) return;
      setState(() {
        _targets = targets;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error);
    }
  }

  /// 当前出口节点上已有的链，用来把「改」和「解除」分清楚。
  String get _existingDialer {
    final target = _target;
    if (target == null) return '';
    for (final item in _targets?.proxies ?? const <ProfileTarget>[]) {
      if (item.name == target) {
        return item.dialer;
      }
    }
    return '';
  }

  Future<void> _handlePickTarget() async {
    final proxies = _targets?.proxies ?? const <ProfileTarget>[];
    final picked = await _showPicker(
      title: context.appLocalizations.proxyChainPickExit,
      sections: [
        _PickerSection(
          label: '',
          items: proxies,
          // 出口是「要被挂上前置」的那一个，所以这里显示它现有的链。
          subtitleOf: (item) => item.dialer.isEmpty
              ? item.type
              : '${item.type} · '
                    '${context.appLocalizations.proxyChainExisting(item.dialer)}',
        ),
      ],
      selected: _target,
      emptyLabel: context.appLocalizations.proxyChainNoNodes,
    );
    if (picked == null || !mounted) return;
    // 把该节点**已有的链**带出来。不这么做的话，选一个已经挂过链的节点会显示
    // 「已有前置：X」，但内部 _dialer 还是空的，用户按 ✓ 会被自己的校验拦下
    // （「请选择前置代理」）—— 明明屏幕上写着有前置。
    String existing = '';
    for (final item in proxies) {
      if (item.name == picked) {
        existing = item.dialer;
      }
    }
    setState(() {
      _target = picked;
      // 前置与出口不能是同一个，旧值正好撞上新出口时清掉。
      _dialer = existing == picked ? null : existing;
    });
  }

  Future<void> _handlePickDialer() async {
    final targets = _targets;
    if (targets == null) return;
    final picked = await _showPicker(
      title: context.appLocalizations.proxyChainPickFront,
      sections: [
        if (targets.groups.isNotEmpty)
          _PickerSection(
            label: context.appLocalizations.proxyChainGroupsSection,
            items: targets.groups,
            subtitleOf: (item) => item.type,
          ),
        _PickerSection(
          label: targets.groups.isEmpty
              ? ''
              : context.appLocalizations.proxyChainNodesSection,
          // 出口自己不能当前置，否则第一步就绕回自己身上。
          items: targets.proxies
              .where((item) => item.name != _target)
              .toList(),
          subtitleOf: (item) => item.type,
        ),
      ],
      selected: _dialer,
      emptyLabel: context.appLocalizations.proxyChainNoNodes,
    );
    if (picked == null || !mounted) return;
    setState(() => _dialer = picked);
  }

  Future<void> _handleSubmit() async {
    final appLocalizations = context.appLocalizations;
    final target = _target;
    if (target == null) {
      _showMessage(appLocalizations.proxyChainPickExit);
      return;
    }
    final dialer = _dialer;
    if (dialer == null) {
      _showMessage(appLocalizations.proxyChainPickFront);
      return;
    }
    await _writeChain(target: target, dialer: dialer);
  }

  Future<void> _handleClear() async {
    final target = _target;
    if (target == null) return;
    await _writeChain(target: target, dialer: '');
  }

  Future<void> _writeChain({
    required String target,
    required String dialer,
  }) async {
    final appLocalizations = context.appLocalizations;
    await ref
        .read(profilesActionProvider.notifier)
        .setProxyChainOnProfile(
          profileId: widget.profileId,
          target: target,
          dialer: dialer,
        );
    if (!mounted) return;
    _showMessage(
      dialer.isEmpty
          ? appLocalizations.proxyChainCleared
          : appLocalizations.proxyChainSaved(dialer, target),
    );
    Navigator.of(context).pop();
  }

  Future<void> _handleConvertToLocal() async {
    final url = ref.read(profileProvider(widget.profileId))?.url ?? '';
    final confirmed = await dialogs.showMessage(
      // 把订阅链接原文一并显示：断开之后它就没了，让用户有机会先记下来。
      message: TextSpan(
        text: '${context.appLocalizations.convertToLocalProfileDesc}\n\n$url',
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref
        .read(profilesActionProvider.notifier)
        .convertProfileToLocal(widget.profileId);
    if (!mounted) return;
    _showMessage(context.appLocalizations.profileConvertedToLocal);
    setState(() {});
  }

  void _showMessage(String text) {
    dialogs.showMessage(message: TextSpan(text: text), cancelable: false);
  }

  Future<String?> _showPicker({
    required String title,
    required List<_PickerSection> sections,
    required String? selected,
    required String emptyLabel,
  }) {
    return Navigator.of(context).push<String>(
      PagedSheetRoute(
        builder: (context) => _TargetPickerView(
          title: title,
          sections: sections,
          selected: selected,
          emptyLabel: emptyLabel,
        ),
      ),
    );
  }

  Widget _buildSubscriptionNotice() {
    final appLocalizations = context.appLocalizations;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card.filled(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: context.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      appLocalizations.subscribeOverwriteWarning,
                      style: context.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _handleConvertToLocal,
                  child: Text(appLocalizations.convertToLocalProfile),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 一行「标签 + 当前值 + 进入选择」。
  ///
  /// 刻意不只显示选中的名字：**没选**的时候也要说清楚该选什么（[hint]），否则
  /// 用户看到两个空行不知道从哪下手。
  Widget _buildRow({
    required String label,
    required String hint,
    required String? value,
    required VoidCallback onPressed,
  }) {
    final colorScheme = context.colorScheme;
    return Card.outlined(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onPressed,
        contentPadding: const EdgeInsets.only(left: 16, right: 12),
        title: Text(label, style: context.textTheme.titleSmall),
        subtitle: Text(
          value ?? hint,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.textTheme.bodySmall?.copyWith(
            color: value == null
                ? colorScheme.onSurfaceVariant
                : colorScheme.primary,
          ),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      ),
    );
  }

  Widget _buildBody() {
    final appLocalizations = context.appLocalizations;
    final targets = _targets;
    if (_loadError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          userFacingErrorMessage(_loadError!, appLocalizations),
          style: context.textTheme.bodyMedium?.copyWith(
            color: context.colorScheme.error,
          ),
        ),
      );
    }
    if (targets == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CommonCircleLoading()),
      );
    }
    if (targets.proxies.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          appLocalizations.proxyChainNoNodes,
          style: context.textTheme.bodyMedium?.copyWith(
            color: context.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    final existing = _existingDialer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            appLocalizations.addProxyChainDesc,
            style: context.textTheme.bodySmall?.copyWith(
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        _buildRow(
          label: appLocalizations.proxyChainExit,
          hint: appLocalizations.proxyChainExitHint,
          value: _target,
          onPressed: _handlePickTarget,
        ),
        _buildRow(
          label: appLocalizations.proxyChainFront,
          hint: appLocalizations.proxyChainFrontHint,
          value: _dialer,
          onPressed: _handlePickDialer,
        ),
        // 只有这个节点本来就有链，才有「解除」这回事。新设一条链不需要先解除。
        if (existing.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _handleClear,
              icon: const Icon(Icons.link_off, size: 18),
              label: Text(appLocalizations.proxyChainClear),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final height = ref.sheetHeight(context, 0.6);
    return AdaptiveSheetScaffold(
      sheetTransparentToolBar: true,
      actions: [
        IconButtonData(
          icon: Icons.check,
          onPressed: _handleSubmit,
          tooltip: appLocalizations.submit,
        ),
      ],
      body: SizedBox(
        height: height,
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
          ).copyWith(top: context.sheetTopPadding, bottom: 20),
          children: [
            if (_isSubscription) _buildSubscriptionNotice(),
            _buildBody(),
          ],
        ),
      ),
      title: appLocalizations.addProxyChain,
    );
  }
}

/// 选择器里的一组候选。
class _PickerSection {
  final String label;
  final List<ProfileTarget> items;
  final String Function(ProfileTarget item) subtitleOf;

  const _PickerSection({
    required this.label,
    required this.items,
    required this.subtitleOf,
  });
}

/// 单项选择面板。
///
/// 带搜索：机场的节点动辄几百条，纯靠滚动找某一条是不现实的。分组与节点分节显示 ——
/// 名字可能一样（Clash 里它们共用命名空间，实际上不会重名），但**含义差别很大**，
/// 混在一起用户分不清自己选的是一次跳转还是一个池子。
class _TargetPickerView extends ConsumerStatefulWidget {
  final String title;
  final List<_PickerSection> sections;
  final String? selected;
  final String emptyLabel;

  const _TargetPickerView({
    required this.title,
    required this.sections,
    required this.selected,
    required this.emptyLabel,
  });

  @override
  ConsumerState<_TargetPickerView> createState() => _TargetPickerViewState();
}

class _TargetPickerViewState extends ConsumerState<_TargetPickerView> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<_PickerSection> get _filtered {
    final keyword = _controller.text.trim().toLowerCase();
    if (keyword.isEmpty) return widget.sections;
    return widget.sections
        .map(
          (section) => _PickerSection(
            label: section.label,
            items: section.items
                .where((item) => item.name.toLowerCase().contains(keyword))
                .toList(),
            subtitleOf: section.subtitleOf,
          ),
        )
        .where((section) => section.items.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final sections = _filtered;
    return AdaptiveSheetScaffold(
      sheetTransparentToolBar: true,
      body: SizedBox(
        height: ref.sheetHeight(context, 0.7),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _controller,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: context.appLocalizations.search,
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: sections.isEmpty
                  ? Center(
                      child: Text(
                        // 两种空要分开说：搜不到是「换个词」，没有候选是「这份配置
                        // 没东西可挑」—— 用同一句话会让用户以为配置坏了。
                        _controller.text.trim().isNotEmpty
                            ? context.appLocalizations.noData
                            : widget.emptyLabel,
                        textAlign: TextAlign.center,
                        style: context.textTheme.bodyMedium?.copyWith(
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 20),
                      children: [
                        for (final section in sections) ...[
                          if (section.label.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                              child: Text(
                                section.label,
                                style: context.textTheme.labelMedium?.copyWith(
                                  color: context.colorScheme.primary,
                                ),
                              ),
                            ),
                          for (final item in section.items)
                            ListTile(
                              onTap: () {
                                Navigator.of(context).pop(item.name);
                              },
                              contentPadding: const EdgeInsets.only(
                                left: 16,
                                right: 12,
                              ),
                              title: Text(
                                item.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(section.subtitleOf(item)),
                              trailing: item.name == widget.selected
                                  ? Icon(
                                      Icons.check,
                                      color: context.colorScheme.primary,
                                    )
                                  : null,
                            ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
      title: widget.title,
    );
  }
}
