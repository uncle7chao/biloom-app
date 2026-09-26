import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/pages/scan.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'add_node_form.dart';

/// 「新增节点」面板。
///
/// 两种模式共用一条提交管线（`addProxyNodesToProfile` → 内核 parseProxyNodes）：
///  - 粘贴：分享链接 / YAML 片段 / 二维码，由内核自己判断是哪一种；
///  - 手动填写：表单按协议动态出字段（`add_node_form.dart`），生成节点 JSON
///    交给同一条管线 —— 重名跳过、自动补默认分组这些安全逻辑原样生效。
///
/// 面板自己不做任何 YAML 解析：拿到文本就交给内核，回收整份新配置。这样 Dart 侧
/// 永远不碰配置内容，也就不存在「拼错一个缩进毁掉整份配置」的可能。
class AddProxyNodeView extends ConsumerStatefulWidget {
  final int profileId;

  const AddProxyNodeView({super.key, required this.profileId});

  @override
  ConsumerState<AddProxyNodeView> createState() => _AddProxyNodeViewState();
}

class _AddProxyNodeViewState extends ConsumerState<AddProxyNodeView> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<ProxyNodeFormState>();
  bool _manual = false;

  /// 目标配置：入口传进来的那份只是**默认值**，面板里可以随时换。
  late int _profileId = widget.profileId;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 这份配置是不是订阅来的。
  ///
  /// 订阅配置的正文会在每次「更新订阅」时被整份覆盖，所以往它里面加节点是**临时**的。
  /// 必须在动手之前就把这件事说清楚 —— 等用户下次更新完发现节点没了再解释就晚了。
  bool get _isSubscription =>
      (ref.read(profileProvider(_profileId))?.url ?? '').isNotEmpty;

  Future<void> _handlePasteFromClipboard() async {
    // 先把文案取出来：读剪贴板是异步的，await 之后再用 context 就得额外加
    // mounted 检查，而这两句提示文案本来也不需要等到那时才取。
    final appLocalizations = context.appLocalizations;
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      if (!mounted) return;
      _showMessage(appLocalizations.clipboardEmpty);
      return;
    }
    _controller.text = text;
  }

  Future<void> _handleScan() async {
    final text = await BaseNavigator.push(context, const ScanPage());
    if (!mounted || text == null || text.trim().isEmpty) return;
    _controller.text = text.trim();
  }

  Future<void> _handleConvertToLocal() async {
    // 读 URL 与执行转换必须同一份配置：_profileId 是用户在面板里选的目标，
    // widget.profileId 只是打开时的初值 —— 两者在用户切换下拉后分叉，
    // 各用各的会把另一份订阅的 URL 展示出来、却转换了错误的那份。
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

  Future<void> _handleSubmit() async {
    final appLocalizations = context.appLocalizations;
    String nodes;
    if (_manual) {
      final json = _formKey.currentState?.buildNodesJson();
      if (json == null) {
        // 表单内已经把缺的必填项标红了，这里不再弹重复的提示。
        return;
      }
      nodes = json;
    } else {
      nodes = _controller.text.trim();
      if (nodes.isEmpty) {
        _showMessage(appLocalizations.emptyTip('').trim());
        return;
      }
    }
    final result = await ref
        .read(profilesActionProvider.notifier)
        .addProxyNodesToProfile(profileId: _profileId, nodes: nodes);
    // result 为 null 表示内核或校验已经报过错（loadingRun 会弹出来），这里不再补一句。
    if (!mounted || result == null) return;
    await _showResult(result);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  /// 如实回报每一个节点去了哪。
  ///
  /// 重名被跳过这件事必须说出来：Clash 里同名会让整份配置加载失败，所以只能留一个；
  /// 而静默跳过会让用户以为加成功了，然后在节点列表里怎么都找不到自己刚加的那条。
  Future<void> _showResult(AddProxyNodesResult result) async {
    final appLocalizations = context.appLocalizations;
    final lines = <String>[];
    if (result.added.isNotEmpty) {
      lines.add('${appLocalizations.addProxyNode} +${result.added.length}');
      lines.addAll(result.added.map((name) => '· $name'));
    }
    if (result.skipped.isNotEmpty) {
      if (lines.isNotEmpty) lines.add('');
      lines.add(appLocalizations.skippedDuplicateNodes);
      lines.addAll(result.skipped.map((name) => '· $name'));
    }
    if (lines.isEmpty) return;
    await dialogs.showMessage(
      message: TextSpan(text: lines.join('\n')),
      cancelable: false,
    );
  }

  void _showMessage(String text) {
    dialogs.showMessage(message: TextSpan(text: text), cancelable: false);
  }

  /// 目标配置选择器：入口默认选中传进来的那份，可手动换成任何一份配置。
  ///
  /// 节点最终要写进某份配置的正文，所以「加到哪」必须在提交之前就摆在明面上 ——
  /// 埋在高级选项里只会让人加完节点后到别的配置里找不到。
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
        setState(() => _profileId = value);
      },
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

  Widget _buildInput() {
    final appLocalizations = context.appLocalizations;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(
              value: false,
              icon: const Icon(Icons.content_paste, size: 18),
              label: Text(appLocalizations.addNodePasteMode),
            ),
            ButtonSegment(
              value: true,
              icon: const Icon(Icons.edit_note, size: 18),
              label: Text(appLocalizations.addNodeManualMode),
            ),
          ],
          selected: {_manual},
          onSelectionChanged: (selection) =>
              setState(() => _manual = selection.first),
        ),
        const SizedBox(height: 12),
        if (_manual)
          ProxyNodeForm(key: _formKey)
        else ...[
          Text(
            appLocalizations.addProxyNodeDesc,
            style: context.textTheme.bodySmall?.copyWith(
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            minLines: 6,
            maxLines: 12,
            autofocus: true,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: _handlePasteFromClipboard,
                icon: const Icon(Icons.content_paste, size: 18),
                label: Text(appLocalizations.pasteFromClipboard),
              ),
              // 桌面端不给扫码入口：那里没有摄像头，识别图片里的二维码走的是另一条
              // 依赖（picker），把它混进来只会让按钮点了没反应。
              if (!system.isDesktop)
                TextButton.icon(
                  onPressed: _handleScan,
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: Text(appLocalizations.qrcode),
                ),
            ],
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final height = ref.sheetHeight(context, _manual ? 0.85 : 0.6);
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
            _buildInput(),
          ],
        ),
      ),
      title: appLocalizations.addProxyNode,
    );
  }
}
