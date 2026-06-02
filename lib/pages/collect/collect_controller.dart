import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/sync/webdav.dart';
import 'package:kazumi/repositories/collect_crud_repository.dart';
import 'package:kazumi/repositories/collect_repository.dart';
import 'package:hive_ce/hive.dart';
import 'package:mobx/mobx.dart';
import 'package:kazumi/services/logging/logger.dart';

part 'collect_controller.g.dart';

class CollectController = _CollectController with _$CollectController;

abstract class _CollectController with Store {
  final _collectCrudRepository = Modular.get<ICollectCrudRepository>();
  final _collectRepository = Modular.get<ICollectRepository>();

  Box setting = GStorage.setting;
  List<BangumiItem> get favorites => _collectCrudRepository.getFavorites();

  @observable
  ObservableList<CollectedBangumi> collectibles =
      ObservableList<CollectedBangumi>();

  void loadCollectibles() {
    collectibles.clear();
    collectibles.addAll(_collectCrudRepository.getAllCollectibles());
  }

  int getCollectType(BangumiItem bangumiItem) {
    return _collectCrudRepository.getCollectType(bangumiItem.id);
  }

  BangumiItem? getCollectibleBangumiItem(int id) {
    return _collectCrudRepository.getCollectible(id)?.bangumiItem;
  }

  @action
  Future<void> addCollect(BangumiItem bangumiItem, {type = 1}) async {
    if (type == 0) {
      await deleteCollect(bangumiItem);
      return;
    }

    final int currentCollectType = getCollectType(bangumiItem);
    final int collectChangeAction = currentCollectType == 0 ? 1 : 2;

    await _collectCrudRepository.addCollectible(bangumiItem, type);
    await GStorage.appendCollectChange(
      bangumiId: bangumiItem.id,
      action: collectChangeAction,
      type: type,
    );
    loadCollectibles();
  }

  @action
  Future<void> deleteCollect(BangumiItem bangumiItem) async {
    await _deleteCollectLocally(bangumiItem);
  }

  Future<void> _deleteCollectLocally(BangumiItem bangumiItem) async {
    await _collectCrudRepository.deleteCollectible(bangumiItem.id);
    await GStorage.appendCollectChange(
      bangumiId: bangumiItem.id,
      action: 3,
      type: 5,
    );
    loadCollectibles();
  }

  Future<void> updateLocalCollect(BangumiItem bangumiItem) async {
    await _collectCrudRepository.updateCollectible(bangumiItem);
    loadCollectibles();
  }

  Future<bool> syncCollectibles({bool showSuccessToast = true}) async {
    final bool webDavCollectEnable =
        setting.get(SettingBoxKey.webDavEnableCollect, defaultValue: false);
    if (!webDavCollectEnable) {
      KazumiDialog.showToast(message: '未开启WebDav收藏同步');
      return false;
    }
    if (!WebDav().initialized) {
      KazumiDialog.showToast(message: '未开启WebDav同步或配置无效');
      return false;
    }
    bool flag = true;
    try {
      await WebDav().ping();
    } catch (e) {
      KazumiLogger().e('WebDav: WebDav connection failed', error: e);
      KazumiDialog.showToast(message: 'WebDav连接失败: $e');
      flag = false;
    }
    if (!flag) {
      return false;
    }
    try {
      await WebDav().syncCollectibles();
      if (showSuccessToast) {
        KazumiDialog.showToast(message: 'WebDav同步完成');
      }
    } catch (e) {
      KazumiDialog.showToast(message: 'WebDav同步失败 $e');
      return false;
    }
    loadCollectibles();
    return true;
  }

  /// Only upload local collectibles and change logs to WebDAV, without downloading and merging.
  /// Used by full sync to push Bangumi-updated local changes back to WebDAV.
  Future<bool> uploadCollectiblesToWebDav(
      {bool showSuccessToast = true}) async {
    final bool webDavCollectEnable =
        setting.get(SettingBoxKey.webDavEnableCollect, defaultValue: false);
    if (!webDavCollectEnable) {
      KazumiDialog.showToast(message: '未开启WebDav收藏同步');
      return false;
    }
    if (!WebDav().initialized) {
      KazumiDialog.showToast(message: '未开启WebDav同步或配置无效');
      return false;
    }
    bool flag = true;
    try {
      await WebDav().ping();
    } catch (e) {
      KazumiLogger().e('WebDav: WebDav connection failed', error: e);
      KazumiDialog.showToast(message: 'WebDav连接失败: $e');
      flag = false;
    }
    if (!flag) {
      return false;
    }
    try {
      await WebDav().updateCollectibles();
      if (showSuccessToast) {
        KazumiDialog.showToast(message: 'WebDav上传完成');
      }
    } catch (e) {
      KazumiDialog.showToast(message: 'WebDav上传失败 $e');
      return false;
    }
    return true;
  }

  // migrate collect from old version (favorites)
  Future<void> migrateCollect() async {
    if (favorites.isNotEmpty) {
      int count = 0;
      for (BangumiItem bangumiItem in favorites) {
        // Migration should never depend on runtime Bangumi initialization.
        // Persist locally and append change logs, then let later sync handle remote updates.
        final int currentCollectType = getCollectType(bangumiItem);
        final int collectChangeAction = currentCollectType == 0 ? 1 : 2;
        await _collectCrudRepository.addCollectible(bangumiItem, 1);
        await GStorage.appendCollectChange(
          bangumiId: bangumiItem.id,
          action: collectChangeAction,
          type: 1,
        );
        count++;
      }
      await _collectCrudRepository.clearFavorites();
      loadCollectibles();
      KazumiLogger().d(
          'GStorage: detected $count uncategorized favorites, migrated to collectibles');
    }
  }

  /// 根据收藏类型获取番剧ID集合
  ///
  /// [type] 收藏类型
  /// 返回番剧ID集合
  Set<int> getBangumiIdsByType(CollectType type) {
    return _collectRepository.getBangumiIdsByType(type);
  }

  /// 过滤掉指定收藏类型的番剧
  ///
  /// [bangumiList] 原始番剧列表
  /// [excludeType] 要排除的收藏类型
  /// 返回过滤后的番剧列表
  List<BangumiItem> filterBangumiByType(
      List<BangumiItem> bangumiList, CollectType excludeType) {
    final excludeIds = getBangumiIdsByType(excludeType);
    return bangumiList.where((item) => !excludeIds.contains(item.id)).toList();
  }

  /// Sync Bangumi collectibles.
  Future<bool> syncCollectiblesBangumi(
      {void Function(String message, int current, int total)? onProgress,
      bool showSuccessToast = true}) async {
    KazumiDialog.showToast(message: '远程追番同步暂未开放');
    return false;
  }
}
