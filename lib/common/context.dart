import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/manager/status_manager.dart';
import 'package:fl_clash/ui/context.dart' as ui_ctx;
import 'package:fl_clash/models/state.dart';
import 'package:material_ui/material_ui.dart';

/// fork 增量扩展：v0.9.2 上游把通用上下文扩展搬进了 ui/context.dart
/// （commonScaffoldState / colorScheme / 排版系等），
/// 这里只留 BiLoom 自己的成员，避免与上游扩展重名冲突。
extension AppContextExtension on BuildContext {
  void showNotifier(
    String text, {
    MessageLevel level = MessageLevel.info,
    MessageActionState? actionState,
  }) {
    return findAncestorStateOfType<StatusManagerState>()?.message(
      text,
      level: level,
      actionState: actionState,
    );
  }

  /// 旧名兼容：上游新版叫 contentTopPadding（ui/context.dart），
  /// 覆写编辑器各页还用着旧名，指过去即可。
  double get sheetTopPadding =>
      ui_ctx.BuildContextExtension(this).contentTopPadding;

  TextTheme get textTheme => Theme.of(this).textTheme;

  AppLocalizations get appLocalizations => AppLocalizations.of(this);

  T? findLastStateOfType<T extends State>() {
    T? state;

    void visitor(Element element) {
      if (!element.mounted) {
        return;
      }
      if (element is StatefulElement) {
        if (element.state is T) {
          state = element.state as T;
        }
      }
      element.visitChildren(visitor);
    }

    visitChildElements(visitor);
    return state;
  }
}

