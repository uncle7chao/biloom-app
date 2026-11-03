import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/widgets/widgets.dart' hide
      ActivateBox,
      AnimatedVisibility,
      AppBarSearchStateBuilder,
      BackLayerScope,
      BaseScaffold,
      BottomInsetScope,
      CloseContainerActionCallback,
      CloseContainerBuilder,
      ClosedCallback,
      CommonCard,
      CommonCheckBox,
      CommonChip,
      CommonCircleLoading,
      CommonDialog,
      CommonExpandIcon,
      CommonMinFilledButtonTheme,
      CommonMinIconButtonTheme,
      CommonPopScope,
      CommonPopupBox,
      CommonPopupMenu,
      CommonPopupMenuItem,
      CommonPopupRoute,
      CommonScaffold,
      CommonScaffoldState,
      CommonScrollBar,
      DecorationListItem,
      DisabledMask,
      EmojiText,
      ExtendProps,
      FadeBox,
      FadeScaleBox,
      FadeScaleEnterBox,
      FadeScaleEnterTransition,
      FadeSlideEnterTransition,
      FadeThroughBox,
      FloatingScrollbar,
      Info,
      InfoHeader,
      InputDialog,
      ItemPositionProvider,
      KeepScope,
      KeyedAnimatedList,
      LineChart,
      ListHeader,
      ListItem,
      MetaChip,
      ModalSideSheetRoute,
      MoreActionButton,
      NullStatus,
      NullStatusIllustration,
      NullStatusSwitcher,
      OnKeywordsUpdateCallback,
      OpenContainer,
      OpenContainerBuilder,
      PageActivityScope,
      PageFocusScope,
      PageTraversalPolicy,
      PagedSheet,
      PagedSheetRoute,
      PopupAnchorResolver,
      PopupOpen,
      ProfileIdProvider,
      ProxyDecoratorProvider,
      ScrollToEndBox,
      SelectedDecorationListItem,
      SettingTextCard,
      SheetProps,
      SheetProvider,
      SheetType,
      SideSheet,
      SliderDefaultsM3,
      TooltipLabel,
      TooltipText,
      commonProxyDecorator,
      genActions,
      generateSection,
      showExtend,
      showModalSideSheet,
      showSheet;
import 'package:material_ui/material_ui.dart';

import 'custom_issue.dart';

/// A form [showFormSheet] opens: grouped rows under a bar whose check saves,
/// with why the last save was refused above them.
class FormPage extends StatelessWidget {
  final String title;
  final VoidCallback onSave;
  final String? saveLabel;
  final List<IconButtonData> actions;
  final String? error;
  final bool saving;
  final List<Widget> children;

  const FormPage({
    super.key,
    required this.title,
    required this.onSave,
    this.saveLabel,
    this.actions = const [],
    this.error,
    this.saving = false,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: title,
      iconActions: actions,
      confirmationAction: IconButtonData(
        glyph: AppGlyphs.check,
        tooltip: saveLabel ?? context.appLocalizations.save,
        isLoading: saving,
        onPressed: saving ? null : onSave,
      ),
      body: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
          top: context.sectionsTopPadding,
          bottom: 20 + context.bottomInset,
        ),
        children: [
          ErrorBanner(message: error),
          ...children,
        ],
      ),
    );
  }
}
