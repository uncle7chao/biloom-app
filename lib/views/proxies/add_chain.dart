import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 「添加链式代理」面板。
///
/// **链式代理是一个独立节点，且不写进任何配置文件**（2026-09-25 模型定稿）：
/// 提交后存进数据层（[ProxyChainStore]），组装运行时配置时注入 —— 一个链 =
/// 参数复制自出口、`dialer-proxy` 指向前置的新条目，统一收进固定的「链式代理」
/// 分组（永远显性、排在「自动选择」后面）。原始配置一个字节不动，订阅更新
/// 也冲不掉；出口/前置的参数快照随链保存，跨配置挑选不需要先复制。
/// 旧模型（把 dialer-proxy 写在出口身上）的「解除」入口保留，用于清理
/// 历史上直接挂在出口上的链。
///
/// 面板自己不做任何 YAML 解析：候选名单交给内核，写入交给数据层，Dart 侧
/// 永远不碰配置内容。
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

  /// 链的归属配置 = 打开面板时**当前生效**的那份（入口传进来，面板里不可换）。
  ///
  /// 曾经这里是可换的（目标配置下拉），独立节点模型落地后用户明确要求取消：
  /// 链是「跟着当前用的配置走」的东西，跨配置挑节点已经由候选列表里的
  /// 自动复制兜住，不需要再让用户先想清楚「存哪」再动手。
  int get _profileId => widget.profileId;

  /// 出口节点名 —— 链挂在它身上。
  String? _target;

  /// 出口来自哪份配置（null/等于 [_profileId] = 目标配置自己的）。
  /// 提交时按它去取出口的参数快照。
  int? _exitProfileId;

  /// 前置名 —— 可以是节点，也可以是策略组。
  String? _dialer;

  /// 前置来自哪份配置（含义同 [_exitProfileId]；策略组只会来自目标配置）。
  int? _dialerProfileId;

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
  ///
  /// **每一节都带配置名标题**——包括目标配置自己的那节。标题是用户理解
  /// 「这份名单从哪来」的唯一线索：全部平铺的话，配置之间的边界完全不可见，
  /// 看起来就是没做分节（用户实测原话：「界面并没有改？」）。
  List<_PickerSection> _buildExitSections() {
    final targets = _targets;
    if (targets == null) return const [];
    return [
      _PickerSection(
        label: _labelOf(_profileId),
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
    final ownLabel = _labelOf(_profileId);
    // 两类候选都在时，节标题必须各自带类型后缀 —— 只有一个「谷歌VPS」加一个
    // 「谷歌VPS · 节点」的话，用户看到的是两个谷歌VPS（2026-09-26 实测反馈），
    // 而不是「同一份配置的策略组与节点」。
    final hasNodes = targets.proxies.isNotEmpty;
    return [
      if (targets.groups.isNotEmpty)
        _PickerSection(
          label: hasNodes
              ? '$ownLabel · ${context.appLocalizations.proxyChainGroupsSection}'
              : ownLabel,
          items: targets.groups,
          subtitleOf: (item) => item.type,
          isGroups: true,
        ),
      _PickerSection(
        label: targets.groups.isEmpty
            ? ownLabel
            : '$ownLabel · ${context.appLocalizations.proxyChainNodesSection}',
        // 出口自己不能当前置，否则第一步就绕回自己身上。
        items: targets.proxies.where((item) => item.name != _target).toList(),
        subtitleOf: (item) => item.type,
      ),
      ..._buildForeignSections(),
    ];
  }

  /// 配置的显示名 —— id 不在列表里（刚被删）时退 id 字符串占位。
  String _labelOf(int profileId) {
    for (final profile in ref.read(profilesProvider)) {
      if (profile.id == profileId) return profile.realLabel;
    }
    return '$profileId';
  }

  /// 其他配置的节点，一份配置一节，节标题就是配置名。
  List<_PickerSection> _buildForeignSections() {
    final sections = <_PickerSection>[];
    for (final entry in _foreignTargets.entries) {
      if (entry.value.proxies.isEmpty) continue;
      sections.add(
        _PickerSection(
          label: _labelOf(entry.key),
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
  /// 链不落配置文件（模型见 proxy_chains.dart），所以选中**只记名字与来源**：
  /// 出口/前置来自哪份配置、提交时好取那边的参数快照。跨配置不再需要先复制
  /// —— 注入时快照直接进运行时配置，原始文件一个字节不动。
  Future<void> _adoptPicked(
    _PickedItem picked, {
    required bool isDialer,
  }) async {
    if (isDialer) {
      setState(() {
        _dialer = picked.name;
        _dialerProfileId = picked.profileId ?? _profileId;
      });
      return;
    }
    // 把该节点**已有的链**带出来。不这么做的话，选一个已经挂过链的节点会
    // 显示「已有前置：X」，但内部 _dialer 还是空的，用户按 ✓ 会被自己的
    // 校验拦下（「请选择前置代理」）—— 明明屏幕上写着有前置。只有目标配置
    // 自己的节点有这份信息；外部节点的前置在它自己的配置里，注入时会被剥掉。
    final existing = _existingDialerOf(picked.name);
    setState(() {
      _target = picked.name;
      _exitProfileId = picked.profileId ?? _profileId;
      // 前置与出口不能是同一个，旧值正好撞上新出口时清掉。
      _dialer = existing == picked.name ? null : existing;
      _dialerProfileId = null;
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

  /// 某份配置的候选里按名找节点的完整参数（快照用）。找不到返回 null
  /// （策略组、或这份配置的名单还没加载出来）。
  Map<String, dynamic>? _snapshotNodeOf(int? profileId, String name) {
    final targets =
        profileId == null || profileId == _profileId
        ? _targets
        : _foreignTargets[profileId];
    for (final node in targets?.nodes ?? const <Map<String, dynamic>>[]) {
      if (node['name'] == name) {
        return node;
      }
    }
    return null;
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
    // 名称规则：空着或仍是默认值 → 默认名路径（链式代理1、链式代理2 …
    // 编号取已占用最大编号 +1）；用户改过名 → 原样使用、不加数字（与配置或
    // 既有链撞名时数据层 -2 兜底）。页签名由运行时注入固定生成，不在这里管。
    final defaultName = appLocalizations.proxyChainDefaultName;
    final rawName = _nameController.text.trim();
    final isDefault = rawName.isEmpty || rawName == defaultName;
    // 参数快照：出口与前置（是节点时）各存一份 —— 链不落配置文件，运行时
    // 全靠这份快照 + 实时解析撑着（实时优先，快照兜底，见 proxy_chains.dart）。
    final exitSnapshot = _snapshotNodeOf(_exitProfileId, target);
    if (exitSnapshot == null) {
      // 名单没加载出来或节点刚被删 —— 没有快照的链是悬空的，拦在提交前。
      _showMessage(appLocalizations.proxyChainPickExit);
      return;
    }
    final dialerSnapshot = _snapshotNodeOf(_dialerProfileId, dialer);
    final finalName = await ref
        .read(profilesActionProvider.notifier)
        .addProxyChainOnProfile(
          profileId: _profileId,
          exit: target,
          exitNode: exitSnapshot,
          dialer: dialer,
          dialerNode: dialerSnapshot,
          name: isDefault ? defaultName : rawName,
          autoNumber: isDefault,
        );
    if (!mounted) return;
    if (finalName == null) {
      // 失败已由统一提示通道弹出 toast（出口/前置不存在等校验），
      // 面板留在原地让用户改完再提交。
      return;
    }
    _showMessage(appLocalizations.proxyChainCreated(finalName));
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

  /// 这节装的是策略组而不是节点。地区芯片筛「节点」时组不该被吞掉 ——
  /// 组没有出口地区可言，单独归到「策略组」芯片下。
  final bool isGroups;

  const _PickerSection({
    required this.label,
    required this.items,
    required this.subtitleOf,
    this.profileId,
    this.isGroups = false,
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
/// 候选**只直接展示每份配置里测速最快的前 20 个节点** —— 机场动辄两三百条，
/// 全罗列就是灾难；20 个之外的靠搜索定位，而搜索是在**全部候选**里跑的，
/// 不受上限约束。排序用测速数据（多次测速取最小值，没测过/失败的按配置原序
/// 排在有成绩的后面）；策略组数量少，不设上限。分组与节点仍按配置分节显示
/// —— 名字可能一样（Clash 里它们共用命名空间，实际上不会重名），但**含义
/// 差别很大**，混在一起用户分不清自己选的是一次跳转还是一个池子。
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

  /// 每份配置最多直接展示的节点数 —— 最快的前这些个，其余交给搜索。
  static const _maxShownPerConfig = 20;

  /// 被收起的分节（按下标）。默认全部展开；点节头切换。搜索时忽略折叠
  /// —— 搜索的目的就是把藏在下面的节点找出来，折叠态不能拦结果。
  final Set<int> _collapsedSections = {};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 一个节点的最优延迟：多次测速（多个测试地址）取最小值；没测过或失败
  /// 返回 -1。延迟数据按名字全局存，当前生效配置之外的节点一般没成绩 ——
  /// 它们按配置原序排在有成绩的节点后面，顺序依旧稳定。
  int _bestDelayOf(String name, DelayMap delays) {
    var best = -1;
    for (final urlMap in delays.values) {
      final value = urlMap[name];
      if (value != null && value > 0 && (best < 0 || value < best)) {
        best = value;
      }
    }
    return best;
  }

  /// 未搜索时的展示名单：节点节截到最快的前 [_maxShownPerConfig] 个。
  ///
  /// `List.sort` 不稳定，所以拿「原下标」做并列裁决 —— 同延迟/都没成绩时
  /// 保持配置原序，列表不会因为重排而跳动。
  _PickerSection _capSection(_PickerSection section, DelayMap delays) {
    if (section.isGroups || section.items.length <= _maxShownPerConfig) {
      return section;
    }
    final indexed = section.items.indexed.toList();
    indexed.sort((a, b) {
      final da = _bestDelayOf(a.$2.name, delays);
      final db = _bestDelayOf(b.$2.name, delays);
      if (da < 0 && db < 0) return a.$1 - b.$1;
      if (da < 0) return 1;
      if (db < 0) return -1;
      if (da != db) return da - db;
      return a.$1 - b.$1;
    });
    return _PickerSection(
      label: section.label,
      items: indexed.take(_maxShownPerConfig).map((entry) => entry.$2).toList(),
      subtitleOf: section.subtitleOf,
      profileId: section.profileId,
    );
  }

  /// 有没有任何节点节被截断 —— 决定搜索框下那行提示显不显示。
  bool get _anyCapped => widget.sections.any(
        (section) => !section.isGroups && section.items.length > _maxShownPerConfig,
      );

  List<_PickerSection> get _filtered {
    final keyword = _controller.text.trim().toLowerCase();
    if (keyword.isEmpty) {
      final delays = ref.watch(delayDataSourceProvider);
      return widget.sections
          .map((section) => _capSection(section, delays))
          .where((section) => section.items.isNotEmpty)
          .toList();
    }
    // 搜索跑在**全部候选**上 —— 20 上限只管默认展示，不能把节点藏没了。
    return widget.sections
        .map(
          (section) => _PickerSection(
            label: section.label,
            items: section.items
                .where((item) => item.name.toLowerCase().contains(keyword))
                .toList(),
            subtitleOf: section.subtitleOf,
            profileId: section.profileId,
            isGroups: section.isGroups,
          ),
        )
        .where((section) => section.items.isNotEmpty)
        .toList();
  }

  /// 可折叠的分节头：配置名 + 节点数 + 展开箭头。点一下收起/展开该节。
  ///
  /// 节头必须「看起来能点」——箭头随折叠态旋转（收起时指向右），数量告诉
  /// 用户收起来的是什么规模的名单。
  Widget _buildSectionHeader(
    _PickerSection section,
    int index,
    bool searching,
  ) {
    final collapsed = !searching && _collapsedSections.contains(index);
    return InkWell(
      onTap: searching
          ? null
          : () => setState(() {
              collapsed
                  ? _collapsedSections.remove(index)
                  : _collapsedSections.add(index);
            }),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                section.label,
                style: context.textTheme.titleSmall?.copyWith(
                  color: context.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '${section.items.length}',
              style: context.textTheme.labelSmall?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 4),
            AnimatedRotation(
              turns: collapsed ? -0.25 : 0,
              duration: const Duration(milliseconds: 150),
              child: Icon(
                Icons.expand_more,
                size: 20,
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sections = _filtered;
    final searching = _controller.text.trim().isNotEmpty;
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
            // 提示行只在不搜索且有节被截断时出现 —— 搜的时候用户已经知道
            // 有搜索这回事了，常驻反而占地方。
            if (_controller.text.trim().isEmpty && _anyCapped)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  context.appLocalizations.proxyChainPickerTopHint,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
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
                        for (final (index, section) in sections.indexed) ...[
                          if (section.label.isNotEmpty)
                            _buildSectionHeader(section, index, searching),
                          // 搜索时无视折叠态：结果是找出来的，不是翻出来的。
                          if (searching || !_collapsedSections.contains(index))
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

