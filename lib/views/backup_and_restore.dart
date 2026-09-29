import 'dart:async';
import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/dav_client.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/lan_sync.dart';
import 'package:fl_clash/widgets/dialog.dart';
import 'package:fl_clash/widgets/fade_box.dart';
import 'package:fl_clash/widgets/input.dart';
import 'package:fl_clash/widgets/list.dart';
import 'package:fl_clash/widgets/loading.dart';
import 'package:fl_clash/widgets/scaffold.dart';
import 'package:fl_clash/widgets/text.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BackupAndRestore extends ConsumerStatefulWidget {
  const BackupAndRestore({super.key});

  @override
  ConsumerState<BackupAndRestore> createState() => _BackupAndRestoreState();
}

class _BackupAndRestoreState extends ConsumerState<BackupAndRestore>
    with UniqueKeyStateMixin {
  final _davConnection = DAVConnectionController();

  /// 自动备份：设置开关 + 本地历史。开关/列表都是纯本地数据（SP + 目录），
  /// 不进备份包 —— 见 AutoBackupSettings 的说明。
  AutoBackupSettings _autoBackupSettings = const AutoBackupSettings();
  List<File> _autoBackups = const [];

  @override
  void initState() {
    super.initState();
    ref.listenManual(davSettingProvider, (_, _) {
      _updateDAVClient();
    }, fireImmediately: true);
    unawaited(_loadAutoBackupData());
  }

  Future<void> _loadAutoBackupData() async {
    final settings = await AutoBackupStore.loadSettings();
    final backups = await AutoBackupStore.list();
    if (!mounted) return;
    setState(() {
      _autoBackupSettings = settings;
      _autoBackups = backups;
    });
  }

  Future<void> _toggleAutoBackup(AutoBackupTrigger trigger, bool value) async {
    final updated = trigger == AutoBackupTrigger.addProfile
        ? _autoBackupSettings.copyWith(onAddProfile: value)
        : _autoBackupSettings.copyWith(onRemoveProfile: value);
    await AutoBackupStore.saveSettings(updated);
    if (!mounted) return;
    setState(() {
      _autoBackupSettings = updated;
    });
  }

  /// 自动备份历史与「本地恢复」走同一条管线：把选中的历史盖到备份路径上，
  /// 再交给 [BackupAction.restore]。
  Future<void> _restoreAutoBackup(File file) async {
    final option = await dialogs.showCommonDialog<RestoreOption>(
      child: const RestoreOptionsDialog(),
    );
    if (option == null || !mounted) return;
    final res = await globalState.loadingRun<bool>(
      () async {
        await File(file.path).safeCopy(await appPath.backupFilePath);
        await ref.read(backupActionProvider.notifier).restore(option);
        return true;
      },
      tag: LoadingTag.backup_restore,
      title: context.appLocalizations.restore,
    );
    if (res != true) return;
    unawaited(
      dialogs.showMessage(
        title: context.appLocalizations.restore,
        message: TextSpan(text: context.appLocalizations.restoreSuccess),
      ),
    );
  }

  Future<void> _deleteAutoBackup(File file) async {
    try {
      await file.delete();
    } catch (_) {
      return;
    }
    await _loadAutoBackupData();
  }

  /// 历史条目副标题：文件名里的时间戳（auto_20260929-174500）转人话 + 大小。
  String _autoBackupFileDescription(File file) {
    final name = file.uri.pathSegments.last;
    final match = RegExp(r'^auto_(\d{8})-(\d{6})\.zip$').firstMatch(name);
    final size = '${(file.lengthSync() / 1024).ceil()} KB';
    if (match == null) {
      return size;
    }
    final date = match.group(1)!;
    final time = match.group(2)!;
    final readable =
        '${date.substring(0, 4)}-${date.substring(4, 6)}-${date.substring(6)} '
        '${time.substring(0, 2)}:${time.substring(2, 4)}:${time.substring(4)}';
    return '$readable · $size';
  }

  void _updateDAVClient() {
    unawaited(_davConnection.update(ref.read(davSettingProvider)));
  }

  @override
  void dispose() {
    _davConnection.dispose();
    super.dispose();
  }

  Future<void> _showAddWebDAV(DAVProps? dav) async {
    await dialogs.showCommonDialog<String>(
      child: WebDAVFormDialog(dav: dav?.copyWith()),
    );
  }

  Future<void> _backupOnWebDAV() async {
    final appLocalizations = context.appLocalizations;
    final res = await globalState.loadingRun<bool>(
      () async {
        final client = _davConnection.client;
        if (client == null) {
          return false;
        }
        return ref
            .read(backupActionProvider.notifier)
            .consumeBackup(client.backup);
      },
      tag: LoadingTag.backup_restore,
      title: appLocalizations.backup,
    );
    if (res != true) return;
    unawaited(
      dialogs.showMessage(
        title: appLocalizations.backup,
        message: TextSpan(text: appLocalizations.backupSuccess),
      ),
    );
  }

  Future<void> _restoreOnWebDAV(RestoreOption option) async {
    final appLocalizations = context.appLocalizations;
    final res = await globalState.loadingRun<bool>(
      () async {
        final client = _davConnection.client;
        if (client == null) {
          return false;
        }
        await client.restore();
        await ref.read(backupActionProvider.notifier).restore(option);
        return true;
      },
      tag: LoadingTag.backup_restore,
      title: appLocalizations.restore,
    );
    if (res != true) return;
    unawaited(
      dialogs.showMessage(
        title: appLocalizations.restore,
        message: TextSpan(text: appLocalizations.restoreSuccess),
      ),
    );
  }

  Future<void> _handleRestoreOnWebDAV() async {
    final restoreOption = await dialogs.showCommonDialog<RestoreOption>(
      child: const RestoreOptionsDialog(),
    );
    if (restoreOption == null || !context.mounted) return;
    unawaited(_restoreOnWebDAV(restoreOption));
  }

  Future<void> _backupOnLocal() async {
    final appLocalizations = context.appLocalizations;
    final res = await globalState.loadingRun<bool>(
      () async {
        return ref.read(backupActionProvider.notifier).consumeBackup((
          path,
        ) async {
          final value = await picker.saveFileWithPath(
            getBackupFileName(),
            path,
          );
          return value != null;
        });
      },
      title: appLocalizations.backup,
      tag: LoadingTag.backup_restore,
    );
    if (res != true) return;
    unawaited(
      dialogs.showMessage(
        title: appLocalizations.backup,
        message: TextSpan(text: appLocalizations.backupSuccess),
      ),
    );
  }

  Future<void> _restoreOnLocal(RestoreOption option) async {
    final backupAction = ref.read(backupActionProvider.notifier);
    final appLocalizations = context.appLocalizations;
    final file = await picker.pickerFile();
    final path = file?.path;
    if (path == null) return;
    await File(path).safeCopy(await appPath.backupFilePath);
    final res = await globalState.loadingRun<bool>(
      () async {
        await backupAction.restore(option);
        return true;
      },
      tag: LoadingTag.backup_restore,
      title: appLocalizations.restore,
    );
    if (res != true) return;
    unawaited(
      dialogs.showMessage(
        title: appLocalizations.restore,
        message: TextSpan(text: appLocalizations.restoreSuccess),
      ),
    );
  }

  Future<void> _handleRestoreOnLocal() async {
    final option = await dialogs.showCommonDialog<RestoreOption>(
      child: const RestoreOptionsDialog(),
    );
    if (option == null || !mounted) return;
    unawaited(_restoreOnLocal(option));
  }

  void _handleChange(String? value, WidgetRef ref) {
    if (value == null) {
      return;
    }
    ref
        .read(davSettingProvider.notifier)
        .update((state) => state?.copyWith(fileName: value));
  }

  Future<void> _handleUpdateRestoreStrategy() async {
    final restoreStrategy = ref.read(
      appSettingProvider.select((state) => state.restoreStrategy),
    );
    final res = await dialogs.showCommonDialog(
      child: OptionsDialog<RestoreStrategy>(
        title: currentAppLocalizations.restoreStrategy,
        options: RestoreStrategy.values,
        textBuilder: (mode) => mode.label,
        value: restoreStrategy,
      ),
    );
    if (res == null) {
      return;
    }
    ref
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(restoreStrategy: res));
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final dav = ref.watch(davSettingProvider);
    final isLoading = ref.watch(loadingProvider(LoadingTag.backup_restore));
    return CommonScaffold(
      isLoading: isLoading,
      title: appLocalizations.backupAndRestore,
      body: ListView(
        children: [
          ListHeader(title: appLocalizations.remote),
          if (dav == null)
            ListItem(
              leading: const Icon(Icons.account_box),
              title: Text(appLocalizations.noInfo),
              subtitle: Text(appLocalizations.pleaseBindWebDAV),
              trailing: FilledButton.tonal(
                onPressed: () {
                  _showAddWebDAV(dav);
                },
                child: Text(appLocalizations.bind),
              ),
            )
          else ...[
            ListItem(
              leading: const Icon(Icons.account_box),
              title: TooltipText(
                text: Text(
                  dav.user,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(appLocalizations.connectivity),
                    _DavConnectionIndicator(connection: _davConnection),
                  ],
                ),
              ),
              trailing: FilledButton.tonal(
                onPressed: () {
                  _showAddWebDAV(dav);
                },
                child: Text(appLocalizations.edit),
              ),
            ),
            const SizedBox(height: 4),
            ListItem.input(
              title: Text(appLocalizations.file),
              subtitle: Text(dav.fileName),
              dialogTitle: appLocalizations.file,
              value: dav.fileName,
              resetValue: defaultDavFileName,
              maxLength: TextInputLimits.fileName,
              onChanged: (value) {
                _handleChange(value, ref);
              },
            ),
            ListItem(
              onTap: () {
                _backupOnWebDAV();
              },
              title: Text(appLocalizations.backup),
              subtitle: Text(appLocalizations.remoteBackupDesc),
            ),
            ListItem(
              onTap: () {
                _handleRestoreOnWebDAV();
              },
              title: Text(appLocalizations.restore),
              subtitle: Text(appLocalizations.restoreFromWebDAVDesc),
            ),
          ],
          ListHeader(title: appLocalizations.local),
          ListItem(
            onTap: () {
              _backupOnLocal();
            },
            title: Text(appLocalizations.backup),
            subtitle: Text(appLocalizations.localBackupDesc),
          ),
          ListItem(
            onTap: () {
              _handleRestoreOnLocal();
            },
            title: Text(appLocalizations.restore),
            subtitle: Text(appLocalizations.restoreFromFileDesc),
          ),
          ListHeader(title: '局域网同步'),
          ListItem(
            onTap: () {
              unawaited(BaseNavigator.push(context, const LanSyncSharePage()));
            },
            leading: const Icon(Icons.share),
            title: const Text('分享配置到其他设备'),
            subtitle: const Text('生成二维码，同一局域网内的设备扫码或输地址即可导入'),
          ),
          ListItem(
            onTap: () {
              unawaited(importFromLan(context, ref));
            },
            leading: const Icon(Icons.lan),
            title: const Text('从其他设备导入'),
            subtitle: const Text('输入对方分享页显示的地址，拉取配置并恢复'),
          ),
          ListHeader(title: '自动备份'),
          ListItem(
            onTap: () => unawaited(
              _toggleAutoBackup(
                AutoBackupTrigger.addProfile,
                !_autoBackupSettings.onAddProfile,
              ),
            ),
            title: const Text('添加订阅时自动备份'),
            subtitle: const Text('自动备份只保存在本机，不会上传到 WebDAV'),
            trailing: Switch(
              value: _autoBackupSettings.onAddProfile,
              onChanged: (value) => unawaited(
                _toggleAutoBackup(AutoBackupTrigger.addProfile, value),
              ),
            ),
          ),
          ListItem(
            onTap: () => unawaited(
              _toggleAutoBackup(
                AutoBackupTrigger.removeProfile,
                !_autoBackupSettings.onRemoveProfile,
              ),
            ),
            title: const Text('删除订阅时自动备份'),
            subtitle: const Text('删除前留一份底，误删可以用这里的历史找回来'),
            trailing: Switch(
              value: _autoBackupSettings.onRemoveProfile,
              onChanged: (value) => unawaited(
                _toggleAutoBackup(AutoBackupTrigger.removeProfile, value),
              ),
            ),
          ),
          for (final file in _autoBackups)
            ListItem(
              onTap: () => unawaited(_restoreAutoBackup(file)),
              title: Text(file.uri.pathSegments.last),
              subtitle: Text(_autoBackupFileDescription(file)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: appLocalizations.restore,
                    icon: const Icon(Icons.restore),
                    onPressed: () => unawaited(_restoreAutoBackup(file)),
                  ),
                  IconButton(
                    tooltip: appLocalizations.delete,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => unawaited(_deleteAutoBackup(file)),
                  ),
                ],
              ),
            ),
          ListHeader(title: appLocalizations.options),
          _RestoreStrategyItem(onPressed: _handleUpdateRestoreStrategy),
        ],
      ),
    );
  }
}

class _DavConnectionIndicator extends StatelessWidget {
  const _DavConnectionIndicator({required this.connection});

  final ValueNotifier<bool?> connection;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: connection,
      builder: (context, isConnected, _) {
        return Center(
          child: FadeThroughBox(
            child: isConnected == null
                ? const SizedBox(
                    width: 12,
                    height: 12,
                    child: CommonCircleLoading(),
                  )
                : Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: !isConnected
                          ? context.colorScheme.error
                          : Colors.green.harmonizeWith(
                              context.colorScheme.primary,
                            ),
                    ),
                    width: 12,
                    height: 12,
                  ),
          ),
        );
      },
    );
  }
}

class _RestoreStrategyItem extends ConsumerWidget {
  const _RestoreStrategyItem({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restoreStrategy = ref.watch(
      appSettingProvider.select((state) => state.restoreStrategy),
    );
    return ListItem(
      onTap: onPressed,
      title: Text(context.appLocalizations.restoreStrategy),
      trailing: FilledButton(
        onPressed: onPressed,
        child: Text(restoreStrategy.label),
      ),
    );
  }
}

class RestoreOptionsDialog extends StatefulWidget {
  const RestoreOptionsDialog({super.key});

  @override
  State<RestoreOptionsDialog> createState() => _RestoreOptionsDialogState();
}

class _RestoreOptionsDialogState extends State<RestoreOptionsDialog> {
  void _handleOnTab(RestoreOption? option) {
    if (option == null) return;
    Navigator.of(context).pop(option);
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return CommonDialog(
      title: appLocalizations.restore,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Wrap(
        children: [
          ListItem(
            onTap: () {
              _handleOnTab(RestoreOption.onlyProfiles);
            },
            title: Text(appLocalizations.restoreOnlyConfig),
          ),
          ListItem(
            onTap: () {
              _handleOnTab(RestoreOption.all);
            },
            title: Text(appLocalizations.restoreAllData),
          ),
        ],
      ),
    );
  }
}

class WebDAVFormDialog extends ConsumerStatefulWidget {
  final DAVProps? dav;

  const WebDAVFormDialog({super.key, this.dav});

  @override
  ConsumerState<WebDAVFormDialog> createState() => _WebDAVFormDialogState();
}

class _WebDAVFormDialogState extends ConsumerState<WebDAVFormDialog> {
  late TextEditingController _uriController;
  late TextEditingController _userController;
  late TextEditingController _passwordController;
  final _obscureController = ValueNotifier<bool>(true);
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _uriController = TextEditingController(text: widget.dav?.uri);
    _userController = TextEditingController(text: widget.dav?.user);
    _passwordController = TextEditingController(text: widget.dav?.password);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    ref
        .read(davSettingProvider.notifier)
        .update(
          (_) => DAVProps(
            uri: _uriController.text,
            user: _userController.text,
            password: _passwordController.text,
            fileName: widget.dav?.fileName ?? defaultDavFileName,
          ),
        );
    Navigator.pop(context);
  }

  void _delete() {
    ref.read(davSettingProvider.notifier).update((_) => null);
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _obscureController.dispose();
    _uriController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return CommonDialog(
      title: appLocalizations.webDAVConfiguration,
      actions: [
        if (widget.dav != null)
          TextButton(onPressed: _delete, child: Text(appLocalizations.delete)),
        TextButton(onPressed: _submit, child: Text(appLocalizations.save)),
      ],
      child: Form(
        key: _formKey,
        child: Wrap(
          runSpacing: 16,
          children: [
            TextFormField(
              controller: _uriController,
              inputFormatters: TextInputLimits.limit(TextInputLimits.uri),
              maxLines: 5,
              minLines: 1,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.link),
                labelText: appLocalizations.address,
                helperText: appLocalizations.addressHelp,
              ),
              validator: (String? value) {
                if (value == null || value.isEmpty || !value.isUrl) {
                  return appLocalizations.addressTip;
                }
                return null;
              },
            ),
            TextFormField(
              controller: _userController,
              inputFormatters: TextInputLimits.limit(TextInputLimits.userName),
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.account_circle),
                labelText: appLocalizations.account,
              ),
              validator: (String? value) {
                if (value == null || value.isEmpty) {
                  return appLocalizations.emptyTip(appLocalizations.account);
                }
                return null;
              },
            ),
            ValueListenableBuilder(
              valueListenable: _obscureController,
              builder: (_, obscure, _) {
                return TextFormField(
                  controller: _passwordController,
                  inputFormatters: TextInputLimits.limit(
                    TextInputLimits.password,
                  ),
                  obscureText: obscure,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) {
                    _submit();
                  },
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.password),
                    suffixIcon: IconButton(
                      tooltip: obscure
                          ? context.appLocalizations.showPassword
                          : context.appLocalizations.hidePassword,
                      icon: Icon(
                        obscure ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () {
                        _obscureController.value = !obscure;
                      },
                    ),
                    labelText: appLocalizations.password,
                  ),
                  validator: (String? value) {
                    if (value == null || value.isEmpty) {
                      return appLocalizations.emptyTip(
                        appLocalizations.password,
                      );
                    }
                    return null;
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
