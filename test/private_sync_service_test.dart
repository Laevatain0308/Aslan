import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/bangumi/bangumi_tag.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/modules/sync/private_sync_models.dart';
import 'package:kazumi/request/apis/private_sync_api.dart';
import 'package:kazumi/services/sync/private_sync_service.dart';
import 'package:kazumi/services/storage/storage.dart';

void main() {
  group('PrivateSyncLocalStore', () {
    late Directory tempDir;
    late _MemorySettings settings;
    late PrivateSyncLocalStore store;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('aslan-private-sync-');
      settings = _MemorySettings();
      store = PrivateSyncLocalStore(
        settings: settings,
        localEventFile: File('${tempDir.path}/private-sync.local.jsonl'),
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('creates and reuses a UUID-shaped device id', () async {
      final first = await store.getDeviceId();
      final second = await store.getDeviceId();

      expect(first, second);
      expect(
        first,
        matches(RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        )),
      );
    });

    test('increments event sequence numbers', () async {
      expect(await store.nextSeq(), 1);
      expect(await store.nextSeq(), 2);
      expect(settings.values[PrivateSyncLocalStore.sequenceKey], 2);
    });

    test('appends reads and replaces jsonl events', () async {
      final event = const PrivateSyncEvent(
        eventId: 'device-a:1',
        deviceId: 'device-a',
        seq: 1,
        domain: 'watch',
        op: 'watch.clearAll',
        updatedAt: 1000,
        payload: {},
      );

      await store.appendEvent(event);
      expect((await store.readEvents()).single.eventId, 'device-a:1');

      await store.replaceEvents(const []);
      expect(await store.readEvents(), isEmpty);
    });
  });

  group('PrivateSyncWatchDebouncer', () {
    test('emits first progress and meaningful progress advances', () {
      final debouncer = PrivateSyncWatchDebouncer(
          minProgressDelta: const Duration(seconds: 20));

      expect(
        debouncer.shouldEmit(
          entityKey: 'a',
          episode: 1,
          road: 0,
          progress: const Duration(seconds: 1),
        ),
        isTrue,
      );
      expect(
        debouncer.shouldEmit(
          entityKey: 'a',
          episode: 1,
          road: 0,
          progress: const Duration(seconds: 10),
        ),
        isFalse,
      );
      expect(
        debouncer.shouldEmit(
          entityKey: 'a',
          episode: 1,
          road: 0,
          progress: const Duration(seconds: 25),
        ),
        isTrue,
      );
    });

    test('emits when episode or road changes', () {
      final debouncer = PrivateSyncWatchDebouncer(
          minProgressDelta: const Duration(seconds: 20));

      debouncer.shouldEmit(
        entityKey: 'a',
        episode: 1,
        road: 0,
        progress: const Duration(seconds: 30),
      );

      expect(
        debouncer.shouldEmit(
          entityKey: 'a',
          episode: 2,
          road: 0,
          progress: const Duration(seconds: 1),
        ),
        isTrue,
      );
      expect(
        debouncer.shouldEmit(
          entityKey: 'a',
          episode: 2,
          road: 1,
          progress: const Duration(seconds: 1),
        ),
        isTrue,
      );
    });

    test('can reset one entity or all tracked state', () {
      final debouncer = PrivateSyncWatchDebouncer(
          minProgressDelta: const Duration(seconds: 20));
      expect(
        debouncer.shouldEmit(
          entityKey: 'a',
          episode: 1,
          road: 0,
          progress: const Duration(seconds: 30),
        ),
        isTrue,
      );
      expect(
        debouncer.shouldEmit(
          entityKey: 'a',
          episode: 1,
          road: 0,
          progress: const Duration(seconds: 35),
        ),
        isFalse,
      );

      debouncer.reset(entityKey: 'a');
      expect(
        debouncer.shouldEmit(
          entityKey: 'a',
          episode: 1,
          road: 0,
          progress: const Duration(seconds: 35),
        ),
        isTrue,
      );
      expect(
        debouncer.shouldEmit(
          entityKey: 'b',
          episode: 1,
          road: 0,
          progress: const Duration(seconds: 10),
        ),
        isTrue,
      );

      debouncer.reset();
      expect(
        debouncer.shouldEmit(
          entityKey: 'b',
          episode: 1,
          road: 0,
          progress: const Duration(seconds: 12),
        ),
        isTrue,
      );
    });
  });

  group('PrivateSyncTriggerThrottler', () {
    test('allows the first trigger and throttles later triggers by interval',
        () {
      final throttler = PrivateSyncTriggerThrottler(
        minInterval: const Duration(minutes: 5),
      );
      final now = DateTime.fromMillisecondsSinceEpoch(1000);

      expect(throttler.shouldTrigger(now), isTrue);
      expect(throttler.shouldTrigger(now.add(const Duration(minutes: 2))),
          isFalse);
      expect(
          throttler.shouldTrigger(now.add(const Duration(minutes: 5))), isTrue);
    });
  });

  group('PrivateSyncService watch event debounce', () {
    late Directory tempDir;
    late _MemorySettings settings;
    late PrivateSyncLocalStore localStore;
    late PrivateSyncService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('aslan-private-sync-');
      settings = _MemorySettings()
        ..values[SettingBoxKey.privateSyncEnable] = true
        ..values[SettingBoxKey.privateSyncEnableWatch] = true
        ..values[SettingBoxKey.privateSyncDeviceId] = 'device-a';
      localStore = PrivateSyncLocalStore(
        settings: settings,
        localEventFile: File('${tempDir.path}/private-sync.local.jsonl'),
      );
      service = PrivateSyncService(
        settings: settings,
        localStore: localStore,
        watchDebouncer: PrivateSyncWatchDebouncer(
          minProgressDelta: const Duration(seconds: 20),
        ),
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('skips insignificant watch progress updates', () async {
      final history = History(
        _item(1),
        1,
        'plugin',
        DateTime.fromMillisecondsSinceEpoch(1000),
        '',
        '',
      );

      await service.appendWatchUpsert(
        history: history,
        episode: 1,
        road: 0,
        progressMs: 1000,
      );
      await service.appendWatchUpsert(
        history: history,
        episode: 1,
        road: 0,
        progressMs: 10000,
      );
      await service.appendWatchUpsert(
        history: history,
        episode: 1,
        road: 0,
        progressMs: 25000,
      );

      expect(
          (await localStore.readEvents()).map((event) {
            return event.payload['progressMs'];
          }),
          [
            1000,
            25000,
          ]);
    });
  });

  group('PrivateSyncService event append', () {
    late Directory tempDir;
    late _MemorySettings settings;
    late PrivateSyncLocalStore localStore;
    late PrivateSyncService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('aslan-private-sync-');
      settings = _MemorySettings()
        ..values[SettingBoxKey.privateSyncEnable] = true
        ..values[SettingBoxKey.privateSyncEnableWatch] = true
        ..values[SettingBoxKey.privateSyncEnableCollect] = true
        ..values[SettingBoxKey.privateSyncDeviceId] = 'device-a';
      localStore = PrivateSyncLocalStore(
        settings: settings,
        localEventFile: File('${tempDir.path}/private-sync.local.jsonl'),
      );
      service = PrivateSyncService(
        settings: settings,
        localStore: localStore,
        now: () => DateTime.fromMillisecondsSinceEpoch(3000),
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('appends watch upsert events when enabled', () async {
      final history = History(
        _item(1),
        2,
        'LaevaBangumi',
        DateTime.fromMillisecondsSinceEpoch(2000),
        'https://example.invalid/1',
        'EP2',
      );

      await service.appendWatchUpsert(
        history: history,
        episode: 2,
        road: 0,
        progressMs: 12000,
      );

      final event = (await localStore.readEvents()).single;
      expect(event.eventId, 'device-a:1');
      expect(event.op, 'watch.upsertProgress');
      expect(event.updatedAt, 2000);
      expect(event.payload['progressMs'], 12000);
    });

    test('does not append watch events when watch sync is disabled', () async {
      settings.values[SettingBoxKey.privateSyncEnableWatch] = false;
      final history = History(
        _item(1),
        1,
        'LaevaBangumi',
        DateTime.fromMillisecondsSinceEpoch(2000),
        '',
        '',
      );

      await service.appendWatchUpsert(
        history: history,
        episode: 1,
        road: 0,
        progressMs: 1000,
      );

      expect(await localStore.readEvents(), isEmpty);
    });

    test('appends collection upsert and delete events', () async {
      final collectible = CollectedBangumi(
        _item(2),
        DateTime.fromMillisecondsSinceEpoch(1000),
        CollectType.watching.value,
      );

      await service.appendCollectionUpsert(collectible);
      await service.appendCollectionDelete(2);

      final events = await localStore.readEvents();
      expect(events.map((event) => event.op), [
        'collection.upsert',
        'collection.delete',
      ]);
      expect(events.first.payload['type'], CollectType.watching.value);
      expect(events.last.bangumiId, 2);
    });
  });

  group('PrivateSyncService snapshot application', () {
    late Directory tempDir;
    late PrivateSyncService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('aslan-private-sync-');
      Hive.init(tempDir.path);
      _registerHiveAdapters();
      GStorage.histories = await Hive.openBox<History>('histories');
      GStorage.collectibles =
          await Hive.openBox<CollectedBangumi>('collectibles');
      service = PrivateSyncService(settings: _MemorySettings());
    });

    tearDown(() async {
      await Hive.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('applies watch snapshots to local histories', () async {
      await GStorage.histories.put(
        'old1',
        History(
          _item(99),
          1,
          'old',
          DateTime.fromMillisecondsSinceEpoch(1),
          '',
          '',
        ),
      );

      await service.applySnapshot(
        PrivateSyncSnapshot(
          generatedAt: 5000,
          watch: PrivateSyncWatchSnapshot(
            clearVersion: null,
            histories: [
              PrivateSyncWatchHistory(
                entityKey: 'plugin1',
                bangumiId: 1,
                adapterName: 'plugin',
                lastWatchEpisode: 3,
                lastWatchTime: 4000,
                lastSrc: 'https://example.invalid/3',
                lastWatchEpisodeName: 'EP3',
                bangumiItem: _item(1),
                itemVersion: '0000000000004000|device-a:1',
                progresses: const {
                  1: PrivateSyncWatchProgress(
                    episode: 1,
                    road: 0,
                    progressMs: 12000,
                    version: '0000000000001000|device-a:1',
                  ),
                  3: PrivateSyncWatchProgress(
                    episode: 3,
                    road: 1,
                    progressMs: 34000,
                    version: '0000000000004000|device-a:2',
                  ),
                },
              ),
            ],
          ),
          collection: const PrivateSyncCollectionSnapshot(
            clearVersion: null,
            items: [],
          ),
        ),
        applyCollection: false,
      );

      expect(GStorage.histories.length, 1);
      final history = GStorage.histories.get('plugin1')!;
      expect(history.lastWatchEpisode, 3);
      expect(history.lastWatchTime.millisecondsSinceEpoch, 4000);
      expect(history.lastSrc, 'https://example.invalid/3');
      expect(history.progresses[1]!.progress.inMilliseconds, 12000);
      expect(history.progresses[3]!.road, 1);
      expect(history.progresses[3]!.progress.inMilliseconds, 34000);
    });

    test('applies collection snapshots to local collectibles', () async {
      await GStorage.collectibles.put(
        99,
        CollectedBangumi(
          _item(99),
          DateTime.fromMillisecondsSinceEpoch(1),
          CollectType.watching.value,
        ),
      );

      await service.applySnapshot(
        PrivateSyncSnapshot(
          generatedAt: 5000,
          watch: const PrivateSyncWatchSnapshot(
            clearVersion: null,
            histories: [],
          ),
          collection: PrivateSyncCollectionSnapshot(
            clearVersion: null,
            items: [
              PrivateSyncCollectionItem(
                bangumiId: 2,
                type: CollectType.watched.value,
                collectedAt: 3000,
                updatedAt: 4000,
                bangumiItem: _item(2),
                itemVersion: '0000000000004000|device-a:1',
              ),
            ],
          ),
        ),
        applyWatch: false,
      );

      expect(GStorage.collectibles.length, 1);
      final collectible = GStorage.collectibles.get(2)!;
      expect(collectible.type, CollectType.watched.value);
      expect(collectible.time.millisecondsSinceEpoch, 3000);
      expect(collectible.bangumiItem.name, 'subject 2');
    });
  });

  group('PrivateSyncService syncNow', () {
    late Directory tempDir;
    late _MemorySettings settings;
    late PrivateSyncLocalStore localStore;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('aslan-private-sync-');
      Hive.init('${tempDir.path}/hive');
      _registerHiveAdapters();
      GStorage.histories = await Hive.openBox<History>('histories');
      GStorage.collectibles =
          await Hive.openBox<CollectedBangumi>('collectibles');
      settings = _MemorySettings()
        ..values[SettingBoxKey.privateSyncEnable] = true
        ..values[SettingBoxKey.privateSyncEnableWatch] = true
        ..values[SettingBoxKey.privateSyncEnableCollect] = true
        ..values[SettingBoxKey.privateSyncDeviceId] = 'device-a'
        ..values[SettingBoxKey.privateSyncDeviceName] = 'Phone';
      localStore = PrivateSyncLocalStore(
        settings: settings,
        localEventFile: File('${tempDir.path}/private-sync.local.jsonl'),
      );
    });

    tearDown(() async {
      await Hive.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('registers device uploads pending events applies snapshot and acks',
        () async {
      await localStore.appendEvent(_clearWatch('device-a:1', seq: 1));
      await localStore.appendEvent(_clearCollection('device-a:2', seq: 2));
      final api = _FakePrivateSyncApi(
        mergeResult: _mergeResult(
          acceptedEventIds: ['device-a:1'],
          ignoredDuplicateEventIds: ['device-a:2'],
        ),
      );
      final service = PrivateSyncService(
        settings: settings,
        localStore: localStore,
        api: api,
      );

      final result = await service.syncNow();

      expect(api.registeredDeviceId, 'device-a');
      expect(api.registeredDeviceName, 'Phone');
      expect(api.mergedDeviceId, 'device-a');
      expect(api.mergedClientSeq, 2);
      expect(api.mergedEvents.map((event) => event.eventId), [
        'device-a:1',
        'device-a:2',
      ]);
      expect(await localStore.readEvents(), isEmpty);
      expect(result.uploadedEventCount, 2);
      expect(result.remainingEventCount, 0);
    });

    test('keeps unacknowledged and concurrently appended events', () async {
      await localStore.appendEvent(_clearWatch('device-a:1', seq: 1));
      await localStore.appendEvent(_clearCollection('device-a:2', seq: 2));
      final api = _FakePrivateSyncApi(
        mergeResult: _mergeResult(acceptedEventIds: ['device-a:1']),
        beforeMergeReturns: () async {
          await localStore.appendEvent(_clearWatch('device-a:3', seq: 3));
        },
      );
      final service = PrivateSyncService(
        settings: settings,
        localStore: localStore,
        api: api,
      );

      final result = await service.syncNow();

      final remaining = await localStore.readEvents();
      expect(remaining.map((event) => event.eventId), [
        'device-a:2',
        'device-a:3',
      ]);
      expect(result.remainingEventCount, 2);
    });

    test('keeps pending events when merge fails', () async {
      await localStore.appendEvent(_clearWatch('device-a:1', seq: 1));
      final service = PrivateSyncService(
        settings: settings,
        localStore: localStore,
        api: _FakePrivateSyncApi(error: Exception('offline')),
      );

      await expectLater(service.syncNow(), throwsException);

      expect((await localStore.readEvents()).single.eventId, 'device-a:1');
    });

    test('disables private sync and keeps pending events after auth failure',
        () async {
      await localStore.appendEvent(_clearWatch('device-a:1', seq: 1));
      final service = PrivateSyncService(
        settings: settings,
        localStore: localStore,
        api: _FakePrivateSyncApi(
          error: const PrivateSyncAuthenticationException('bad token'),
        ),
      );

      await expectLater(
        service.syncNow(),
        throwsA(isA<PrivateSyncAuthenticationException>()),
      );

      expect(settings.values[SettingBoxKey.privateSyncEnable], isFalse);
      expect((await localStore.readEvents()).single.eventId, 'device-a:1');
    });

    test('shares in-flight sync across service instances', () async {
      await localStore.appendEvent(_clearWatch('device-a:1', seq: 1));
      final releaseMerge = Completer<void>();
      final api = _FakePrivateSyncApi(
        mergeResult: _mergeResult(acceptedEventIds: ['device-a:1']),
        beforeMergeReturns: () => releaseMerge.future,
      );
      final first = PrivateSyncService(
        settings: settings,
        localStore: localStore,
        api: api,
      );
      final second = PrivateSyncService(
        settings: settings,
        localStore: localStore,
        api: api,
      );

      final firstResult = first.syncNow();
      final secondResult = second.syncNow();
      await Future<void>.delayed(Duration.zero);
      releaseMerge.complete();
      await Future.wait([firstResult, secondResult]);

      expect(api.mergeCallCount, 1);
      expect(await localStore.readEvents(), isEmpty);
    });

    test('schedules long-playback sync only after the trigger interval',
        () async {
      var now = DateTime.fromMillisecondsSinceEpoch(1000);
      final api = _FakePrivateSyncApi(mergeResult: _mergeResult());
      final service = PrivateSyncService(
        settings: settings,
        localStore: localStore,
        api: api,
        playbackSyncThrottler: PrivateSyncTriggerThrottler(
          minInterval: const Duration(minutes: 5),
        ),
        now: () => now,
      );

      expect(service.syncPlaybackProgressInBackground(), isTrue);
      await service.lastPlaybackSync;
      expect(service.syncPlaybackProgressInBackground(), isFalse);

      now = now.add(const Duration(minutes: 5));
      expect(service.syncPlaybackProgressInBackground(), isTrue);
      await service.lastPlaybackSync;
    });
  });

  group('PrivateSyncService first enable import', () {
    late Directory tempDir;
    late _MemorySettings settings;
    late PrivateSyncLocalStore localStore;
    late PrivateSyncService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('aslan-private-sync-');
      Hive.init('${tempDir.path}/hive');
      _registerHiveAdapters();
      GStorage.histories = await Hive.openBox<History>('histories');
      GStorage.collectibles =
          await Hive.openBox<CollectedBangumi>('collectibles');
      settings = _MemorySettings()
        ..values[SettingBoxKey.privateSyncEnable] = true
        ..values[SettingBoxKey.privateSyncEnableWatch] = true
        ..values[SettingBoxKey.privateSyncEnableCollect] = true
        ..values[SettingBoxKey.privateSyncDeviceId] = 'device-a';
      localStore = PrivateSyncLocalStore(
        settings: settings,
        localEventFile: File('${tempDir.path}/private-sync.local.jsonl'),
      );
      service = PrivateSyncService(
        settings: settings,
        localStore: localStore,
      );
    });

    tearDown(() async {
      await Hive.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('imports existing watch histories once', () async {
      final history = History(
        _item(1),
        2,
        'plugin',
        DateTime.fromMillisecondsSinceEpoch(2000),
        'https://example.invalid/2',
        'EP2',
      );
      history.progresses[1] = Progress(1, 0, 10000);
      history.progresses[2] = Progress(2, 1, 20000);
      await GStorage.histories.put(history.key, history);

      await service.importExistingLocalDataIfNeeded();
      await service.importExistingLocalDataIfNeeded();

      final events = await localStore.readEvents();
      expect(events.map((event) => event.op), [
        'watch.upsertProgress',
        'watch.upsertProgress',
      ]);
      expect(events.map((event) => event.eventId), [
        'device-a:1',
        'device-a:2',
      ]);
      expect(events.first.payload['episode'], 1);
      expect(events.last.payload['progressMs'], 20000);
      expect(settings.values[SettingBoxKey.privateSyncWatchImported], isTrue);
    });

    test('imports existing collectibles once', () async {
      await GStorage.collectibles.put(
        2,
        CollectedBangumi(
          _item(2),
          DateTime.fromMillisecondsSinceEpoch(3000),
          CollectType.watching.value,
        ),
      );

      await service.importExistingLocalDataIfNeeded();
      await service.importExistingLocalDataIfNeeded();

      final events = await localStore.readEvents();
      expect(events.map((event) => event.op), ['collection.upsert']);
      expect(events.single.bangumiId, 2);
      expect(events.single.payload['collectedAt'], 3000);
      expect(settings.values[SettingBoxKey.privateSyncCollectImported], isTrue);
    });

    test('imports existing watch histories even after recent debounced update',
        () async {
      final history = History(
        _item(1),
        1,
        'plugin',
        DateTime.fromMillisecondsSinceEpoch(2000),
        '',
        '',
      );
      history.progresses[1] = Progress(1, 0, 10000);
      await GStorage.histories.put(history.key, history);
      await service.appendWatchUpsert(
        history: history,
        episode: 1,
        road: 0,
        progressMs: 10000,
      );
      await localStore.replaceEvents(const []);

      await service.importExistingLocalDataIfNeeded();

      final events = await localStore.readEvents();
      expect(events.map((event) => event.op), ['watch.upsertProgress']);
      expect(events.single.payload['progressMs'], 10000);
    });
  });
}

class _MemorySettings implements PrivateSyncSettingsStore {
  final values = <String, dynamic>{};

  @override
  dynamic get(String key, {dynamic defaultValue}) {
    return values.containsKey(key) ? values[key] : defaultValue;
  }

  @override
  Future<void> put(String key, dynamic value) async {
    values[key] = value;
  }
}

BangumiItem _item(int id) {
  return BangumiItem(
    id: id,
    type: 2,
    name: 'subject $id',
    nameCn: '条目 $id',
    summary: '',
    airDate: '2026-01-01',
    airWeekday: 4,
    rank: 0,
    images: const {
      'large': '',
      'common': '',
      'medium': '',
      'small': '',
      'grid': '',
    },
    tags: const <BangumiTag>[],
    alias: const [],
    ratingScore: 0,
    votes: 0,
    votesCount: const [],
    info: '',
  );
}

PrivateSyncEvent _clearWatch(String eventId, {required int seq}) {
  return PrivateSyncEvent.watchClearAll(
    eventId: eventId,
    deviceId: 'device-a',
    seq: seq,
    updatedAt: 1000 + seq,
  );
}

PrivateSyncEvent _clearCollection(String eventId, {required int seq}) {
  return PrivateSyncEvent.collectionClearAll(
    eventId: eventId,
    deviceId: 'device-a',
    seq: seq,
    updatedAt: 1000 + seq,
  );
}

PrivateSyncMergeResult _mergeResult({
  List<String> acceptedEventIds = const [],
  List<String> ignoredDuplicateEventIds = const [],
}) {
  return PrivateSyncMergeResult(
    acceptedEventIds: acceptedEventIds,
    ignoredDuplicateEventIds: ignoredDuplicateEventIds,
    snapshot: const PrivateSyncSnapshot(
      generatedAt: 5000,
      watch: PrivateSyncWatchSnapshot(clearVersion: null, histories: []),
      collection: PrivateSyncCollectionSnapshot(clearVersion: null, items: []),
    ),
  );
}

class _FakePrivateSyncApi implements PrivateSyncApiClient {
  _FakePrivateSyncApi({
    PrivateSyncMergeResult? mergeResult,
    this.beforeMergeReturns,
    this.error,
  }) : mergeResult = mergeResult ?? _mergeResult();

  final PrivateSyncMergeResult mergeResult;
  final Future<void> Function()? beforeMergeReturns;
  final Object? error;
  String? registeredDeviceId;
  String? registeredDeviceName;
  String? mergedDeviceId;
  int? mergedClientSeq;
  int mergeCallCount = 0;
  List<PrivateSyncEvent> mergedEvents = const [];

  @override
  Future<PrivateSyncAuthResult> registerAccount({
    required String loginName,
    required String displayName,
    required String password,
    required String inviteCode,
    required String deviceId,
    required String deviceName,
    String? platform,
    String? appVersion,
  }) async {
    throw UnimplementedError(
        'registerAccount is not used by sync service tests');
  }

  @override
  Future<PrivateSyncAuthResult> login({
    required String loginName,
    required String password,
    required String deviceId,
    required String deviceName,
    String? platform,
    String? appVersion,
  }) async {
    throw UnimplementedError('login is not used by sync service tests');
  }

  @override
  Future<PrivateSyncStatus> status() async {
    return const PrivateSyncStatus(
      displayName: 'Test',
      devices: [],
      watchHistoryCount: 0,
      collectionCount: 0,
    );
  }

  @override
  Future<void> logout() async {
    throw UnimplementedError('logout is not used by sync service tests');
  }

  @override
  Future<PrivateSyncDeviceRegistration> registerDevice({
    required String deviceId,
    required String deviceName,
    String? platform,
    String? appVersion,
  }) async {
    registeredDeviceId = deviceId;
    registeredDeviceName = deviceName;
    return PrivateSyncDeviceRegistration(
      displayName: 'Test',
      deviceId: deviceId,
    );
  }

  @override
  Future<PrivateSyncMergeResult> merge({
    required String deviceId,
    required int clientSeq,
    required List<PrivateSyncEvent> events,
  }) async {
    mergeCallCount++;
    if (error != null) {
      throw error!;
    }
    mergedDeviceId = deviceId;
    mergedClientSeq = clientSeq;
    mergedEvents = List.of(events);
    await beforeMergeReturns?.call();
    return mergeResult;
  }
}

void _registerHiveAdapters() {
  if (!Hive.isAdapterRegistered(0)) {
    Hive.registerAdapter(BangumiItemAdapter());
  }
  if (!Hive.isAdapterRegistered(4)) {
    Hive.registerAdapter(BangumiTagAdapter());
  }
  if (!Hive.isAdapterRegistered(3)) {
    Hive.registerAdapter(CollectedBangumiAdapter());
  }
  if (!Hive.isAdapterRegistered(2)) {
    Hive.registerAdapter(ProgressAdapter());
  }
  if (!Hive.isAdapterRegistered(1)) {
    Hive.registerAdapter(HistoryAdapter());
  }
}
