import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/pages/scan.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/backup_and_restore.dart'
    show RestoreOptionsDialog;
import 'package:fl_clash/widgets/dialog.dart';
import 'package:fl_clash/widgets/list.dart';
import 'package:fl_clash/widgets/scaffold.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr/qr.dart';

/// 局域网同步。
///
/// 模型照搬 Karing 的「导出方起 HTTP 服务 + 二维码」：
///  · **导出方**：生成备份 zip → 绑定临时端口起 [HttpServer] → 把
///    `http://<局域网IP>:<端口>/biloom-sync` 画成二维码。另一台设备扫码
///    或手动输地址，GET 直接流式拉走这份 zip。
///  · **导入方**：输地址 → 下载到备份路径 → 走和本地文件恢复完全相同的
///    [BackupAction.restore] 管线（含恢复范围选择）。
///
/// 服务端只活在分享页存续期间：dispose 时关服务、删临时 zip。同 Karing，
/// 不做鉴权 —— 通道只在局域网内、页面开着才暴露，风险窗口足够小。
class LanSyncSharePage extends ConsumerStatefulWidget {
  const LanSyncSharePage({super.key});

  @override
  ConsumerState<LanSyncSharePage> createState() => _LanSyncSharePageState();
}

class _LanSyncSharePageState extends ConsumerState<LanSyncSharePage> {
  static const _servePath = '/biloom-sync';

  HttpServer? _server;
  String? _zipPath;
  List<String> _ips = const [];
  QrImage? _qrImage;
  String? _error;
  int _downloadCount = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _server?.close(force: true);
    _server = null;
    final zipPath = _zipPath;
    if (zipPath != null) {
      unawaited(File(zipPath).safeDelete());
    }
    super.dispose();
  }

  Future<void> _start() async {
    try {
      _zipPath = await ref
          .read(backupActionProvider.notifier)
          .createBackupFile();
      // 端口交给系统分配：分享地址是每次现场生成的二维码，固定端口没有收益。
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      _server!.listen(_handle, onError: (_) {});
      _ips = await _listLanAddresses();
      if (_ips.isEmpty) {
        setState(() {
          _error = '未找到可用的局域网地址，请确认两台设备在同一个网络里';
        });
        return;
      }
      final url = 'http://${_ips.first}:$port$_servePath';
      _qrImage = QrImage(
        QrCode.fromData(data: url, errorCorrectLevel: QrErrorCorrectLevel.M),
      );
      setState(() {});
    } catch (error, stacktrace) {
      commonPrint.log(
        'lan sync share failed: $error\n$stacktrace',
        logLevel: LogLevel.warning,
      );
      setState(() {
        _error = '启动分享失败：$error';
      });
    }
  }

  int get port => _server?.port ?? 0;

  /// 枚举本机 IPv4 地址，滤掉虚拟网卡 —— VMware/VirtualBox/WSL/Docker/TUN
  /// 这些接口的地址对方根本路由不到，编进二维码只会让人扫出一个连不上的码。
  Future<List<String>> _listLanAddresses() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: false,
    );
    final result = <String>[];
    for (final interface in interfaces) {
      final name = interface.name.toLowerCase();
      const virtualMarkers = [
        'vmware',
        'virtualbox',
        'vbox',
        'hyper-v',
        'wsl',
        'docker',
        'vpn',
        'tun',
        'loopback',
      ];
      if (virtualMarkers.any(name.contains)) continue;
      for (final address in interface.addresses) {
        if (address.type != InternetAddressType.IPv4) continue;
        result.add(address.address);
      }
    }
    return result;
  }

  Future<void> _handle(HttpRequest request) async {
    if (request.method != 'GET' || request.uri.path != _servePath) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final zipPath = _zipPath;
    final file = zipPath == null ? null : File(zipPath);
    if (file == null || !await file.exists()) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    request.response.headers.contentType = ContentType('application', 'zip');
    request.response.headers.set('content-length', '${await file.length()}');
    request.response.headers.set(
      'content-disposition',
      'attachment; filename="biloom_share.zip"',
    );
    try {
      await file.openRead().pipe(request.response);
      if (mounted) {
        setState(() {
          _downloadCount++;
        });
      }
    } catch (_) {
      // 对方中途取消是常态，不必记录。
    }
  }

  @override
  Widget build(BuildContext context) {
    final qrImage = _qrImage;
    return CommonScaffold(
      title: '局域网同步',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null) ...[
            ListItem(
              title: Text(_error!),
              leading: const Icon(Icons.error_outline),
            ),
          ] else if (qrImage == null) ...[
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            ),
          ] else ...[
            Center(
              child: Container(
                padding: const EdgeInsets.all(8),
                color: Colors.white,
                child: CustomPaint(
                  size: const Size(220, 220),
                  painter: _QrPainter(qrImage),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: SelectableText('http://${_ips.first}:$port$_servePath'),
            ),
            if (_ips.length > 1) ...[
              const SizedBox(height: 8),
              Center(
                child: Text(
                  '备选地址：${_ips.skip(1).join('　')}',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            const SizedBox(height: 16),
            ListItem(
              title: Text('已同步 $_downloadCount 次'),
              subtitle: const Text('保持本页打开，直到对方导入完成'),
            ),
            ListItem(
              leading: const Icon(Icons.info_outline),
              title: const Text('使用说明'),
              subtitle: const Text('两台设备需在同一局域网。首次使用如系统弹出防火墙授权，请选择「允许」。'),
            ),
          ],
        ],
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  final QrImage qr;

  _QrPainter(this.qr);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black;
    canvas.drawPaint(Paint()..color = Colors.white);
    // QR 规范要求四周各留 4 个模块的静区（quiet zone），否则大量识别器
    // 直接拒读 —— 之前模块顶着画布边画，手机对着屏幕经常扫不出来。
    const quietZone = 4;
    final count = qr.moduleCount + quietZone * 2;
    final cell = size.width / count;
    for (var row = 0; row < qr.moduleCount; row++) {
      for (var col = 0; col < qr.moduleCount; col++) {
        if (!qr.isDark(row, col)) continue;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              (col + quietZone) * cell,
              (row + quietZone) * cell,
              cell,
              cell,
            ),
            const Radius.circular(0.5),
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter oldDelegate) => oldDelegate.qr != qr;
}

/// 「从其他设备导入」入口：输地址 → 选恢复范围 → 下载并恢复。
///
/// 与本地文件恢复唯一的差别是文件来源：拉下来的 zip 同样落到备份路径，
/// 恢复走同一条 [BackupAction.restore] 管线。
Future<void> importFromLan(BuildContext context, WidgetRef ref) async {
  final address = await dialogs.showCommonDialog<String>(
    child: const _AddressInputDialog(),
  );
  if (address == null || !context.mounted) return;
  var text = address.trim();
  if (!text.startsWith('http://') && !text.startsWith('https://')) {
    text = 'http://$text';
  }
  final parsed = Uri.tryParse(text);
  if (parsed == null || parsed.host.isEmpty || parsed.port == 0) {
    unawaited(
      dialogs.showMessage(
        title: '局域网同步',
        message: const TextSpan(text: '地址格式不对，示例：192.168.1.5:41234'),
      ),
    );
    return;
  }
  final uri = parsed.replace(path: '/biloom-sync', query: '');
  final option = await dialogs.showCommonDialog<RestoreOption>(
    child: const RestoreOptionsDialog(),
  );
  if (option == null || !context.mounted) return;
  final res = await globalState.loadingRun<bool>(
    () async {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10);
      try {
        final request = await client.getUrl(uri);
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw MessageException(
            '对方返回了 ${response.statusCode}，请确认地址没输错、分享页还开着',
          );
        }
        await response.pipe(File(await appPath.backupFilePath).openWrite());
        await ref.read(backupActionProvider.notifier).restore(option);
        return true;
      } finally {
        client.close(force: true);
      }
    },
    tag: LoadingTag.backup_restore,
    title: '局域网同步',
  );
  if (res != true) return;
  unawaited(
    dialogs.showMessage(
      title: '局域网同步',
      message: const TextSpan(text: '导入成功'),
    ),
  );
}

class _AddressInputDialog extends StatefulWidget {
  const _AddressInputDialog();

  @override
  State<_AddressInputDialog> createState() => _AddressInputDialogState();
}

class _AddressInputDialogState extends State<_AddressInputDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  /// 只有带相机的平台才显示扫码入口；桌面端保持纯手填。
  bool get _canScan => Platform.isAndroid || Platform.isIOS;

  /// 扫码直填：扫到任何非空内容都原样带回（对方分享页画的就是完整
  /// http 地址），由外层 [importFromLan] 统一做协议补全与格式校验。
  Future<void> _scan() async {
    final text = await BaseNavigator.push<String>(context, const ScanPage());
    if (!mounted) return;
    if (text == null || text.trim().isEmpty) return;
    Navigator.of(context).pop(text.trim());
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      title: '从其他设备导入',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(onPressed: _submit, child: const Text('导入')),
      ],
      child: Form(
        key: _formKey,
        child: Wrap(
          runSpacing: 16,
          children: [
            TextFormField(
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.lan),
                labelText: '对方分享页显示的地址',
                helperText: '例如 192.168.1.5:41234，或完整 http:// 地址',
                suffixIcon: _canScan
                    ? IconButton(
                        tooltip: '扫码导入',
                        icon: const Icon(Icons.qr_code_scanner),
                        onPressed: _scan,
                      )
                    : null,
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '请输入地址';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }
}
