import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/error_widget.dart';
import 'package:kazumi/modules/laeva/laeva_bangumi_models.dart';
import 'package:kazumi/pages/info/info_controller.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/request/apis/laeva_bangumi_api.dart';
import 'package:kazumi/services/logging/logger.dart';

class SourceSheet extends StatefulWidget {
  const SourceSheet({
    super.key,
    required this.tabController,
    required this.infoController,
  });

  final TabController tabController;
  final InfoController infoController;

  @override
  State<SourceSheet> createState() => _SourceSheetState();
}

class _SourceSheetState extends State<SourceSheet> {
  final VideoPageController videoPageController =
      Modular.get<VideoPageController>();

  bool loading = true;
  String? errorMessage;
  LaevaBangumiDetail? detail;

  @override
  void initState() {
    super.initState();
    loadDetail();
  }

  Future<void> loadDetail() async {
    setState(() {
      loading = true;
      errorMessage = null;
    });
    try {
      final cached = widget.infoController.laevaBangumiDetail;
      final nextDetail = cached ??
          (await LaevaBangumiApi.getDetail(
            LaevaBangumiMetadata.apiIdFromItem(
              widget.infoController.bangumiItem,
            ),
          ))
              ?.data;
      if (nextDetail == null) {
        throw const LaevaBangumiApiException('未找到播放详情');
      }
      detail = nextDetail;
      widget.infoController.laevaBangumiDetail = nextDetail;
      nextDetail.applyToBangumiItem(widget.infoController.bangumiItem);
    } catch (e) {
      KazumiLogger().e(
        'SourceSheet: failed to load LaevaBangumi detail',
        error: e,
      );
      errorMessage = e.toString();
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  Future<void> startPlayback({int initialRoad = 0}) async {
    final currentDetail = detail;
    if (currentDetail == null) {
      return;
    }
    if (!currentDetail.hasPlayableEpisodes) {
      KazumiDialog.showToast(message: '暂无可播放剧集');
      return;
    }
    videoPageController.bangumiItem = widget.infoController.bangumiItem;
    videoPageController.initLaevaSource(currentDetail, road: initialRoad);
    Modular.to.pop();
    Modular.to.pushNamed('/video/');
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final currentDetail = detail;
    if (errorMessage != null || currentDetail == null) {
      return GeneralErrorWidget(
        errMsg: errorMessage ?? '加载失败',
        actions: [GeneralErrorButton(onPressed: loadDetail, text: '重试')],
      );
    }

    return SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    laevaBangumiSourceName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                FilledButton.icon(
                  onPressed: currentDetail.hasPlayableEpisodes
                      ? () => startPlayback()
                      : null,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('开始播放'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: currentDetail.channels.isEmpty
                ? const Center(child: Text('暂无播放线路'))
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: currentDetail.channels.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final channel = currentDetail.channels[index];
                      return Card(
                        elevation: 0,
                        child: ListTile(
                          leading: const Icon(Icons.playlist_play_rounded),
                          title: Text(channel.name),
                          subtitle: Text('${channel.episodes.length} 集'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: channel.episodes.isEmpty
                              ? null
                              : () {
                                  startPlayback(initialRoad: index);
                                },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
