import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/bangumi/bangumi_tag.dart';
import 'package:kazumi/modules/collect/collect_change_module.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/repositories/collect_crud_repository.dart';
import 'package:kazumi/services/storage/storage.dart';

void main() {
  group('CollectCrudRepository private sync event append', () {
    late Directory tempDir;
    late List<CollectedBangumi> upserts;
    late List<int> deletes;
    late CollectCrudRepository repository;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('aslan-collect-crud-');
      Hive.init(tempDir.path);
      _registerHiveAdapters();
      GStorage.collectibles =
          await Hive.openBox<CollectedBangumi>('collectibles');
      GStorage.favorites = await Hive.openBox<BangumiItem>('favorites');
      GStorage.collectChanges =
          await Hive.openBox<CollectedBangumiChange>('collectchanges');
      upserts = [];
      deletes = [];
      repository = CollectCrudRepository(
        appendCollectionUpsert: (collectible) async {
          upserts.add(collectible);
        },
        appendCollectionDelete: (bangumiId) async {
          deletes.add(bangumiId);
        },
      );
    });

    tearDown(() async {
      await Hive.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('appends sync events for user collection state changes', () async {
      await repository.addCollectible(_item(1, name: 'old'), 1);
      await repository.deleteCollectible(1);

      expect(upserts.single.type, CollectType.watching.value);
      expect(deletes, [1]);
    });

    test('does not append sync events for metadata-only updates', () async {
      await repository.addCollectible(_item(1, name: 'old'), 1);
      upserts.clear();

      await repository.updateCollectible(
        _item(1, name: 'new'),
        syncStateChange: false,
      );

      expect(upserts, isEmpty);
      expect(repository.getCollectible(1)?.bangumiItem.name, 'new');
      expect(repository.getCollectType(1), CollectType.watching.value);
    });
  });
}

BangumiItem _item(int id, {required String name}) {
  return BangumiItem(
    id: id,
    type: 2,
    name: name,
    nameCn: name,
    summary: '',
    airDate: '',
    airWeekday: 0,
    rank: 0,
    images: const {},
    tags: const [],
    alias: const [],
    ratingScore: 0,
    votes: 0,
    votesCount: const [],
    info: '',
  );
}

void _registerHiveAdapters() {
  _registerBangumiItemAdapter();
  _registerBangumiTagAdapter();
  _registerCollectedBangumiAdapter();
  _registerCollectedBangumiChangeAdapter();
}

void _registerBangumiItemAdapter() {
  if (!Hive.isAdapterRegistered(0)) {
    Hive.registerAdapter<BangumiItem>(BangumiItemAdapter());
  }
}

void _registerBangumiTagAdapter() {
  if (!Hive.isAdapterRegistered(4)) {
    Hive.registerAdapter<BangumiTag>(BangumiTagAdapter());
  }
}

void _registerCollectedBangumiAdapter() {
  if (!Hive.isAdapterRegistered(3)) {
    Hive.registerAdapter<CollectedBangumi>(CollectedBangumiAdapter());
  }
}

void _registerCollectedBangumiChangeAdapter() {
  if (!Hive.isAdapterRegistered(5)) {
    Hive.registerAdapter<CollectedBangumiChange>(
      CollectedBangumiChangeAdapter(),
    );
  }
}
