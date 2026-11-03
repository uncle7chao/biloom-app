import 'package:fl_clash/common/app_ports.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/ui/icons/app_glyphs.dart';
import 'package:fl_clash/views/views.dart';
import 'package:material_ui/material_ui.dart';

class Navigation implements NavigationPort {
  static Navigation? _instance;

  @override
  List<NavigationItem> getItems({
    bool openLogs = false,
    bool hasProxies = false,
    bool hasPromo = false,
  }) {
    return [
      NavigationItem(
        glyph: AppGlyphs.dashboard,
        label: PageLabel.dashboard,
        builder: (_) =>
            const DashboardView(key: GlobalObjectKey(PageLabel.dashboard)),
      ),
      NavigationItem(
        glyph: AppGlyphs.proxies,
        label: PageLabel.proxies,
        builder: (_) =>
            const ProxiesView(key: GlobalObjectKey(PageLabel.proxies)),
        modes: hasProxies
            ? [NavigationItemMode.mobile, NavigationItemMode.desktop]
            : [],
      ),
      NavigationItem(
        glyph: AppGlyphs.profiles,
        label: PageLabel.profiles,
        builder: (_) =>
            const ProfilesView(key: GlobalObjectKey(PageLabel.profiles)),
      ),
      NavigationItem(
        glyph: AppGlyphs.requests,
        label: PageLabel.requests,
        builder: (_) =>
            const RequestsView(key: GlobalObjectKey(PageLabel.requests)),
        modes: [NavigationItemMode.moreFull],
      ),
      NavigationItem(
        glyph: AppGlyphs.connections,
        label: PageLabel.connections,
        builder: (_) =>
            const ConnectionsView(key: GlobalObjectKey(PageLabel.connections)),
        modes: [NavigationItemMode.desktop, NavigationItemMode.moreFull],
      ),
      NavigationItem(
        glyph: AppGlyphs.dns,
        label: PageLabel.dns,
        builder: (_) =>
            const DnsQueriesView(key: GlobalObjectKey(PageLabel.dns)),
        modes: [NavigationItemMode.moreFull],
      ),
      NavigationItem(
        glyph: AppGlyphs.resources,
        label: PageLabel.resources,
        builder: (_) =>
            const ResourcesView(key: GlobalObjectKey(PageLabel.resources)),
        modes: [NavigationItemMode.more],
      ),
      NavigationItem(
        glyph: AppGlyphs.logs,
        label: PageLabel.logs,
        builder: (_) => const LogsView(key: GlobalObjectKey(PageLabel.logs)),
        modes: openLogs
            ? [NavigationItemMode.desktop, NavigationItemMode.more]
            : [],
      ),
      NavigationItem(
        glyph: AppGlyphs.tools,
        label: PageLabel.tools,
        builder: (_) => const ToolsView(key: GlobalObjectKey(PageLabel.tools)),
        modes: [NavigationItemMode.desktop, NavigationItemMode.mobile],
      ),
      // 「活动」入口（M3 方案 v2）：引流位不是广告位 —— WebView 加载
      // biloom.top 的自家页面，「在浏览器中打开」跳系统浏览器承接广告。
      // [hasPromo] 由远程开关 JSON 下发（promoWindowProvider 裁决平台与
      // url 白名单），配置无效时整个入口不渲染，不占位。
      if (hasPromo)
        NavigationItem(
          glyph: AppGlyphs.sparkle,
          label: PageLabel.activity,
          builder: (_) =>
              const ActivityView(key: GlobalObjectKey(PageLabel.activity)),
        ),
    ];
  }

  Navigation._internal();

  factory Navigation() {
    _instance ??= Navigation._internal();
    return _instance!;
  }
}

final navigation = Navigation();
