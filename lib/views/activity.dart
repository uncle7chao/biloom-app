import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/scaffold.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_windows/webview_windows.dart';

/// 「活动」页 —— Windows 端引流位（M3 广告内嵌方案 v2）。
///
/// WebView 加载 biloom.top 的自家推广页（**绝不允许 AdSense 代码进应用内
/// 窗口**，那是封整个 AdSense 账号的红线），页内「在浏览器中打开」跳系统
/// 浏览器，广告收入由官网承接。url 由远程开关 JSON 下发，入口显示与否、
/// 加载哪个页面全部远程可控；本页只在 [promoWindowProvider] 非 null 时
/// 才会出现在导航里。
///
/// 降级链（每一步都不让用户看到白屏/死入口）：
/// 1. WebView2 Runtime 缺失（initialize 抛异常）→ 直接显示「在浏览器中
///    打开」的大按钮，点击即跳系统浏览器；
/// 2. 加载超过 [kActivityLoadTimeout] 仍未完成 → 同上（并保留重试）；
/// 3. 远程把配置关掉 → 入口消失，本页不会被进入（keepAlive 下已进入的
///    旧实例显示「活动不可用」占位）。
const kActivityLoadTimeout = Duration(seconds: 10);

class ActivityView extends ConsumerStatefulWidget {
  const ActivityView({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _ActivityViewState();
}

class _ActivityViewState extends ConsumerState<ActivityView> {
  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final promo = ref.watch(promoWindowProvider);
    if (promo == null) {
      return CommonScaffold(
        title: appLocalizations.activity,
        body: Center(
          child: Text(appLocalizations.activityLoadFailed),
        ),
      );
    }
    return CommonScaffold(
      title: appLocalizations.activity,
      body: _ActivityWebView(url: promo.url),
    );
  }
}

class _ActivityWebView extends ConsumerStatefulWidget {
  const _ActivityWebView({required this.url});

  final String url;

  @override
  ConsumerState<_ActivityWebView> createState() => _ActivityWebViewState();
}

class _ActivityWebViewState extends ConsumerState<_ActivityWebView> {
  final _controller = WebviewController();
  Timer? _timeoutTimer;

  /// null = WebView 正常渲染；非 null = 降级页（直接给「在浏览器中打开」）。
  bool? _failed;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() {
      _failed = null;
      _loading = true;
    });
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(kActivityLoadTimeout, () {
      if (mounted && _loading) {
        setState(() {
          _failed = true;
        });
      }
    });
    try {
      await _controller.initialize();
      // 活动页是纯展示页：弹窗（window.open）一律拒绝，不让远程页面在
      // 应用里造新窗口。
      unawaited(
        _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny),
      );
      unawaited(_controller.loadUrl(widget.url));
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    } catch (_) {
      // WebView2 Runtime 缺失或初始化失败：WebView 不可用，降级为直接
      // 跳系统浏览器 —— 功能不丢，只是少了内嵌体验。
      if (mounted) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  Future<void> _openInBrowser() async {
    final uri = Uri.tryParse(widget.url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return Column(
      children: [
        _buildUrlBar(appLocalizations),
        const Divider(height: 0),
        Expanded(
          child: _failed == true
              ? _buildFallback(appLocalizations)
              : Stack(
                  children: [
                    Webview(_controller),
                    if (_loading)
                      const Center(child: CircularProgressIndicator()),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildUrlBar(AppLocalizations appLocalizations) {
    final uri = Uri.tryParse(widget.url);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.language, size: 16, color: Theme.of(context).hintColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              uri?.host ?? widget.url,
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: appLocalizations.openInBrowser,
            icon: const Icon(Icons.open_in_new),
            onPressed: _openInBrowser,
          ),
        ],
      ),
    );
  }

  Widget _buildFallback(AppLocalizations appLocalizations) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.language,
            size: 48,
            color: Theme.of(context).hintColor,
          ),
          const SizedBox(height: 16),
          Text(appLocalizations.activityLoadFailed),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _openInBrowser,
            icon: const Icon(Icons.open_in_new),
            label: Text(appLocalizations.openInBrowser),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _init,
            child: Text(appLocalizations.retry),
          ),
        ],
      ),
    );
  }
}
