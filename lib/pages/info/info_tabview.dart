import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/utils/device.dart';
import 'package:skeletonizer/skeletonizer.dart';

class InfoTabView extends StatefulWidget {
  const InfoTabView({
    super.key,
    required this.tabController,
    required this.bangumiItem,
    required this.isLoading,
  });

  final TabController tabController;
  final BangumiItem bangumiItem;
  final bool isLoading;

  @override
  State<InfoTabView> createState() => _InfoTabViewState();
}

class _InfoTabViewState extends State<InfoTabView>
    with SingleTickerProviderStateMixin {
  final maxWidth = 950.0;
  bool fullIntro = false;
  bool fullTag = false;

  Widget get infoBody {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SizedBox(
          width: MediaQuery.sizeOf(context).width > maxWidth
              ? maxWidth
              : MediaQuery.sizeOf(context).width - 32,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('简介', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final span = TextSpan(text: widget.bangumiItem.summary);
                  final tp = TextPainter(
                    text: span,
                    textDirection: TextDirection.ltr,
                  );
                  tp.layout(maxWidth: constraints.maxWidth);
                  final numLines = tp.computeLineMetrics().length;
                  if (numLines > 7) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        SizedBox(
                          height: fullIntro ? null : 120,
                          width: MediaQuery.sizeOf(context).width > maxWidth
                              ? maxWidth
                              : MediaQuery.sizeOf(context).width - 32,
                          child: SelectableText(
                            widget.bangumiItem.summary,
                            textAlign: TextAlign.start,
                            scrollBehavior: const ScrollBehavior().copyWith(
                              scrollbars: false,
                            ),
                            scrollPhysics: NeverScrollableScrollPhysics(),
                            selectionHeightStyle: ui.BoxHeightStyle.max,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              fullIntro = !fullIntro;
                            });
                          },
                          child: Text(fullIntro ? '加载更少' : '加载更多'),
                        ),
                      ],
                    );
                  } else {
                    return SelectableText(
                      widget.bangumiItem.summary,
                      textAlign: TextAlign.start,
                      scrollPhysics: NeverScrollableScrollPhysics(),
                      selectionHeightStyle: ui.BoxHeightStyle.max,
                    );
                  }
                },
              ),
              const SizedBox(height: 16),
              Text('标签', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8.0,
                runSpacing: isDesktop() ? 8 : 0,
                children: List<Widget>.generate(
                  fullTag || widget.bangumiItem.tags.length < 13
                      ? widget.bangumiItem.tags.length
                      : 13,
                  (int index) {
                    if (!fullTag && index == 12) {
                      return ActionChip(
                        label: Text(
                          '更多 +',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        onPressed: () {
                          setState(() {
                            fullTag = !fullTag;
                          });
                        },
                      );
                    }
                    return ActionChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${widget.bangumiItem.tags[index].name} '),
                          Text(
                            '${widget.bangumiItem.tags[index].count}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      onPressed: () {
                        final tagName = Uri.encodeComponent(
                          widget.bangumiItem.tags[index].name,
                        );
                        Modular.to.pushNamed('/search/$tagName');
                      },
                    );
                  },
                ).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget get infoBodyBone {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SizedBox(
          width: MediaQuery.sizeOf(context).width > maxWidth
              ? maxWidth
              : MediaQuery.sizeOf(context).width - 32,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Skeletonizer.zone(child: Bone.text(fontSize: 18, width: 50)),
              const SizedBox(height: 8),
              Skeletonizer.zone(child: Bone.multiText(lines: 7)),
              const SizedBox(height: 16),
              Skeletonizer.zone(child: Bone.text(fontSize: 18, width: 50)),
              const SizedBox(height: 8),
              if (widget.isLoading)
                Skeletonizer.zone(
                  child: Wrap(
                    spacing: 8.0,
                    runSpacing: 8.0,
                    children: List.generate(
                      4,
                      (_) => Bone.button(uniRadius: 8, height: 32),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TabBarView(
      controller: widget.tabController,
      children: [
        Builder(
          builder: (BuildContext context) {
            return CustomScrollView(
              scrollBehavior: const ScrollBehavior().copyWith(
                scrollbars: false,
              ),
              key: PageStorageKey<String>('概览'),
              slivers: <Widget>[
                SliverOverlapInjector(
                  handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                    context,
                  ),
                ),
                SliverToBoxAdapter(
                  child: SafeArea(
                    top: false,
                    bottom: false,
                    child: widget.isLoading ? infoBodyBone : infoBody,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
