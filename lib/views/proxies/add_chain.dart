import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 「添加链式代理」面板。
///
/// **链式代理是一个独立节点**（2026-09-25 模型定稿）：提交后生成一个新 proxy
/// 条目 —— 参数复制自出口、`dialer-proxy` 指向前置、名字独立（默认名
/// 「链式代理」自动编号），并统一收进「链式代理」分组，代理页里就是一个
/// 独立页签。原出口节点保持不动；旧模型（把 dialer-proxy 写在出口身上）
/// 的「解除」入口保留，用于清理历史上直接挂在出口上的链。
///
/// 面板自己不做任何 YAML 解析：候选名单、复制与写入都交给内核，Dart 侧永远
/// 不碰配置内容。
class AddProxyChainView extends ConsumerStatefulWidget {
  final int profileId;

  const AddProxyChainView({super.key, required this.profileId});

  @override
  ConsumerState<AddProxyChainView> createState() => _AddProxyChainViewState();
}

class _AddProxyChainViewState extends ConsumerState<AddProxyChainView> {
  ProfileTargets? _targets;
  Object? _loadError;

  /// 其他配置的候选名单（跨配置挑选用）：profileId → 该配置的节点与分组。
  ///
  /// 面板打开时随主候选一起加载；某份配置读不了就跳过 —— 跨配置挑选是锦上
  /// 添花，不能因为它把整个面板拖垮。
  final Map<int, ProfileTargets> _foreignTargets = {};

  /// 目标配置：入口传进来的那份只是**默认值**，面板里可以随时换。
  ///
  /// 链写在配置正文里，候选名单也从这份配置读 —— 但「哪份配置」不该被
  /// 当前选中态绑死：出口在前一份配置、前置在另一份是正常诉求。
  /// 与「新增节点」面板的「目标配置」下拉同一套做法。
  late int _profileId = widget.profileId;

  /// 出口节点名 —— 链挂在它身上。
  String? _target;

  /// 前置名 —— 可以是节点，也可以是策略组。
  String? _dialer;

  /// 链式代理名称输入框。默认值是「链式代理」（[defaultChainName]）：
  /// 用默认名提交时按 链式代理1、链式代理2 … 自动编号；改过名就原样使用、
  /// 不加数字。每次打开面板都回到默认值。
  final _nameController = TextEditingController();

  bool _nameInitialized = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_nameInitialized) {
      _nameInitialized = true;
      _nameController.text = context.appLocalizations.proxyChainDefaultName;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// 这份配置是不是订阅来的。
  ///
  /// 与「新增节点」是同一个问题：链写在配置正文里，订阅更新会整份覆盖。所以提示
  /// 与「转为本地配置」的出口要一并给到 —— 链式代理通常是一次设好长期不动的，
  /// 转为本地配置对它比新增节点更自然。
  bool get _isSubscription =>
      (ref.read(profileProvider(_profileId))?.url ?? '').isNotEmpty;

  Future<void> _load() async {
    if (!await _loadTargets()) return;
    unawaited(_loadForeign());
  }

  /// 加载当前目标配置的候选名单。失败时把错误挂到 [_loadError] 并返回 false。
  Future<bool> _loadTargets() async {
    try {
      final targets = await ref
          .read(profilesActionProvider.notifier)
          .readProfileTargets(_profileId);
      if (!mounted) return false;
      setState(() {
        _targets = targets;
        _loadError = null;
      });
      return true;
    } catch (error) {
      if (!mounted) return false;
      setState(() => _loadError = error);
      return false;
    }
  }

  /// 加载其他配置的候选名单 —— 跨配置挑选的池子。
  Future<void> _loadForeign() async {
    for (final profile in ref.read(profilesProvider)) {
      if (profile.id == _profileId) continue;
      if (_foreignTargets.containsKey(profile.id)) continue;
      try {
        final targets = await ref
            .read(profilesActionProvider.notifier)
            .readProfileTargets(profile.id);
        if (!mounted) return;
        setState(() => _foreignTargets[profile.id] = targets);
      } catch (_) {
        // 这份配置暂时读不了（比如正在更新），跳过即可。
      }
    }
  }

  /// 目标配置选择器：入口默认选中传进来的那份，可手动换成任何一份配置。
  ///
  /// 换配置必须把**已选的出口/前置一并清掉** —— 名字只在自己那份配置里有意义，
  /// 带着旧配置里挑的名字去新配置提交，要么找不到、要么撞上同名但完全不同的节点。
  Widget _buildProfileSelector() {
    final appLocalizations = context.appLocalizations;
    final profiles = ref.watch(profilesProvider);
    // 选中值失效（配置刚被删）时回退到列表第一份，避免下拉出现悬空选中。
    final validIds = profiles.map((profile) => profile.id).toSet();
    if (!validIds.contains(_profileId) && profiles.isNotEmpty) {
      _profileId = profiles.first.id;
    }
    return DropdownButtonFormField<int>(
      initialValue: _profileId,
      decoration: InputDecoration(
        labelText: appLocalizations.addNodeTargetProfile,
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.layers_outlined, size: 20),
      ),
      items: profiles
          .map(
            (profile) => DropdownMenuItem(
              value: profile.id,
              child: Text(profile.label, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value == null || value == _profileId) return;
        // 旧目标配置的候选还有用 —— 它现在是「其他配置」之一；新目标的缓存
        // 清掉重新读，它的节点可能刚被别处改过。
        final oldTargets = _targets;
        setState(() {
          if (oldTargets != null) {
            _foreignTargets[_profileId] = oldTargets;
          }
          _foreignTargets.remove(value);
          _profileId = value;
          _targets = null;
          _loadError = null;
          _target = null;
          _dialer = null;
        });
        _load();
      },
    );
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

  /// 出口候选：目标配置的节点 + 其他配置的节点。出口必须是节点，没有组。
  List<_PickerSection> _buildExitSections() {
    final targets = _targets;
    if (targets == null) return const [];
    return [
      _PickerSection(
        label: '',
        items: targets.proxies,
        // 出口是「要被挂上前置」的那一个，所以这里显示它现有的链。
        subtitleOf: (item) => item.dialer.isEmpty
            ? item.type
            : '${item.type} · '
                  '${context.appLocalizations.proxyChainExisting(item.dialer)}',
      ),
      ..._buildForeignSections(),
    ];
  }

  /// 前置候选：目标配置的分组与节点 + 其他配置的节点。
  ///
  /// 跨配置只开放**节点**：策略组的成员名单跨配置复制会把组员连锁带过去，
  /// 组员又可能在目标配置里不存在 —— 那是递归的坑，第一版不碰。
  List<_PickerSection> _buildDialerSections() {
    final targets = _targets;
    if (targets == null) return const [];
    return [
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
        items: targets.proxies.where((item) => item.name != _target).toList(),
        subtitleOf: (item) => item.type,
      ),
      ..._buildForeignSections(),
    ];
  }

  /// 其他配置的节点，一份配置一节，节标题就是配置名。
  List<_PickerSection> _buildForeignSections() {
    final labelOf = {
      for (final profile in ref.read(profilesProvider))
        profile.id: profile.realLabel,
    };
    final sections = <_PickerSection>[];
    for (final entry in _foreignTargets.entries) {
      if (entry.value.proxies.isEmpty) continue;
      sections.add(
        _PickerSection(
          label: labelOf[entry.key] ?? '',
          items: entry.value.proxies,
          profileId: entry.key,
          subtitleOf: (item) => item.type,
        ),
      );
    }
    return sections;
  }

  Future<void> _handlePickTarget() async {
    final picked = await _showPicker(
      title: context.appLocalizations.proxyChainPickExit,
      sections: _buildExitSections(),
      selected: _target,
      emptyLabel: context.appLocalizations.proxyChainNoNodes,
    );
    if (picked == null || !mounted) return;
    await _adoptPicked(picked, isDialer: false);
  }

  Future<void> _handlePickDialer() async {
    final picked = await _showPicker(
      title: context.appLocalizations.proxyChainPickFront,
      sections: _buildDialerSections(),
      selected: _dialer,
      emptyLabel: context.appLocalizations.proxyChainNoNodes,
    );
    if (picked == null || !mounted) return;
    await _adoptPicked(picked, isDialer: true);
  }

  /// 选中候选后的落地。
  ///
  /// 目标配置自己的名字直接用；**其他配置**的名字先把节点复制进目标配置
  /// （内核剥 dialer-proxy、重名自动改名、身份相同直接复用），再用**最终名**
  /// 落选中值 —— 链引用的是复制体，不是来源配置里的原名。
  Future<void> _adoptPicked(
    _PickedItem picked, {
    required bool isDialer,
  }) async {
    final targetId = _profileId;
    if (picked.profileId == null || picked.profileId == targetId) {
      if (isDialer) {
        setState(() => _dialer = picked.name);
        return;
      }
      // 把该节点**已有的链**带出来。不这么做的话，选一个已经挂过链的节点会
      // 显示「已有前置：X」，但内部 _dialer 还是空的，用户按 ✓ 会被自己的
      // 校验拦下（「请选择前置代理」）—— 明明屏幕上写着有前置。
      final existing = _existingDialerOf(picked.name);
      setState(() {
        _target = picked.name;
        // 前置与出口不能是同一个，旧值正好撞上新出口时清掉。
        _dialer = existing == picked.name ? null : existing;
      });
      return;
    }
    final result = await globalState.loadingRun(
      tag: LoadingTag.profiles,
      () => ref
          .read(profilesActionProvider.notifier)
          .copyProxyNodeBetweenProfiles(
            fromProfileId: picked.profileId!,
            toProfileId: targetId,
            name: picked.name,
          ),
    );
    if (!mounted || _profileId != targetId) return;
    if (result == null) {
      // 失败已由统一提示通道弹过 toast，面板留在原地。
      return;
    }
    context.showNotifier(
      result.reused
          ? context.appLocalizations.proxyChainNodeReused(result.name)
          : context.appLocalizations.proxyChainNodeCopied(result.name),
    );
    // 复制体要在本配置候选里可见（后续提交、解除都靠这份名单），重载一次；
    // 选中值在重载之后落。
    await _loadTargets();
    if (!mounted || _profileId != targetId) return;
    if (isDialer) {
      setState(() => _dialer = result.name);
      return;
    }
    final existing = _existingDialerOf(result.name);
    setState(() {
      _target = result.name;
      _dialer = existing == result.name ? null : existing;
    });
  }

  /// 目标配置里某个节点当前挂的前置名；没有则空串。
  String _existingDialerOf(String name) {
    for (final item in _targets?.proxies ?? const <ProfileTarget>[]) {
      if (item.name == name) {
        return item.dialer;
      }
    }
    return '';
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
    // 名称规则：空着或仍是默认值 → 默认名路径（内核按 链式代理1、链式代理2 …
    // 编号取空位）；用户改过名 → 原样使用、不加数字（被占用才 -2 兜底）。
    // 分组名与默认名是同一个词：所有链式代理都收进「链式代理」页签。
    final defaultName = appLocalizations.proxyChainDefaultName;
    final rawName = _nameController.text.trim();
    final isDefault = rawName.isEmpty || rawName == defaultName;
    final result = await ref
        .read(profilesActionProvider.notifier)
        .addProxyChainOnProfile(
          profileId: _profileId,
          exit: target,
          dialer: dialer,
          name: isDefault ? defaultName : rawName,
          autoNumber: isDefault,
          group: defaultName,
        );
    if (!mounted) return;
    if (result == null) {
      // 失败已由统一提示通道弹出 toast（出口/前置不存在、成环等内核校验），
      // 面板留在原地让用户改完再提交。
      return;
    }
    _showMessage(appLocalizations.proxyChainCreated(result.name));
    Navigator.of(context).pop();
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
          profileId: _profileId,
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
    final url = ref.read(profileProvider(_profileId))?.url ?? '';
    final confirmed = await dialogs.showMessage(
      // 把订阅链接原文一并显示：断开之后它就没了，让用户有机会先记下来。
      message: TextSpan(
        text: '${context.appLocalizations.convertToLocalProfileDesc}\n\n$url',
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref
        .read(profilesActionProvider.notifier)
        .convertProfileToLocal(_profileId);
    if (!mounted) return;
    _showMessage(context.appLocalizations.profileConvertedToLocal);
    setState(() {});
  }

  void _showMessage(String text) {
    dialogs.showMessage(message: TextSpan(text: text), cancelable: false);
  }

  /// ⛔ 这里**不能用 `PagedSheetRoute`**：它的 `buildPage` 会强制包一层
  /// `ResizableNavigatorRouteContentBoundary`，创建时向上找 `NavigatorResizable`
  /// 宿主，找不到就是空断言崩溃 —— 全项目唯一的宿主在覆写编辑器的嵌套 sheet 里
  /// （`overwrite_nested_sheet.dart` 的 `PagedSheet`）。从本面板直接推出去没有宿主，
  /// 推出去的整页就是空白（release 下无报错、无返回按钮，用户只会看到白屏）。
  /// 所以选择器改成再开一层自适应 sheet：桌面端是叠在侧滑上的第二层侧滑，
  /// 移动端是叠在底部弹层上的第二层弹层，都是模态路由，返回值照常拿到。
  Future<_PickedItem?> _showPicker({
    required String title,
    required List<_PickerSection> sections,
    required String? selected,
    required String emptyLabel,
  }) {
    return showSheet<_PickedItem>(
      context: context,
      props: const SheetProps(isScrollControlled: true),
      builder: (context) => _TargetPickerView(
        title: title,
        sections: sections,
        selected: selected,
        emptyLabel: emptyLabel,
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
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: appLocalizations.proxyChainNameLabel,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.label_outline, size: 20),
              isDense: true,
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
            _buildProfileSelector(),
            const SizedBox(height: 12),
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

  /// 候选所属的配置；null = 目标配置自己的（选中后无需复制）。
  final int? profileId;

  const _PickerSection({
    required this.label,
    required this.items,
    required this.subtitleOf,
    this.profileId,
  });
}

/// 选择器的返回值：名字 + 它来自哪份配置（null = 目标配置自己的）。
class _PickedItem {
  final String name;
  final int? profileId;

  const _PickedItem({required this.name, this.profileId});
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
            profileId: section.profileId,
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
            // 底部弹层的工具栏是透明的，搜索框必须让它出顶部空间；侧滑是
            // 普通AppBar，这里只会多 10px 呼吸感，两种形态都安全。
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                context.sheetTopPadding + 8,
                16,
                8,
              ),
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
                                Navigator.of(context).pop(
                                  _PickedItem(
                                    name: item.name,
                                    profileId: section.profileId,
                                  ),
                                );
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
