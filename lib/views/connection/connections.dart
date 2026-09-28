import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/method.dart';
import 'package:fl_clash/features/features.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ConnectionsView extends ConsumerStatefulWidget {
  final Future<List<TrackerInfo>> Function()? connectionsReader;

  const ConnectionsView({super.key, @visibleForTesting this.connectionsReader});

  @override
  ConsumerState<ConnectionsView> createState() => _ConnectionsViewState();
}

class _ConnectionsViewState extends ConsumerState<ConnectionsView>
    with WidgetsBindingObserver, ActivePollingMixin<ConnectionsView> {
  CoreController get _core => ref.read(coreHandlerProvider);

  final _listController = TrackerInfoListController();
  final ScrollController _scrollController = ScrollController();

  /// 最近一次内核快照（未筛选）—— 结构化筛选的选项与筛选都基于它。
  List<TrackerInfo> _snapshot = const [];

  /// 结构化筛选：进程 / 节点链 / 规则类型。null = 不过滤该维度。
  /// 与搜索关键词（keywords/query）独立，两层过滤叠加生效。
  String? _filterProcess;
  String? _filterChain;
  String? _filterRule;

  @override
  Duration get pollInterval => const Duration(seconds: 1);

  List<Widget> _buildActions() {
    return [
      IconButton(
        tooltip: context.appLocalizations.closeConnections,
        onPressed: () async {
          unawaited(_core.closeConnections());
          await _refreshConnections();
        },
        icon: const Icon(Icons.delete_sweep_outlined),
      ),
    ];
  }

  @override
  Future<void> poll(PollGuard isCurrent) async {
    final trackerInfos = await _readConnections();
    if (trackerInfos == null || !isCurrent()) {
      return;
    }
    _applyConnections(trackerInfos);
  }

  Future<void> _refreshConnections() async {
    final trackerInfos = await _readConnections();
    if (trackerInfos == null || !mounted) {
      return;
    }
    _applyConnections(trackerInfos);
  }

  Future<List<TrackerInfo>?> _readConnections() async {
    try {
      final connectionsReader = widget.connectionsReader;
      return connectionsReader != null
          ? await connectionsReader()
          : await _core.getConnections();
    } catch (error) {
      commonPrint.log(
        'updateConnections error: $error',
        logLevel: coreFailureLogLevel(error),
      );
      return null;
    }
  }

  void _applyConnections(List<TrackerInfo> trackerInfos) {
    _snapshot = trackerInfos;
    final filtered = _filteredConnections(trackerInfos);
    // The core snapshot iterates a Go map, so its order is random per poll;
    // sort by total traffic to keep the list stable between refreshes.
    final sorted = List.of(filtered)
      ..sort((a, b) {
        final traffic = (b.upload + b.download).compareTo(
          a.upload + a.download,
        );
        if (traffic != 0) {
          return traffic;
        }
        final start = b.start.compareTo(a.start);
        return start != 0 ? start : a.id.compareTo(b.id);
      });
    _listController.setTrackerInfos(sorted);
  }

  List<TrackerInfo> _filteredConnections(List<TrackerInfo> trackerInfos) {
    return trackerInfos.where((trackerInfo) {
      if (_filterProcess != null &&
          trackerInfo.metadata.process != _filterProcess) {
        return false;
      }
      if (_filterChain != null && !trackerInfo.chains.contains(_filterChain)) {
        return false;
      }
      if (_filterRule != null && trackerInfo.rule != _filterRule) {
        return false;
      }
      return true;
    }).toList();
  }

  /// 把候选值按出现次数降序排列（同名连接越多越靠前），同次数按名字排。
  /// 只取前 [_maxFilterOptions] 个，避免快照里几百个进程把菜单撑爆。
  List<String> _rankFilterOptions(Iterable<String> values) {
    final counts = <String, int>{};
    for (final value in values) {
      counts[value] = (counts[value] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return entries.map((entry) => entry.key).take(_maxFilterOptions).toList();
  }

  static const _maxFilterOptions = 100;

  List<String> get _processOptions => _rankFilterOptions([
    for (final trackerInfo in _snapshot)
      if (trackerInfo.metadata.process.isNotEmpty) trackerInfo.metadata.process,
  ]);

  List<String> get _chainOptions => _rankFilterOptions([
    for (final trackerInfo in _snapshot) ...trackerInfo.chains,
  ]);

  List<String> get _ruleOptions => _rankFilterOptions([
    for (final trackerInfo in _snapshot)
      if (trackerInfo.rule.isNotEmpty) trackerInfo.rule,
  ]);

  void _setFilter(void Function() updater) {
    setState(updater);
    // 立即按新筛选重放当前快照，不等下一秒的轮询。
    _applyConnections(_snapshot);
  }

  Future<void> _handleBlockFiltered() async {
    final ids = _listController.value.list.map((info) => info.id).toList();
    if (ids.isEmpty) {
      return;
    }
    await Future.wait([for (final id in ids) _core.closeConnection(id)]);
    await _refreshConnections();
  }

  Future<void> _handleBlockConnection(String id) async {
    await _core.closeConnection(id);
    await _refreshConnections();
  }

  @override
  void dispose() {
    _listController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 筛选行：三个维度下拉 chip（进程/节点/规则）+「断开筛选结果」。
  /// 无连接时整行隐藏；有筛选时按钮才出现——别让破坏性操作常驻。
  Widget _buildFilterBar() {
    if (_snapshot.isEmpty) {
      return const SizedBox.shrink();
    }
    final appLocalizations = context.appLocalizations;
    final hasFilter =
        _filterProcess != null || _filterChain != null || _filterRule != null;
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 8, top: 4),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip(
                    title: appLocalizations.connectionsFilterProcess,
                    value: _filterProcess,
                    options: _processOptions,
                    onSelected: (value) =>
                        _setFilter(() => _filterProcess = value),
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    title: appLocalizations.connectionsFilterChain,
                    value: _filterChain,
                    options: _chainOptions,
                    onSelected: (value) =>
                        _setFilter(() => _filterChain = value),
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    title: appLocalizations.connectionsFilterRule,
                    value: _filterRule,
                    options: _ruleOptions,
                    onSelected: (value) =>
                        _setFilter(() => _filterRule = value),
                  ),
                ],
              ),
            ),
          ),
          if (hasFilter)
            IconButton(
              tooltip: appLocalizations.connectionsCloseFiltered,
              onPressed: _handleBlockFiltered,
              icon: const Icon(Icons.block, size: 20),
            ),
        ],
      ),
    );
  }

  /// 单个筛选维度：未选中是纯标签 chip，选中变胶囊填充（品牌语言同页签），
  /// 右侧自带清除按钮。菜单项里当前值加粗，一眼看出选中态。
  Widget _buildFilterChip({
    required String title,
    required String? value,
    required List<String> options,
    required ValueChanged<String?> onSelected,
  }) {
    final colorScheme = context.colorScheme;
    final selected = value != null;
    return PopupMenuButton<String>(
      tooltip: title,
      initialValue: value,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final option in options)
          PopupMenuItem(
            value: option,
            child: Text(
              option,
              style: context.textTheme.bodyMedium?.copyWith(
                fontWeight: option == value ? FontWeight.bold : null,
              ),
            ),
          ),
      ],
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.secondaryContainer
              : colorScheme.surfaceContainerLow,
          borderRadius: AppRadius.full,
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outlineVariant,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              selected ? '$title · $value' : title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.labelSmall?.copyWith(
                color: selected
                    ? colorScheme.onSecondaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => onSelected(null),
                child: Icon(
                  Icons.close,
                  size: 14,
                  color: colorScheme.onSecondaryContainer,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return CommonScaffold(
      title: appLocalizations.connections,
      onKeywordsUpdate: _listController.updateKeywords,
      searchState: AppBarSearchState(onSearch: _listController.search),
      actions: _buildActions(),
      body: ValueListenableBuilder<TrackerInfosState>(
        valueListenable: _listController,
        builder: (context, state, _) {
          final connections = state.list;
          return Column(
            children: [
              _buildFilterBar(),
              Expanded(
                child: NullStatusSwitcher(
                  isEmpty: connections.isEmpty,
                  nullStatus: NullStatus(
                    label: appLocalizations.nullTip(
                      appLocalizations.connections,
                    ),
                    illustration: NullStatusIllustration.connections,
                  ),
                  child: TrackerInfoAnimatedList(
                    controller: _scrollController,
                    trackerInfos: connections,
                    detailTitle: appLocalizations.details(
                      appLocalizations.connection,
                    ),
                    trailingBuilder: (trackerInfo) => IconButton(
                      tooltip: appLocalizations.blockConnection,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.block, size: 20),
                      onPressed: () {
                        _handleBlockConnection(trackerInfo.id);
                      },
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
