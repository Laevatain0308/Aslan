import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/collect/collect_change_module.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/sync/private_sync_service.dart';

/// 收藏CRUD数据访问接口
///
/// 提供收藏数据的增删改查操作
abstract class ICollectCrudRepository {
  /// 获取所有收藏
  List<CollectedBangumi> getAllCollectibles();

  /// 获取单个收藏
  ///
  /// [id] 番剧ID
  /// 返回收藏对象，如果不存在返回null
  CollectedBangumi? getCollectible(int id);

  /// 获取收藏类型
  ///
  /// [id] 番剧ID
  /// 返回收藏类型值，未收藏返回0
  int getCollectType(int id);

  /// 添加或更新收藏
  ///
  /// [bangumiItem] 番剧信息
  /// [type] 收藏类型
  Future<void> addCollectible(BangumiItem bangumiItem, int type);

  /// 更新收藏的番剧信息
  ///
  /// [bangumiItem] 更新后的番剧信息
  Future<void> updateCollectible(
    BangumiItem bangumiItem, {
    bool syncStateChange = true,
  });

  /// 删除收藏
  ///
  /// [id] 番剧ID
  Future<void> deleteCollectible(int id);

  /// 记录收藏变更（用于WebDAV同步）
  ///
  /// [change] 变更记录
  Future<void> addCollectChange(CollectedBangumiChange change);

  /// 获取旧版收藏列表（用于迁移）
  List<BangumiItem> getFavorites();

  /// 清空旧版收藏（迁移后）
  Future<void> clearFavorites();
}

/// 收藏CRUD数据访问实现类
///
/// 基于Hive实现的收藏CRUD数据访问层
class CollectCrudRepository implements ICollectCrudRepository {
  CollectCrudRepository({
    Future<void> Function(CollectedBangumi collectible)? appendCollectionUpsert,
    Future<void> Function(int bangumiId)? appendCollectionDelete,
  })  : _appendCollectionUpsert = appendCollectionUpsert,
        _appendCollectionDelete = appendCollectionDelete;

  final _collectiblesBox = GStorage.collectibles;
  final _favoritesBox = GStorage.favorites;
  final Future<void> Function(CollectedBangumi collectible)?
      _appendCollectionUpsert;
  final Future<void> Function(int bangumiId)? _appendCollectionDelete;

  @override
  List<CollectedBangumi> getAllCollectibles() {
    try {
      return _collectiblesBox.values.cast<CollectedBangumi>().toList();
    } catch (e) {
      KazumiLogger().w(
        'GStorage: get all collectibles failed',
        error: e,
      );
      return [];
    }
  }

  @override
  CollectedBangumi? getCollectible(int id) {
    try {
      return _collectiblesBox.get(id);
    } catch (e) {
      KazumiLogger().w(
        'GStorage: get collectible failed. id=$id',
        error: e,
      );
      return null;
    }
  }

  @override
  int getCollectType(int id) {
    try {
      final collectible = _collectiblesBox.get(id);
      return collectible?.type ?? 0;
    } catch (e) {
      KazumiLogger().w(
        'GStorage: get collect type failed. id=$id',
        error: e,
      );
      return 0;
    }
  }

  @override
  Future<void> addCollectible(BangumiItem bangumiItem, int type) async {
    try {
      final collectedBangumi = CollectedBangumi(
        bangumiItem,
        DateTime.now(),
        type,
      );
      await GStorage.putCollectible(collectedBangumi);
      await _appendPrivateSyncSafely(
        () =>
            _appendCollectionUpsert?.call(collectedBangumi) ??
            PrivateSyncService().appendCollectionUpsert(collectedBangumi),
      );
    } catch (e, stackTrace) {
      KazumiLogger().e(
        'GStorage: add collectible failed. id=${bangumiItem.id}, type=$type',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  Future<void> updateCollectible(
    BangumiItem bangumiItem, {
    bool syncStateChange = true,
  }) async {
    try {
      final collectible = _collectiblesBox.get(bangumiItem.id);
      if (collectible == null) {
        KazumiLogger().i(
          'GStorage: update collectible failed. collectible not found, id=${bangumiItem.id}',
        );
        return;
      }
      collectible.bangumiItem = bangumiItem;
      await GStorage.putCollectible(collectible);
      if (syncStateChange) {
        await _appendPrivateSyncSafely(
          () =>
              _appendCollectionUpsert?.call(collectible) ??
              PrivateSyncService().appendCollectionUpsert(collectible),
        );
      }
    } catch (e, stackTrace) {
      KazumiLogger().e(
        'GStorage: update collectible failed. id=${bangumiItem.id}',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  Future<void> deleteCollectible(int id) async {
    try {
      await GStorage.deleteCollectible(id);
      await _appendPrivateSyncSafely(
        () =>
            _appendCollectionDelete?.call(id) ??
            PrivateSyncService().appendCollectionDelete(id),
      );
    } catch (e, stackTrace) {
      KazumiLogger().e(
        'GStorage: delete collectible failed. id=$id',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  Future<void> addCollectChange(CollectedBangumiChange change) async {
    try {
      await GStorage.putCollectChange(change);
    } catch (e, stackTrace) {
      KazumiLogger().e(
        'GStorage: record collect change failed. changeId=${change.id}',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  List<BangumiItem> getFavorites() {
    try {
      return _favoritesBox.values.cast<BangumiItem>().toList();
    } catch (e) {
      KazumiLogger().i(
        'GStorage: get favorites failed',
        error: e,
      );
      return [];
    }
  }

  @override
  Future<void> clearFavorites() async {
    try {
      await _favoritesBox.clear();
      await _favoritesBox.flush();
    } catch (e) {
      KazumiLogger().i(
        'GStorage: clear favorites failed',
        error: e,
      );
      rethrow;
    }
  }

  Future<void> _appendPrivateSyncSafely(Future<void> Function() append) async {
    try {
      await append();
    } catch (e, stackTrace) {
      KazumiLogger().e(
        'PrivateSync: failed to append collection change',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
}
