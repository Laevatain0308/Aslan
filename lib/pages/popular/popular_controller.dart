import 'package:flutter/material.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/request/apis/laeva_bangumi_api.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:mobx/mobx.dart';

part 'popular_controller.g.dart';

class PopularController = _PopularController with _$PopularController;

abstract class _PopularController with Store {
  static const int _pageSize = 24;

  final ScrollController scrollController = ScrollController();

  @observable
  String currentTag = '';

  @observable
  ObservableList<BangumiItem> bangumiList = ObservableList.of([]);

  @observable
  ObservableList<BangumiItem> trendList = ObservableList.of([]);

  double scrollOffset = 0.0;

  @observable
  bool isLoadingMore = false;

  @observable
  bool isTimeOut = false;

  void setCurrentTag(String s) {
    currentTag = s;
  }

  void clearBangumiList() {
    bangumiList.clear();
  }

  Future<void> queryBangumiByTrend({String type = 'add'}) async {
    if (type == 'init') {
      trendList.clear();
    }
    isLoadingMore = true;
    isTimeOut = false;
    try {
      final result = await LaevaBangumiApi.getUpdates(
        limit: trendList.length + _pageSize,
      );
      trendList
        ..clear()
        ..addAll(result.map((item) => item.toBangumiItem()));
    } catch (e, stackTrace) {
      KazumiLogger().e(
        'LaevaBangumi: resolve updates failed',
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      isLoadingMore = false;
      isTimeOut = trendList.isEmpty;
    }
  }

  Future<void> queryBangumiByTag({String type = 'add'}) async {
    if (type == 'add' && bangumiList.isNotEmpty) {
      return;
    }
    if (type == 'init') {
      bangumiList.clear();
    }
    isLoadingMore = true;
    isTimeOut = false;
    var tag = currentTag;
    try {
      final result = await LaevaBangumiApi.search(tag, byTag: true);
      bangumiList
        ..clear()
        ..addAll(result.map((item) => item.toBangumiItem()));
    } catch (e, stackTrace) {
      KazumiLogger().e(
        'LaevaBangumi: resolve tag search failed',
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      isLoadingMore = false;
      isTimeOut = bangumiList.isEmpty;
    }
  }
}
