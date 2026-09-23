import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

ConfigToggleItem _appSettingToggle({
  required ConfigLabel title,
  required ConfigLabel subtitle,
  required bool Function(AppSettingProps state) select,
  required AppSettingProps Function(AppSettingProps state, bool value) update,
}) {
  return ConfigToggleItem(
    title: title,
    subtitle: subtitle,
    selector: appSettingProvider.select(select),
    onChanged: (ref, value) => ref
        .read(appSettingProvider.notifier)
        .update((state) => update(state, value)),
  );
}

class ApplicationSettingView extends StatelessWidget {
  const ApplicationSettingView({super.key});

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      const _BestPresetItem(),
      _appSettingToggle(
        title: (l) => l.minimizeOnExit,
        subtitle: (l) => l.minimizeOnExitDesc,
        select: (state) => state.minimizeOnExit,
        update: (state, value) => state.copyWith(minimizeOnExit: value),
      ),
      if (system.isDesktop) ...[
        _appSettingToggle(
          title: (l) => l.autoLaunch,
          subtitle: (l) => l.autoLaunchDesc,
          select: (state) => state.autoLaunch,
          update: (state, value) => state.copyWith(autoLaunch: value),
        ),
        _appSettingToggle(
          title: (l) => l.silentLaunch,
          subtitle: (l) => l.silentLaunchDesc,
          select: (state) => state.silentLaunch,
          update: (state, value) => state.copyWith(silentLaunch: value),
        ),
      ],
      _appSettingToggle(
        title: (l) => l.autoRun,
        subtitle: (l) => l.autoRunDesc,
        select: (state) => state.autoRun,
        update: (state, value) => state.copyWith(autoRun: value),
      ),
      if (system.isAndroid)
        _appSettingToggle(
          title: (l) => l.exclude,
          subtitle: (l) => l.excludeDesc,
          select: (state) => state.hidden,
          update: (state, value) => state.copyWith(hidden: value),
        ),
      _appSettingToggle(
        title: (l) => l.tabAnimation,
        subtitle: (l) => l.tabAnimationDesc,
        select: (state) => state.isAnimateToPage,
        update: (state, value) => state.copyWith(isAnimateToPage: value),
      ),
      _appSettingToggle(
        title: (l) => l.logcat,
        subtitle: (l) => l.logcatDesc,
        select: (state) => state.openLogs,
        update: (state, value) => state.copyWith(openLogs: value),
      ),
      _appSettingToggle(
        title: (l) => l.autoCloseConnections,
        subtitle: (l) => l.autoCloseConnectionsDesc,
        select: (state) => state.closeConnections,
        update: (state, value) => state.copyWith(closeConnections: value),
      ),
      _appSettingToggle(
        title: (l) => l.onlyStatisticsProxy,
        subtitle: (l) => l.onlyStatisticsProxyDesc,
        select: (state) => state.onlyStatisticsProxy,
        update: (state, value) => state.copyWith(onlyStatisticsProxy: value),
      ),
      if (system.isAndroid)
        _appSettingToggle(
          title: (l) => l.showNotificationStopAction,
          subtitle: (l) => l.showNotificationStopActionDesc,
          select: (state) => state.showNotificationStopAction,
          update: (state, value) =>
              state.copyWith(showNotificationStopAction: value),
        ),
      // BiLoom: the Crashlytics toggle is gone - Firebase was removed from the
      // fork, so showing a "we collect crash data via Firebase" switch here
      // would be a false disclosure in the Play Data Safety sense.
      _appSettingToggle(
        title: (l) => l.autoCheckUpdate,
        subtitle: (l) => l.autoCheckUpdateDesc,
        select: (state) => state.autoCheckUpdate,
        update: (state, value) => state.copyWith(autoCheckUpdate: value),
      ),
      _appSettingToggle(
        title: (l) => l.checkCertificate,
        subtitle: (l) => l.checkCertificateDesc,
        select: (state) => state.checkCertificate,
        update: (state, value) => state.copyWith(checkCertificate: value),
      ),
    ];
    return BaseScaffold(
      title: context.appLocalizations.application,
      body: ListView.separated(
        padding: const EdgeInsets.only(bottom: 20),
        itemBuilder: (_, index) => items[index],
        separatorBuilder: (_, _) => const Divider(height: 0),
        itemCount: items.length,
      ),
    );
  }
}

/// 「恢复最佳设置」—— 方案 C 的一键入口：不引导，随时一键回到推荐预设。
///
/// 动作本身在 [SystemAction.applyBestPreset]：按设备能力选接管方式，
/// 应用后弹窗说明选了什么、为什么。放在设置页最顶上，因为它作用于
/// 下面所有开关的总和，语义上是这一页的「快捷键」而不是其中一项。
class _BestPresetItem extends ConsumerWidget {
  const _BestPresetItem();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    return ListItem(
      leading: const Icon(Icons.auto_fix_high),
      title: Text(appLocalizations.bestPresetTitle),
      subtitle: Text(appLocalizations.bestPresetDesc),
      onTap: () async {
        final confirmed = await dialogs.showMessage(
          title: appLocalizations.bestPresetTitle,
          message: TextSpan(text: appLocalizations.bestPresetFirstRunTip),
          confirmText: appLocalizations.bestPresetApply,
        );
        if (confirmed == true) {
          await ref.read(systemActionProvider.notifier).applyBestPreset();
        }
      },
    );
  }
}
