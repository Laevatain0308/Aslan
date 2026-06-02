import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/widget/collect_button.dart';
import 'package:kazumi/bean/widget/embedded_native_control_area.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/pages/info/info_controller.dart';
import 'package:kazumi/bean/card/bangumi_info_card.dart';
import 'package:kazumi/pages/info/source_sheet.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/pages/info/info_tabview.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/bean/appbar/drag_to_move_bar.dart' as dtb;
import 'package:kazumi/utils/device.dart';

class InfoPage extends StatefulWidget {
  const InfoPage({super.key});

  @override
  State<InfoPage> createState() => _InfoPageState();
}

class _InfoPageState extends State<InfoPage> with TickerProviderStateMixin {
  static const List<String> _infoTabs = <String>['概览'];
  static const Duration _minimumBangumiInfoLoadingDuration = Duration(
    milliseconds: 600,
  );

  /// Don't use modular singleton here. We may have multiple info pages.
  /// Use a new instance of InfoController for each info page.
  final InfoController infoController = InfoController();
  final VideoPageController videoPageController =
      Modular.get<VideoPageController>();
  late TabController sourceTabController;
  late TabController infoTabController;
  late bool showRating;

  bool _showBangumiInfoSkeleton = false;

  final inputBangumiIten = Modular.args.data as BangumiItem;

  bool get _isShowingBangumiInfoSkeleton =>
      infoController.isLoading || _showBangumiInfoSkeleton;

  @override
  void initState() {
    super.initState();
    infoController.bangumiItem = inputBangumiIten;
    infoController.pluginSearchResponseList.clear();
    videoPageController.resetEpisodeState();
    _showBangumiInfoSkeleton = true;
    queryLaevaBangumiInfo(enforceMinimumLoadingDuration: true);
    sourceTabController = TabController(length: 1, vsync: this);
    infoTabController = TabController(length: _infoTabs.length, vsync: this);
    showRating = GStorage.setting.get(
      SettingBoxKey.showRating,
      defaultValue: true,
    );
  }

  @override
  void dispose() {
    infoController.pluginSearchResponseList.clear();
    videoPageController.resetEpisodeState();
    sourceTabController.dispose();
    infoTabController.dispose();
    super.dispose();
  }

  Future<void> queryLaevaBangumiInfo({
    bool enforceMinimumLoadingDuration = false,
  }) async {
    final loadingStartedAt = DateTime.now();
    try {
      await infoController.queryLaevaBangumiInfo();
    } catch (e) {
      KazumiLogger().e('InfoPage: failed to query LaevaBangumi info', error: e);
    } finally {
      if (enforceMinimumLoadingDuration && mounted) {
        await _waitForMinimumBangumiInfoLoadingDuration(loadingStartedAt);
      }
      if (mounted) {
        setState(() {
          _showBangumiInfoSkeleton = false;
        });
      }
    }
  }

  Future<void> _waitForMinimumBangumiInfoLoadingDuration(
    DateTime loadingStartedAt,
  ) async {
    final elapsed = DateTime.now().difference(loadingStartedAt);
    final remaining = _minimumBangumiInfoLoadingDuration - elapsed;
    if (remaining > Duration.zero) {
      await Future.delayed(remaining);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool showWindowButton = GStorage.setting.get(
      SettingBoxKey.showWindowButton,
      defaultValue: false,
    );
    return PopScope(
      canPop: true,
      child: DefaultTabController(
        length: _infoTabs.length,
        child: Scaffold(
          body: NestedScrollView(
            headerSliverBuilder:
                (BuildContext context, bool innerBoxIsScrolled) {
              return <Widget>[
                SliverOverlapAbsorber(
                  handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                    context,
                  ),
                  sliver: SliverAppBar.medium(
                    title: EmbeddedNativeControlArea(
                      child: dtb.DragToMoveArea(
                        child: Container(
                          width: double.infinity,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            infoController.bangumiItem.nameCn == ''
                                ? infoController.bangumiItem.name
                                : infoController.bangumiItem.nameCn,
                          ),
                        ),
                      ),
                    ),
                    automaticallyImplyLeading: false,
                    scrolledUnderElevation: 0.0,
                    leading: EmbeddedNativeControlArea(
                      child: IconButton(
                        onPressed: () {
                          Navigator.maybePop(context);
                        },
                        icon: Icon(Icons.arrow_back),
                      ),
                    ),
                    actions: [
                      if (innerBoxIsScrolled)
                        EmbeddedNativeControlArea(
                          child: CollectButton(
                            bangumiItem: infoController.bangumiItem,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      EmbeddedNativeControlArea(
                        child: IconButton(
                          onPressed: () {
                            launchUrl(
                              Uri.parse(
                                'https://bangumi.tv/subject/${infoController.bangumiItem.id}',
                              ),
                              mode: LaunchMode.externalApplication,
                            );
                          },
                          icon: const Icon(Icons.open_in_browser_rounded),
                        ),
                      ),
                      if (!showWindowButton && isDesktop())
                        CloseButton(onPressed: () => windowManager.close()),
                      SizedBox(width: 8),
                    ],
                    toolbarHeight: (Platform.isMacOS && showWindowButton)
                        ? kToolbarHeight + 22
                        : kToolbarHeight,
                    stretch: true,
                    centerTitle: false,
                    expandedHeight: (Platform.isMacOS && showWindowButton)
                        ? 308 + kTextTabBarHeight + kToolbarHeight + 22
                        : 308 + kTextTabBarHeight + kToolbarHeight,
                    collapsedHeight: (Platform.isMacOS && showWindowButton)
                        ? kTextTabBarHeight +
                            kToolbarHeight +
                            MediaQuery.paddingOf(context).top +
                            22
                        : kTextTabBarHeight +
                            kToolbarHeight +
                            MediaQuery.paddingOf(context).top,
                    flexibleSpace: FlexibleSpaceBar(
                      collapseMode: CollapseMode.pin,
                      background: Observer(
                        builder: (context) {
                          final showBangumiInfoSkeleton =
                              _isShowingBangumiInfoSkeleton;
                          return Stack(
                            children: [
                              // No background image when loading to make loading looks better
                              if (!showBangumiInfoSkeleton)
                                Positioned.fill(
                                  bottom: kTextTabBarHeight,
                                  child: IgnorePointer(
                                    child: _InfoHeaderBackground(
                                      imageUrl: infoController
                                              .bangumiItem.images['large'] ??
                                          '',
                                    ),
                                  ),
                                ),
                              SafeArea(
                                bottom: false,
                                child: EmbeddedNativeControlArea(
                                  child: Align(
                                    alignment: Alignment.topCenter,
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        kToolbarHeight,
                                        16,
                                        0,
                                      ),
                                      child: BangumiInfoCardV(
                                        bangumiItem: infoController.bangumiItem,
                                        isLoading: showBangumiInfoSkeleton,
                                        showRating: showRating,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    forceElevated: innerBoxIsScrolled,
                    bottom: TabBar(
                      controller: infoTabController,
                      isScrollable: true,
                      tabAlignment: TabAlignment.center,
                      dividerHeight: 0,
                      tabs: _infoTabs.map((name) => Tab(text: name)).toList(),
                    ),
                  ),
                ),
              ];
            },
            body: Observer(
              builder: (context) {
                final showBangumiInfoSkeleton = _isShowingBangumiInfoSkeleton;
                return InfoTabView(
                  tabController: infoTabController,
                  bangumiItem: infoController.bangumiItem,
                  isLoading: showBangumiInfoSkeleton,
                );
              },
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            tooltip: '开始观看',
            onPressed: () async {
              showModalBottomSheet(
                isScrollControlled: true,
                constraints: BoxConstraints(
                  maxHeight: (MediaQuery.sizeOf(context).height >=
                          LayoutBreakpoint.compact['height']!)
                      ? MediaQuery.of(context).size.height * 3 / 4
                      : MediaQuery.of(context).size.height,
                  maxWidth: (MediaQuery.sizeOf(context).width >=
                          LayoutBreakpoint.medium['width']!)
                      ? MediaQuery.of(context).size.width * 9 / 16
                      : MediaQuery.of(context).size.width,
                ),
                clipBehavior: Clip.antiAlias,
                backgroundColor: Theme.of(
                  context,
                ).scaffoldBackgroundColor,
                showDragHandle: true,
                context: context,
                builder: (context) {
                  return SourceSheet(
                    tabController: sourceTabController,
                    infoController: infoController,
                  );
                },
              );
            },
            label: const Text('开始观看'),
            icon: const Icon(Icons.play_arrow_rounded),
          ),
        ),
      ),
    );
  }
}

class _InfoHeaderBackground extends StatelessWidget {
  const _InfoHeaderBackground({required this.imageUrl});

  static const double _downsample = 0.5;
  static const double _blurSigma = 15.0;
  static const double _opacity = 0.4;
  static const double _edgeBleed = 32.0;
  static const double _bottomFeatherHeight = 48.0;

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        if (width <= 0 || height <= 0) {
          return const SizedBox.shrink();
        }

        final rasterWidth = width * _downsample;
        final rasterHeight = (height + _edgeBleed) * _downsample;

        final backgroundColor = Theme.of(context).scaffoldBackgroundColor;

        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ShaderMask(
                shaderCallback: (bounds) {
                  return const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white, Colors.transparent],
                    stops: [0.8, 1],
                  ).createShader(bounds);
                },
                child: Align(
                  alignment: Alignment.topCenter,
                  child: RepaintBoundary(
                    child: Transform.scale(
                      scale: 1 / _downsample,
                      alignment: Alignment.topCenter,
                      filterQuality: FilterQuality.low,
                      child: SizedBox(
                        width: rasterWidth,
                        height: rasterHeight,
                        child: ImageFiltered(
                          imageFilter: ImageFilter.blur(
                            sigmaX: _blurSigma * _downsample,
                            sigmaY: _blurSigma * _downsample,
                          ),
                          child: NetworkImgLayer(
                            src: imageUrl,
                            width: rasterWidth,
                            height: rasterHeight,
                            fadeInDuration: Duration.zero,
                            fadeOutDuration: Duration.zero,
                            filterQuality: FilterQuality.low,
                            color: Colors.white.withValues(alpha: _opacity),
                            colorBlendMode: BlendMode.modulate,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: _bottomFeatherHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        backgroundColor.withValues(alpha: 0),
                        backgroundColor.withValues(alpha: 0.55),
                        backgroundColor,
                      ],
                      stops: const [0, 0.72, 1],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
