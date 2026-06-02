import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/menu/menu.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/timeline/timeline_controller.dart';
import 'package:kazumi/bean/card/bangumi_timeline_card.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:provider/provider.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/error_widget.dart';
import 'package:kazumi/utils/device.dart';

class TimelinePage extends StatefulWidget {
  const TimelinePage({super.key});

  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage>
    with SingleTickerProviderStateMixin {
  final TimelineController timelineController =
      Modular.get<TimelineController>();
  late NavigationBarState navigationBarState;
  TabController? tabController;
  late bool showRating;
  final GlobalKey filterSectionKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    int weekday = DateTime.now().weekday - 1;
    tabController =
        TabController(vsync: this, length: tabs.length, initialIndex: weekday);
    navigationBarState =
        Provider.of<NavigationBarState>(context, listen: false);
    showRating =
        GStorage.setting.get(SettingBoxKey.showRating, defaultValue: true);
    if (timelineController.bangumiCalendar.isEmpty) {
      timelineController.init();
    }
  }

  @override
  void dispose() {
    tabController?.dispose();
    super.dispose();
  }

  void onBackPressed(BuildContext context) {
    if (KazumiDialog.observer.hasKazumiDialog) {
      KazumiDialog.dismiss();
      return;
    }
    navigationBarState.updateSelectedIndex(0);
    Modular.to.navigate('/tab/popular/');
  }

  final List<Tab> tabs = const <Tab>[
    Tab(text: '一'),
    Tab(text: '二'),
    Tab(text: '三'),
    Tab(text: '四'),
    Tab(text: '五'),
    Tab(text: '六'),
    Tab(text: '日'),
  ];

  Future<void> scrollToFilterSection() async {
    final filterContext = filterSectionKey.currentContext;
    if (filterContext == null) {
      return;
    }

    await Scrollable.ensureVisible(
      filterContext,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: 0.04,
    );
  }

  BoxConstraints buildTimelineBottomSheetConstraints(
    BuildContext context, {
    double? compactHeightFactor,
  }) {
    final mediaSize = MediaQuery.sizeOf(context);
    final maxWidth = mediaSize.width >= LayoutBreakpoint.medium['width']!
        ? mediaSize.width * 9 / 16
        : mediaSize.width;
    final maxHeight = compactHeightFactor != null
        ? (mediaSize.height >= LayoutBreakpoint.compact['height']!
            ? mediaSize.height * compactHeightFactor
            : mediaSize.height)
        : double.infinity;

    return BoxConstraints(
      maxWidth: maxWidth,
      maxHeight: maxHeight,
    );
  }

  Widget buildTimelineBottomSheetHeaderCard(
    BuildContext context, {
    required String title,
    required String description,
    required Widget footer,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.headlineSmall?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              IconButton.filledTonal(
                onPressed: KazumiDialog.dismiss,
                tooltip: '关闭',
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 16),
          footer,
        ],
      ),
    );
  }

  Widget buildTimelineBottomSheetShell(
    BuildContext context, {
    required Widget header,
    required Widget body,
    bool showDragHandle = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDragHandle) ...[
            const SizedBox(height: 12),
            Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ],
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              showDragHandle ? 12 : 16,
              16,
              8,
            ),
            child: header,
          ),
          Flexible(child: body),
        ],
      ),
    );
  }

  String getSortTypeLabel(int sortType) {
    switch (sortType) {
      case 1:
        return '时间优先';
      case 2:
        return '评分优先';
      case 3:
        return '热度优先';
      default:
        return '热度优先';
    }
  }

  int getEnabledTimelineFilterCount() {
    var enabledCount = 0;
    if (timelineController.notShowAbandonedBangumis) {
      enabledCount++;
    }
    if (timelineController.notShowWatchedBangumis) {
      enabledCount++;
    }
    if (timelineController.onlyShowWatchingBangumis) {
      enabledCount++;
    }
    return enabledCount;
  }

  Widget buildTimelineOptionSummaryChip(
    BuildContext context, {
    required String label,
    bool highlighted = false,
    VoidCallback? onTap,
    IconData? trailingIcon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final foregroundColor =
        highlighted ? colorScheme.onSecondaryContainer : colorScheme.onSurface;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: highlighted
                ? colorScheme.secondaryContainer
                : colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: textTheme.labelLarge?.copyWith(
                  color: foregroundColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: 6),
                Icon(
                  trailingIcon,
                  size: 18,
                  color: foregroundColor,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget buildTimelineOptionsSheetHeader(BuildContext context) {
    return buildTimelineBottomSheetHeaderCard(
      context,
      title: '时间线选项',
      description: '调整排序和过滤条件，结果会立即应用到当前时间线。',
      footer: Observer(
        builder: (context) {
          final enabledFilterCount = getEnabledTimelineFilterCount();
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              buildTimelineOptionSummaryChip(
                context,
                label: '当前排序 ${getSortTypeLabel(timelineController.sortType)}',
                highlighted: true,
              ),
              buildTimelineOptionSummaryChip(
                context,
                label: enabledFilterCount == 0
                    ? '未启用过滤条件'
                    : '已启用 $enabledFilterCount 个过滤条件',
                onTap: scrollToFilterSection,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget buildTimelineOptionSection(
    BuildContext context, {
    required String title,
    required String description,
    required Widget child,
    Key? sectionKey,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      key: sectionKey,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget buildSortOptionTile(
    BuildContext context, {
    required int sortType,
    required String title,
    required String description,
    required IconData icon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isSelected = timelineController.sortType == sortType;

    return Ink(
      decoration: BoxDecoration(
        color: isSelected
            ? colorScheme.secondaryContainer
            : colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected
              ? colorScheme.secondary.withValues(alpha: 0.3)
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        leading: Icon(
          icon,
          color: isSelected
              ? colorScheme.onSecondaryContainer
              : colorScheme.onSurfaceVariant,
        ),
        title: Text(
          title,
          style: textTheme.titleMedium?.copyWith(
            color: isSelected
                ? colorScheme.onSecondaryContainer
                : colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          description,
          style: textTheme.bodySmall?.copyWith(
            color: isSelected
                ? colorScheme.onSecondaryContainer.withValues(alpha: 0.82)
                : colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Icon(
          isSelected
              ? Icons.check_circle_rounded
              : Icons.radio_button_unchecked_rounded,
          color: isSelected
              ? colorScheme.onSecondaryContainer
              : colorScheme.onSurfaceVariant,
        ),
        onTap: () {
          KazumiDialog.dismiss();
          timelineController.changeSortType(sortType);
        },
      ),
    );
  }

  Widget buildFilterOptionTile(
    BuildContext context, {
    required String title,
    required String description,
    required bool value,
    required ValueChanged<bool> onChanged,
    required IconData icon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Ink(
      decoration: BoxDecoration(
        color: value
            ? colorScheme.secondaryContainer.withValues(alpha: 0.5)
            : colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: value
              ? colorScheme.secondary.withValues(alpha: 0.24)
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        leading: Icon(
          icon,
          color: value
              ? colorScheme.onSecondaryContainer
              : colorScheme.onSurfaceVariant,
        ),
        title: Text(
          title,
          style: textTheme.titleMedium?.copyWith(
            color: value
                ? colorScheme.onSecondaryContainer
                : colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          description,
          style: textTheme.bodySmall?.copyWith(
            color: value
                ? colorScheme.onSecondaryContainer.withValues(alpha: 0.82)
                : colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Switch(
          value: value,
          onChanged: onChanged,
        ),
        onTap: () {
          onChanged(!value);
        },
      ),
    );
  }

  Widget showFilterSwitcher() {
    return buildTimelineOptionSection(
      context,
      sectionKey: filterSectionKey,
      title: '过滤器',
      description: '按收藏状态收起不需要显示的条目，支持连续调整。',
      child: Column(
        children: [
          Observer(
            builder: (context) => buildFilterOptionTile(
              context,
              title: '不显示已抛弃的番剧',
              description: '隐藏已经标记为抛弃的条目。',
              value: timelineController.notShowAbandonedBangumis,
              onChanged: (value) {
                timelineController.setNotShowAbandonedBangumis(value);
              },
              icon: Icons.heart_broken_rounded,
            ),
          ),
          const SizedBox(height: 12),
          Observer(
            builder: (context) => buildFilterOptionTile(
              context,
              title: '不显示已看过的番剧',
              description: '把已经看完的条目从时间线中移除。',
              value: timelineController.notShowWatchedBangumis,
              onChanged: (value) {
                timelineController.setNotShowWatchedBangumis(value);
              },
              icon: Icons.task_alt_rounded,
            ),
          ),
          const SizedBox(height: 12),
          Observer(
            builder: (context) => buildFilterOptionTile(
              context,
              title: '只显示在看的番剧',
              description: '聚焦当前正在追更的条目。',
              value: timelineController.onlyShowWatchingBangumis,
              onChanged: (value) {
                timelineController.setOnlyShowWatchingBangumis(value);
              },
              icon: Icons.live_tv_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget showSortSwitcher() {
    return buildTimelineOptionSection(
      context,
      title: '排序方式',
      description: '选择每一天内番剧卡片的排列方式。',
      child: Column(
        children: [
          buildSortOptionTile(
            context,
            sortType: 3,
            title: '按热度排序',
            description: '优先展示讨论度和关注度更高的条目。',
            icon: Icons.local_fire_department_rounded,
          ),
          const SizedBox(height: 12),
          buildSortOptionTile(
            context,
            sortType: 2,
            title: '按评分排序',
            description: '优先展示评分更高的条目。',
            icon: Icons.star_rounded,
          ),
          const SizedBox(height: 12),
          buildSortOptionTile(
            context,
            sortType: 1,
            title: '按时间排序',
            description: '恢复默认时间顺序，方便按播出节奏查看。',
            icon: Icons.schedule_rounded,
          ),
        ],
      ),
    );
  }

  Widget buildTimelineOptionsSheet(BuildContext context) {
    return buildTimelineBottomSheetShell(
      context,
      header: buildTimelineOptionsSheetHeader(context),
      body: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          showSortSwitcher(),
          const SizedBox(height: 12),
          showFilterSwitcher(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) {
          return;
        }
        onBackPressed(context);
      },
      child: Scaffold(
        appBar: SysAppBar(
          needTopOffset: false,
          toolbarHeight: 104,
          bottom: TabBar(
            controller: tabController,
            tabs: tabs,
            indicatorColor: Theme.of(context).colorScheme.primary,
          ),
          title: Observer(
            builder: (context) {
              return Text(timelineController.seasonString);
            },
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () async {
            KazumiDialog.showBottomSheet(
              backgroundColor: Theme.of(context).colorScheme.surface,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              isScrollControlled: true,
              constraints: buildTimelineBottomSheetConstraints(
                context,
                compactHeightFactor: 2 / 3,
              ),
              clipBehavior: Clip.antiAlias,
              useSafeArea: true,
              context: context,
              builder: (context) {
                return buildTimelineOptionsSheet(context);
              },
            );
          },
          child: const Icon(Icons.tune),
        ),
        body: Observer(builder: (context) {
          if (timelineController.isLoading &&
              timelineController.bangumiCalendar.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }
          if (timelineController.isTimeOut) {
            return Center(
              child: SizedBox(
                height: 400,
                child: GeneralErrorWidget(
                  errMsg: '啊咧（⊙.⊙） 无法加载时间表',
                  actions: [
                    GeneralErrorButton(
                      onPressed: timelineController.getSchedules,
                      text: '点击重试',
                    ),
                  ],
                ),
              ),
            );
          }
          return TabBarView(
            controller: tabController,
            children: contentGrid(timelineController.bangumiCalendar),
          );
        }),
      ),
    );
  }

  List<Widget> contentGrid(List<List<BangumiItem>> bangumiCalendar) {
    List<Widget> gridViewList = [];
    int crossCount = 1;
    if (MediaQuery.sizeOf(context).width > LayoutBreakpoint.compact['width']!) {
      crossCount = 2;
    }
    if (MediaQuery.sizeOf(context).width > LayoutBreakpoint.medium['width']!) {
      crossCount = 3;
    }
    double cardHeight = isDesktop() ? 160 : (isTablet() ? 140 : 120);
    for (var bangumiList in bangumiCalendar) {
      // 根据过滤器设置过滤番剧
      var filteredList = bangumiList;

      if (timelineController.notShowAbandonedBangumis) {
        final abandonedBangumiIds =
            timelineController.loadAbandonedBangumiIds();
        filteredList = filteredList
            .where((item) => !abandonedBangumiIds.contains(item.id))
            .toList();
      }

      if (timelineController.notShowWatchedBangumis) {
        final watchedBangumiIds = timelineController.loadWatchedBangumiIds();
        filteredList = filteredList
            .where((item) => !watchedBangumiIds.contains(item.id))
            .toList();
      }

      if (timelineController.onlyShowWatchingBangumis) {
        final watchingBangumiIds = timelineController.loadWatchingBangumiIds();
        filteredList = filteredList
            .where((item) => watchingBangumiIds.contains(item.id))
            .toList();
      }

      gridViewList.add(
        CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  mainAxisSpacing: StyleString.cardSpace - 2,
                  crossAxisSpacing: StyleString.cardSpace,
                  crossAxisCount: crossCount,
                  mainAxisExtent: cardHeight + 12,
                ),
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int index) {
                    if (filteredList.isEmpty) return null;
                    final item = filteredList[index];
                    return BangumiTimelineCard(
                        bangumiItem: item,
                        cardHeight: cardHeight,
                        showRating: showRating);
                  },
                  childCount:
                      filteredList.isNotEmpty ? filteredList.length : 10,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return gridViewList;
  }
}
