import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'edit_node.dart';

/// 「管理节点」面板：列出一份配置里的全部节点，逐个删除。
///
/// 入口在配置卡片菜单（「添加节点」旁边）。节点名单从内核 [readProfileTargets]
/// 读 —— 它本来是给链式代理选目标用的，但「配置里有哪些节点、各是什么协议」
/// 这件事它就是权威来源，没必要再写一条读取路径。
///
/// 删除走内核 removeProxyNodes：组员、规则、listeners 的引用清理都在内核完成，
/// 这里只负责确认与回报。订阅配置同样可以删 —— 但要记得「更新订阅」会把正文
/// 整份覆盖，删了也会回来（面板顶部照「新增节点」的先例给出提示）。
class ManageProxyNodesView extends ConsumerStatefulWidget {
  final int profileId;

  const ManageProxyNodesView({super.key, required this.profileId});

  @override
  ConsumerState<ManageProxyNodesView> createState() =>
      _ManageProxyNodesViewState();
}

class _ManageProxyNodesViewState extends ConsumerState<ManageProxyNodesView> {
  List<ProfileTarget>? _nodes;
  String? _error;

  /// 名字 → 节点完整参数（readProfileTargets 的 nodes，编辑预填用）。
  Map<String, Map<String, dynamic>> _nodeDetails = {};
  // 批量删除的选中集。名字是节点的唯一键（内核按名字删），直接拿名字当勾选状态。
  final Set<String> _selected = {};

  /// 表单支持的协议才给「编辑」入口：其它类型（wireguard/tuic/…）没有表单，
  /// 编辑入口点不开比点了报错好。
  static const _editableTypes = {
    'socks5',
    'http',
    'ss',
    'vmess',
    'vless',
    'trojan',
    'hysteria2',
  };

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final targets = await ref
          .read(profilesActionProvider.notifier)
          .readProfileTargets(widget.profileId);
      if (!mounted) return;
      setState(() {
        _nodes = targets.proxies;
        _nodeDetails = {
          for (final node in targets.nodes)
            if (node['name'] != null) node['name'].toString(): node,
        };
        // 重新加载后名单可能变短（刚删掉一批），把不在名单里的选中项清掉。
        _selected.removeWhere(
          (name) => !targets.proxies.any((node) => node.name == name),
        );
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  bool get _isSubscription =>
      (ref.read(profileProvider(widget.profileId))?.url ?? '').isNotEmpty;

  void _toggle(String name) {
    setState(() {
      if (!_selected.add(name)) {
        _selected.remove(name);
      }
    });
  }

  void _toggleAll() {
    final nodes = _nodes;
    if (nodes == null || nodes.isEmpty) {
      return;
    }
    setState(() {
      if (_selected.length == nodes.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(nodes.map((node) => node.name));
      }
    });
  }

  /// 打开「编辑节点」面板。预填数据来自 readProfileTargets 的 nodes；
  /// 万一详情缺失（不该发生，但数据过期防御）就不给开，避免一张半空表单。
  void _handleEdit(ProfileTarget node) {
    final detail = _nodeDetails[node.name];
    if (detail == null) {
      return;
    }
    showSheet(
      context: context,
      props: const SheetProps(isScrollControlled: true),
      builder: (_) => EditProxyNodeView(profileId: widget.profileId, node: detail),
    );
  }

  void _showResult(RemoveProxyNodesResult result) {    final appLocalizations = context.appLocalizations;
    final lines = <String>[];
    if (result.removed.isNotEmpty) {
      lines.add(appLocalizations.deleteNodeSuccess);
      lines.addAll(result.removed.map((name) => '· $name'));
    }
    if (result.missing.isNotEmpty) {
      if (lines.isNotEmpty) lines.add('');
      lines.add(appLocalizations.deleteNodeMissing);
      lines.addAll(result.missing.map((name) => '· $name'));
    }
    if (lines.isNotEmpty) {
      dialogs.showMessage(
        message: TextSpan(text: lines.join('\n')),
        cancelable: false,
      );
    }
  }

  Future<void> _handleDelete(ProfileTarget node) async {
    final appLocalizations = context.appLocalizations;
    final confirmed = await dialogs.showMessage(
      message: TextSpan(
        text: '${node.name}\n\n${appLocalizations.deleteNodeConfirm}',
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await ref
        .read(profilesActionProvider.notifier)
        .removeProxyNodesFromProfile(
          profileId: widget.profileId,
          names: [node.name],
        );
    if (!mounted || result == null) return;
    _showResult(result);
    if (!mounted) return;
    setState(() => _selected.remove(node.name));
    _reload();
  }

  /// 批量删除：一次确认、一次调内核（removeProxyNodes 本来就收名字列表，
  /// 组员 / 规则 / listeners 的清理与单个删除走同一段代码）。
  Future<void> _handleBatchDelete() async {
    final nodes = _nodes;
    if (nodes == null || _selected.isEmpty) {
      return;
    }
    final appLocalizations = context.appLocalizations;
    final names = _selected
        .where((name) => nodes.any((node) => node.name == name))
        .toList();
    if (names.isEmpty) {
      return;
    }
    final confirmed = await dialogs.showMessage(
      message: TextSpan(
        text: '${names.join('\n')}\n\n${appLocalizations.deleteNodesConfirm}',
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await ref
        .read(profilesActionProvider.notifier)
        .removeProxyNodesFromProfile(profileId: widget.profileId, names: names);
    if (!mounted || result == null) return;
    _showResult(result);
    if (!mounted) return;
    setState(_selected.clear);
    _reload();
  }

  /// 批量操作栏：全选 + 「删除所选 (n)」。有节点时才出现在列表上方。
  Widget _buildBatchBar() {
    final appLocalizations = context.appLocalizations;
    final nodes = _nodes!;
    final allSelected = _selected.length == nodes.length;
    final count = _selected.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          InkWell(
            borderRadius: AppRadius.sm,
            onTap: _toggleAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(value: allSelected, onChanged: (_) => _toggleAll()),
                  Text(
                    appLocalizations.selectAll,
                    style: context.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: count == 0
                  ? null
                  : context.colorScheme.error,
              foregroundColor: count == 0
                  ? null
                  : context.colorScheme.onError,
            ),
            onPressed: count == 0 ? null : _handleBatchDelete,
            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
            label: Text('${appLocalizations.deleteSelected} ($count)'),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final appLocalizations = context.appLocalizations;
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(_error!, style: context.textTheme.bodyMedium),
      );
    }
    final nodes = _nodes;
    if (nodes == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (nodes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          appLocalizations.noProxyNodes,
          style: context.textTheme.bodyMedium?.copyWith(
            color: context.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: nodes.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final node = nodes[index];
        final isSelected = _selected.contains(node.name);
        return ListTile(
          leading: Checkbox(
            value: isSelected,
            onChanged: (_) => _toggle(node.name),
          ),
          onTap: () => _toggle(node.name),
          title: Text(node.name, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            node.type,
            style: context.textTheme.bodySmall?.copyWith(
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_editableTypes.contains(node.type) &&
                  _nodeDetails.containsKey(node.name))
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: appLocalizations.editNode,
                  onPressed: () => _handleEdit(node),
                ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: appLocalizations.deleteNode,
                onPressed: () => _handleDelete(node),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final height = ref.sheetHeight(context, 0.7);
    return AdaptiveSheetScaffold(
      sheetTransparentToolBar: true,
      body: SizedBox(
        height: height,
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
          ).copyWith(top: context.sheetTopPadding, bottom: 20),
          children: [
            if (_isSubscription) ...[
              Card.filled(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
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
                ),
              ),
              const SizedBox(height: 12),
            ],
            // 批量操作栏只在该有节点可管的时候出现；加载中 / 空列表时没有意义。
            if (_nodes != null && _nodes!.isNotEmpty) _buildBatchBar(),
            _buildBody(),
          ],
        ),
      ),
      title: appLocalizations.manageNodes,
    );
  }
}
