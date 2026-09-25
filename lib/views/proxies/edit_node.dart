import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'add_node_form.dart';

/// 「编辑节点」面板：把节点的完整参数预填进 [ProxyNodeForm]，提交走内核
/// updateProxyNode —— 名字是组员/规则/链式引用的锚点，编辑不允许改名
/// （表单里名字只读、协议锁定），其余字段整体替换。
///
/// 与「新增」共用同一张表单：内核的安全逻辑（校验、文档级编辑、整体替换）
/// 全部原样生效，Dart 侧不碰配置内容。
class EditProxyNodeView extends ConsumerStatefulWidget {
  final int profileId;
  final Map<String, dynamic> node;

  const EditProxyNodeView({
    super.key,
    required this.profileId,
    required this.node,
  });

  @override
  ConsumerState<EditProxyNodeView> createState() => _EditProxyNodeViewState();
}

class _EditProxyNodeViewState extends ConsumerState<EditProxyNodeView> {
  final _formKey = GlobalKey<ProxyNodeFormState>();

  Future<void> _handleSubmit() async {
    final json = _formKey.currentState?.buildNodesJson();
    if (json == null) {
      // 表单内已经把缺的必填项标红了，这里不再弹重复的提示。
      return;
    }
    final name = widget.node['name']?.toString() ?? '';
    final result = await ref
        .read(profilesActionProvider.notifier)
        .updateProxyNodeInProfile(
          profileId: widget.profileId,
          name: name,
          node: json,
        );
    // result 为 null 表示内核或校验已经报过错（loadingRun 会弹出来），这里不再补一句。
    if (!mounted || result == null) return;
    dialogs.showMessage(
      message: TextSpan(
        text: '${context.appLocalizations.editNodeSuccess}\n· ${result.updated}',
      ),
      cancelable: false,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final height = ref.sheetHeight(context, 0.85);
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
            ProxyNodeForm(key: _formKey, initialNode: widget.node),
          ],
        ),
      ),
      title: appLocalizations.editNode,
    );
  }
}
