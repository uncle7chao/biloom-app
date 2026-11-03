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
import 'package:fl_clash/views/config/filters.dart';
import 'package:fl_clash/views/config/icon_sets.dart';
import 'package:fl_clash/views/config/providers.dart';
import 'package:fl_clash/views/profiles/custom/custom_proxies.dart';
import 'package:material_ui/material_ui.dart';

class CustomResourcesView extends StatelessWidget {
  const CustomResourcesView({super.key});

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final items = [
      ListItem.open(
        title: Text(appLocalizations.proxies),
        leading: const GlyphIcon(AppGlyphs.proxies),
        widget: const CustomProxiesView(),
      ),
      ListItem.open(
        title: Text(appLocalizations.ruleProviders),
        leading: const GlyphIcon(AppGlyphs.resources),
        widget: const ClashProvidersView(),
      ),
      ListItem.open(
        title: Text(appLocalizations.filters),
        leading: const GlyphIcon(AppGlyphs.filter),
        widget: const FiltersView(),
      ),
      ListItem.open(
        title: Text(appLocalizations.iconSets),
        leading: const GlyphIcon(AppGlyphs.photos),
        widget: const IconSetsView(),
      ),
    ];
    return BaseScaffold(
      title: appLocalizations.customProfileResources,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
          top: context.sectionsTopPadding,
          bottom: 16 + context.bottomInset,
        ),
        children: [generateSection(items: items)],
      ),
    );
  }
}
