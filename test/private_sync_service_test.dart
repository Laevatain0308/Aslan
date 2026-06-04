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

    test('saves auth session without enabling sync when strategy is cancelled',
        () async {
      await store.appendEvent(_clearWatch('device-a:1', seq: 1));

      await PrivateSyncService.saveAuthenticationResult(
        settings: settings,
        localStore: store,
        result: const PrivateSyncAuthResult(
          displayName: 'Alice',
          deviceId: 'device-a',
          token: 'lbst_token',
        ),
        loginName: ' alice ',
        previousLoginName: '',
        previousToken: '',
        deviceName: ' Phone ',
        enableSync: false,
      );

      expect(settings.values[SettingBoxKey.privateSyncToken], 'lbst_token');
      expect(settings.values[SettingBoxKey.privateSyncLoginName], 'alice');
      expect(settings.values[SettingBoxKey.privateSyncDisplayName], 'Alice');
      expect(settings.values[SettingBoxKey.privateSyncEnable], isFalse);
      expect(settings.values[SettingBoxKey.privateSyncEnableWatch], isTrue);
      expect(settings.values[SettingBoxKey.privateSyncEnableCollect], isTrue);
      expect(settings.values[SettingBoxKey.privateSyncDeviceName], 'Phone');
      expect(settings.values[SettingBoxKey.privateSyncWatchImported], isFalse);
      expect(
        settings.values[SettingBoxKey.privateSyncCollectImported],
        isFalse,
      );
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

    test('does not append watch events while sync is paused', () async {
      settings.values[SettingBoxKey.privateSyncEnable] = false;
      settings.values[SettingBoxKey.privateSyncToken] = 'lbst_token';
      final history = History(
        _item(1),
        1,
        'LaevaBangumi',
        DateTime.fromMillisecondsSinceEpoch(2000),
        'https://example.invalid/1',
        'EP1',
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

    test('does not append collection events while sync is paused', () async {
      settings.values[SettingBoxKey.privateSyncEnable] = false;
      settings.values[SettingBoxKey.privateSyncToken] = 'lbst_token';
      final collectible = CollectedBangumi(
        _item(2),
        DateTime.fromMillisecondsSinceEpoch(1000),
        CollectType.watching.value,
      );

      await service.appendCollectionUpsert(collectible);
      await service.appendCollectionDelete(2);

      expect(await localStore.readEvents(), isEmpty);
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

    test('skips collection snapshot items with invalid collection type',
        () async {
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
                type: 6,
                collectedAt: 3000,
                updatedAt: 4000,
                bangumiItem: _item(2),
                itemVersion: 'bad',
              ),
            ],
          ),
        ),
        applyWatch: false,
      );

      expect(GStorage.collectibles.values, isEmpty);
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

    test('uploads pending events in bounded batches before applying snapshot',
        () async {
      for (var i = 1; i <= 205; i++) {
        await localStore.appendEvent(_clearWatch('device-a:$i', seq: i));
      }
      final api = _FakePrivateSyncApi(
        mergeResults: [
          _mergeResult(
            acceptedEventIds:
                List.generate(100, (index) => 'device-a:${index + 1}'),
          ),
          _mergeResult(
            acceptedEventIds:
                List.generate(100, (index) => 'device-a:${index + 101}'),
          ),
          _mergeResult(
            acceptedEventIds:
                List.generate(5, (index) => 'device-a:${index + 201}'),
          ),
        ],
      );
      final service = PrivateSyncService(
        settings: settings,
        localStore: localStore,
        api: api,
      );

      final result = await service.syncNow();

      expect(api.mergeCallCount, 3);
      expect(api.mergedEventBatches.map((batch) => batch.length), [
        100,
        100,
        5,
      ]);
      expect(api.mergedClientSeqs, [100, 200, 205]);
      expect(result.uploadedEventCount, 205);
      expect(result.remainingEventCount, 0);
      expect(await localStore.readEvents(), isEmpty);
    });

    test('keeps all local events when a later upload batch fails', () async {
      for (var i = 1; i <= 101; i++) {
        await localStore.appendEvent(_clearWatch('device-a:$i', seq: i));
      }
      final api = _FakePrivateSyncApi(
        mergeResults: [
          _mergeResult(
            acceptedEventIds:
                List.generate(100, (index) => 'device-a:${index + 1}'),
          ),
        ],
        errorOnMergeCall: 2,
        error: Exception('offline'),
      );
      final service = PrivateSyncService(
        settings: settings,
        localStore: localStore,
        api: api,
      );

      await expectLater(service.syncNow(), throwsException);

      expect(api.mergeCallCount, 2);
      expect((await localStore.readEvents()).length, 101);
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

    test('cloud override clears local data and pending events before snapshot',
        () async {
      await localStore.appendEvent(_clearWatch('device-a:1', seq: 1));
      await GStorage.histories.put(
        'LaevaBangumi1',
        History(
          _item(1),
          1,
          'LaevaBangumi',
          DateTime.fromMillisecondsSinceEpoch(1000),
          '',
          'EP1',
        ),
      );
      await GStorage.collectibles.put(
        2,
        CollectedBangumi(
          _item(2),
          DateTime.fromMillisecondsSinceEpoch(2000),
          CollectType.watching.value,
        ),
      );
      final api = _FakePrivateSyncApi(
        mergeResult: _mergeResult(
          snapshot: PrivateSyncSnapshot(
            generatedAt: 5000,
            watch: PrivateSyncWatchSnapshot(
              clearVersion: null,
              histories: [
                PrivateSyncWatchHistory(
                  entityKey: 'LaevaBangumi3',
                  bangumiId: 3,
                  adapterName: 'LaevaBangumi',
                  lastWatchEpisode: 3,
                  lastWatchTime: 3000,
                  lastSrc: '',
                  lastWatchEpisodeName: 'EP3',
                  bangumiItem: _item(3),
                  itemVersion: 'v3',
                  progresses: const {},
                ),
              ],
            ),
            collection: PrivateSyncCollectionSnapshot(
              clearVersion: null,
              items: [
                PrivateSyncCollectionItem(
                  bangumiId: 4,
                  type: CollectType.watched.value,
                  collectedAt: 4000,
                  updatedAt: 4000,
                  bangumiItem: _item(4),
                  itemVersion: 'v4',
                ),
              ],
            ),
          ),
        ),
      );
      final service = PrivateSyncService(
        settings: settings,
        localStore: localStore,
        api: api,
      );

      final result = await service.syncNowWithStrategy(
        PrivateSyncEnableStrategy.cloudFirst,
      );

      expect(api.clearRemoteWatch, isFalse);
      expect(api.clearRemoteCollection, isFalse);
      expect(api.mergedEvents, isEmpty);
      expect(await localStore.readEvents(), isEmpty);
      expect(result.uploadedEventCount, 0);
      expect(GStorage.histories.keys, ['LaevaBangumi3']);
      expect(GStorage.collectibles.keys, [4]);
      expect(settings.values[SettingBoxKey.privateSyncWatchImported], isTrue);
      expect(
        settings.values[SettingBoxKey.privateSyncCollectImported],
        isTrue,
      );
    });

    test('local override clears remote domains then uploads local snapshot',
        () async {
      final history = History(
        _item(1),
        1,
        'LaevaBangumi',
        DateTime.fromMillisecondsSinceEpoch(1000),
        'https://example.invalid/1',
        'EP1',
      );
      history.progresses[1] = Progress(1, 0, 10000);
      await GStorage.histories.put(history.key, history);
      await GStorage.collectibles.put(
        2,
        CollectedBangumi(
          _item(2),
          DateTime.fromMillisecondsSinceEpoch(2000),
          CollectType.watching.value,
        ),
      );
      final api = _FakePrivateSyncApi(
        mergeResult: _mergeResult(
          acceptedEventIds: ['device-a:1', 'device-a:2'],
        ),
      );
      final service = PrivateSyncService(
        settings: settings,
        localStore: localStore,
        api: api,
        now: () => DateTime.fromMillisecondsSinceEpoch(9000),
      );

      await service.syncNowWithStrategy(PrivateSyncEnableStrategy.localFirst);

      expect(api.clearRemoteWatch, isTrue);
      expect(api.clearRemoteCollection, isTrue);
      expect(api.mergedEvents.map((event) => event.op), [
        'watch.upsertProgress',
        'collection.upsert',
      ]);
      expect(
          api.mergedEvents.every((event) => event.updatedAt == 9000), isTrue);
      expect(
        api.mergedEvents
            .firstWhere((event) => event.op == 'watch.upsertProgress')
            .payload['lastWatchTime'],
        1000,
      );
      expect(
        api.mergedEvents
            .firstWhere((event) => event.op == 'watch.upsertProgress')
            .payload['lastWatchEpisode'],
        1,
      );
      expect(
        api.mergedEvents
            .firstWhere((event) => event.op == 'collection.upsert')
            .payload['collectedAt'],
        2000,
      );
      expect(settings.values[SettingBoxKey.privateSyncWatchImported], isTrue);
      expect(
        settings.values[SettingBoxKey.privateSyncCollectImported],
        isTrue,
      );
    });

    test(
        'local override keeps generated snapshot events when clear is interrupted',
        () async {
      final history = History(
        _item(1),
        1,
        'LaevaBangumi',
        DateTime.fromMillisecondsSinceEpoch(1000),
        'https://example.invalid/1',
        'EP1',
      );
      history.progresses[1] = Progress(1, 0, 10000);
      await GStorage.histories.put(history.key, history);
      await GStorage.collectibles.put(
        2,
        CollectedBangumi(
          _item(2),
          DateTime.fromMillisecondsSinceEpoch(2000),
          CollectType.watching.value,
        ),
      );
      final api = _FakePrivateSyncApi(clearDataError: Exception('interrupted'));
      final service = PrivateSyncService(
        settings: settings,
        localStore: localStore,
        api: api,
        now: () => DateTime.fromMillisecondsSinceEpoch(9000),
      );

      await expectLater(
        service.syncNowWithStrategy(PrivateSyncEnableStrategy.localFirst),
        throwsException,
      );

      expect(api.clearRemoteWatch, isTrue);
      expect(api.clearRemoteCollection, isTrue);
      final events = await localStore.readEvents();
      expect(events.map((event) => event.op), [
        'watch.upsertProgress',
        'collection.upsert',
      ]);
      expect(events.every((event) => event.updatedAt == 9000), isTrue);
    });

    test('normal sync retries a pending local override clear before upload',
        () async {
      final history = History(
        _item(1),
        1,
        'LaevaBangumi',
        DateTime.fromMillisecondsSinceEpoch(1000),
        'https://example.invalid/1',
        'EP1',
      );
      history.progresses[1] = Progress(1, 0, 10000);
      await GStorage.histories.put(history.key, history);
      await GStorage.collectibles.put(
        2,
        CollectedBangumi(
          _item(2),
          DateTime.fromMillisecondsSinceEpoch(2000),
          CollectType.watching.value,
        ),
      );
      final firstApi =
          _FakePrivateSyncApi(clearDataError: Exception('interrupted'));
      final firstService = PrivateSyncService(
        settings: settings,
        localStore: localStore,
        api: firstApi,
        now: () => DateTime.fromMillisecondsSinceEpoch(9000),
      );

      await expectLater(
        firstService.syncNowWithStrategy(PrivateSyncEnableStrategy.localFirst),
        throwsException,
      );

      final secondApi = _FakePrivateSyncApi(
        mergeResult: _mergeResult(
          acceptedEventIds: ['device-a:1', 'device-a:2'],
        ),
      );
      final secondService = PrivateSyncService(
        settings: settings,
        localStore: localStore,
        api: secondApi,
      );

      await secondService.syncNow();

      expect(secondApi.callLog, [
        'clear:true:true',
        'merge:2',
      ]);
      expect(secondApi.mergedEvents.map((event) => event.op), [
        'watch.upsertProgress',
        'collection.upsert',
      ]);
      expect(await localStore.readEvents(), isEmpty);
    });

    test('local override preserves pending clear state for untouched domains',
        () async {
      settings.values[SettingBoxKey.privateSyncPendingLocalOverrideCollect] =
          true;
      final history = History(
        _item(1),
        1,
        'LaevaBangumi',
        DateTime.fromMillisecondsSinceEpoch(1000),
        'https://example.invalid/1',
        'EP1',
      );
      history.progresses[1] = Progress(1, 0, 10000);
      await GStorage.histories.put(history.key, history);
      final api = _FakePrivateSyncApi(
        mergeResult: _mergeResult(acceptedEventIds: ['device-a:1']),
      );
      final service = PrivateSyncService(
        settings: settings,
        localStore: localStore,
        api: api,
        now: () => DateTime.fromMillisecondsSinceEpoch(9000),
      );

      await service.syncNowWithStrategy(
        PrivateSyncEnableStrategy.localFirst,
        forceWatchSnapshot: true,
        forceCollectionSnapshot: false,
      );

      expect(api.clearRemoteWatch, isTrue);
      expect(api.clearRemoteCollection, isFalse);
      expect(
        settings.values[SettingBoxKey.privateSyncPendingLocalOverrideCollect],
        isTrue,
      );
    });

    test(
        'explicit merge uploads current local snapshot even after prior import',
        () async {
      settings.values[SettingBoxKey.privateSyncWatchImported] = true;
      settings.values[SettingBoxKey.privateSyncCollectImported] = true;
      await localStore.appendEvent(_clearWatch('device-a:1', seq: 1));
      final history = History(
        _item(5),
        2,
        'LaevaBangumi',
        DateTime.fromMillisecondsSinceEpoch(5000),
        'https://example.invalid/5',
        'EP2',
      );
      history.progresses[2] = Progress(2, 0, 12000);
      await GStorage.histories.put(history.key, history);
      await GStorage.collectibles.put(
        6,
        CollectedBangumi(
          _item(6),
          DateTime.fromMillisecondsSinceEpoch(6000),
          CollectType.watching.value,
        ),
      );
      final api = _FakePrivateSyncApi(
        mergeResult: _mergeResult(
          acceptedEventIds: ['device-a:1', 'device-a:2'],
        ),
      );
      final service = PrivateSyncService(
        settings: settings,
        localStore: localStore,
        api: api,
        now: () => DateTime.fromMillisecondsSinceEpoch(11000),
      );

      await service.syncNowWithStrategy(
        PrivateSyncEnableStrategy.merge,
        forceLocalSnapshot: true,
      );

      expect(api.mergedEvents.map((event) => event.op), [
        'watch.upsertProgress',
        'collection.upsert',
      ]);
      expect(
          api.mergedEvents.every((event) => event.updatedAt == 11000), isTrue);
      expect(api.mergedEvents.first.entityKey, history.key);
      expect(api.mergedEvents.last.bangumiId, 6);
      expect(await localStore.readEvents(), isEmpty);
      expect(settings.values[SettingBoxKey.privateSyncWatchImported], isTrue);
      expect(
        settings.values[SettingBoxKey.privateSyncCollectImported],
        isTrue,
      );
    });

    test('runs explicit override sync even when a normal sync is in flight',
        () async {
      final releaseMerge = Completer<void>();
      final normalApi = _FakePrivateSyncApi(
        mergeResult: _mergeResult(
          snapshot: PrivateSyncSnapshot(
            generatedAt: 5000,
            watch: PrivateSyncWatchSnapshot(
              clearVersion: null,
              histories: [
                PrivateSyncWatchHistory(
                  entityKey: 'LaevaBangumi9',
                  bangumiId: 9,
                  adapterName: 'LaevaBangumi',
                  lastWatchEpisode: 1,
                  lastWatchTime: 9000,
                  lastSrc: '',
                  lastWatchEpisodeName: 'EP1',
                  bangumiItem: _item(9),
                  itemVersion: 'normal',
                  progresses: const {},
                ),
              ],
            ),
            collection:
                PrivateSyncCollectionSnapshot(clearVersion: null, items: []),
          ),
        ),
        beforeMergeReturns: () => releaseMerge.future,
      );
      final overrideApi = _FakePrivateSyncApi(
        mergeResult: _mergeResult(
          snapshot: PrivateSyncSnapshot(
            generatedAt: 6000,
            watch: PrivateSyncWatchSnapshot(
              clearVersion: null,
              histories: [
                PrivateSyncWatchHistory(
                  entityKey: 'LaevaBangumi3',
                  bangumiId: 3,
                  adapterName: 'LaevaBangumi',
                  lastWatchEpisode: 1,
                  lastWatchTime: 3000,
                  lastSrc: '',
                  lastWatchEpisodeName: 'EP1',
                  bangumiItem: _item(3),
                  itemVersion: 'override',
                  progresses: const {},
                ),
              ],
            ),
            collection:
                PrivateSyncCollectionSnapshot(clearVersion: null, items: []),
          ),
        ),
      );
      final normalService = PrivateSyncService(
        settings: settings,
        localStore: localStore,
        api: normalApi,
      );
      final overrideService = PrivateSyncService(
        settings: settings,
        localStore: localStore,
        api: overrideApi,
      );

      final normalResult = normalService.syncNow();
      await Future<void>.delayed(Duration.zero);
      final overrideFuture = overrideService.syncNowWithStrategy(
        PrivateSyncEnableStrategy.localFirst,
      );
      await Future<void>.delayed(Duration.zero);
      expect(overrideApi.clearRemoteWatch, isFalse);
      releaseMerge.complete();
      await normalResult;
      final overrideResult = await overrideFuture;

      expect(overrideApi.clearRemoteWatch, isTrue);
      expect(overrideApi.clearRemoteCollection, isTrue);
      expect(overrideResult.remainingEventCount, 0);
      expect(GStorage.histories.keys, ['LaevaBangumi3']);
    });

    test('disables private sync and keeps pending events after auth failure',
        () async {
      await localStore.appendEvent(_clearWatch('device-a:1', seq: 1));
      settings.values[SettingBoxKey.privateSyncToken] = 'lbst_stale';
      settings.values[SettingBoxKey.privateSyncLoginName] = 'alice';
      settings.values[SettingBoxKey.privateSyncDisplayName] = 'Alice';
      settings.values[SettingBoxKey.privateSyncWatchImported] = true;
      settings.values[SettingBoxKey.privateSyncCollectImported] = true;
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
      expect(settings.values[SettingBoxKey.privateSyncToken], '');
      expect(settings.values[SettingBoxKey.privateSyncLoginName], 'alice');
      expect(settings.values[SettingBoxKey.privateSyncDisplayName], '');
      expect(settings.values[SettingBoxKey.privateSyncWatchImported], isFalse);
      expect(
        settings.values[SettingBoxKey.privateSyncCollectImported],
        isFalse,
      );
      expect((await localStore.readEvents()).single.eventId, 'device-a:1');
    });

    test(
        'disables private sync and keeps pending events after device registration auth failure',
        () async {
      await localStore.appendEvent(_clearWatch('device-a:1', seq: 1));
      settings.values[SettingBoxKey.privateSyncToken] = 'lbst_deleted_user';
      settings.values[SettingBoxKey.privateSyncLoginName] = 'alice';
      settings.values[SettingBoxKey.privateSyncDisplayName] = 'Alice';
      settings.values[SettingBoxKey.privateSyncWatchImported] = true;
      settings.values[SettingBoxKey.privateSyncCollectImported] = true;
      final api = _FakePrivateSyncApi(
        registerDeviceError:
            const PrivateSyncAuthenticationException('bad token'),
      );
      final service = PrivateSyncService(
        settings: settings,
        localStore: localStore,
        api: api,
      );

      await expectLater(
        service.syncNow(),
        throwsA(isA<PrivateSyncAuthenticationException>()),
      );

      expect(settings.values[SettingBoxKey.privateSyncEnable], isFalse);
      expect(settings.values[SettingBoxKey.privateSyncToken], '');
      expect(settings.values[SettingBoxKey.privateSyncLoginName], 'alice');
      expect(settings.values[SettingBoxKey.privateSyncDisplayName], '');
      expect(settings.values[SettingBoxKey.privateSyncWatchImported], isFalse);
      expect(
        settings.values[SettingBoxKey.privateSyncCollectImported],
        isFalse,
      );
      expect((await localStore.readEvents()).single.eventId, 'device-a:1');
      expect(api.mergeCallCount, 0);
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

    test(
        'explicit merge records local deletes when imported watch baseline exists',
        () async {
      settings.values[SettingBoxKey.privateSyncWatchImported] = true;
      settings.values[SettingBoxKey.privateSyncCollectImported] = false;
      settings.values[SettingBoxKey.privateSyncWatchBaseline] =
          'LaevaBangumi1\nLaevaBangumi2';
      final history = History(
        _item(2),
        2,
        'LaevaBangumi',
        DateTime.fromMillisecondsSinceEpoch(5000),
        'https://example.invalid/2',
        'EP2',
      );
      history.progresses[2] = Progress(2, 0, 12000);
      await GStorage.histories.put(history.key, history);
      final api = _FakePrivateSyncApi(
        mergeResult: _mergeResult(
          acceptedEventIds: ['device-a:1', 'device-a:2'],
        ),
      );
      final service = PrivateSyncService(
        settings: settings,
        localStore: localStore,
        api: api,
        now: () => DateTime.fromMillisecondsSinceEpoch(11000),
      );

      await service.syncNowWithStrategy(
        PrivateSyncEnableStrategy.merge,
        forceLocalSnapshot: true,
      );

      expect(api.mergedEvents.map((event) => event.op), [
        'watch.deleteHistory',
        'watch.upsertProgress',
      ]);
      expect(api.mergedEvents.first.entityKey, 'LaevaBangumi1');
      expect(api.mergedEvents.last.entityKey, history.key);
    });

    test(
        'explicit merge does not create deletes for a newly enabled empty domain',
        () async {
      settings.values[SettingBoxKey.privateSyncWatchImported] = false;
      settings.values[SettingBoxKey.privateSyncCollectImported] = false;
      settings.values[SettingBoxKey.privateSyncWatchBaseline] =
          'LaevaBangumi1\nLaevaBangumi2';
      final api = _FakePrivateSyncApi(mergeResult: _mergeResult());
      final service = PrivateSyncService(
        settings: settings,
        localStore: localStore,
        api: api,
        now: () => DateTime.fromMillisecondsSinceEpoch(11000),
      );

      await service.syncNowWithStrategy(
        PrivateSyncEnableStrategy.merge,
        forceLocalSnapshot: true,
      );

      expect(api.mergedEvents, isEmpty);
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

  group('PrivateSyncEnableState', () {
    test('requires a strategy when the global switch is newly enabled', () {
      final state = PrivateSyncEnableState(
        persistedSyncEnabled: false,
        persistedWatchEnabled: false,
        persistedCollectEnabled: false,
        nextSyncEnabled: true,
        nextWatchEnabled: true,
        nextCollectEnabled: true,
      );

      expect(state.requiresEnableStrategy, isTrue);
      expect(state.newlyEnabledWatch, isTrue);
      expect(state.newlyEnabledCollect, isTrue);
    });

    test('requires a strategy when a domain switch is newly enabled', () {
      final state = PrivateSyncEnableState(
        persistedSyncEnabled: true,
        persistedWatchEnabled: false,
        persistedCollectEnabled: true,
        nextSyncEnabled: true,
        nextWatchEnabled: true,
        nextCollectEnabled: true,
      );

      expect(state.requiresEnableStrategy, isTrue);
      expect(state.newlyEnabledWatch, isTrue);
      expect(state.newlyEnabledCollect, isFalse);
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
  PrivateSyncSnapshot? snapshot,
}) {
  return PrivateSyncMergeResult(
    acceptedEventIds: acceptedEventIds,
    ignoredDuplicateEventIds: ignoredDuplicateEventIds,
    snapshot: snapshot ??
        const PrivateSyncSnapshot(
          generatedAt: 5000,
          watch: PrivateSyncWatchSnapshot(clearVersion: null, histories: []),
          collection:
              PrivateSyncCollectionSnapshot(clearVersion: null, items: []),
        ),
  );
}

class _FakePrivateSyncApi implements PrivateSyncApiClient {
  _FakePrivateSyncApi({
    PrivateSyncMergeResult? mergeResult,
    List<PrivateSyncMergeResult>? mergeResults,
    this.beforeMergeReturns,
    this.error,
    this.errorOnMergeCall,
    this.registerDeviceError,
    this.clearDataError,
  })  : mergeResult = mergeResult ?? _mergeResult(),
        mergeResults = mergeResults == null ? null : List.of(mergeResults);

  final PrivateSyncMergeResult mergeResult;
  final List<PrivateSyncMergeResult>? mergeResults;
  final Future<void> Function()? beforeMergeReturns;
  final Object? error;
  final int? errorOnMergeCall;
  final Object? registerDeviceError;
  final Object? clearDataError;
  String? registeredDeviceId;
  String? registeredDeviceName;
  String? mergedDeviceId;
  int? mergedClientSeq;
  int mergeCallCount = 0;
  List<PrivateSyncEvent> mergedEvents = const [];
  List<List<PrivateSyncEvent>> mergedEventBatches = const [];
  List<int> mergedClientSeqs = const [];
  bool clearRemoteWatch = false;
  bool clearRemoteCollection = false;
  List<String> callLog = const [];

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
  Future<void> clearData({
    required bool watch,
    required bool collection,
  }) async {
    clearRemoteWatch = watch;
    clearRemoteCollection = collection;
    callLog = [
      ...callLog,
      'clear:$watch:$collection',
    ];
    if (clearDataError != null) {
      throw clearDataError!;
    }
  }

  @override
  Future<PrivateSyncDeviceRegistration> registerDevice({
    required String deviceId,
    required String deviceName,
    String? platform,
    String? appVersion,
  }) async {
    if (registerDeviceError != null) {
      throw registerDeviceError!;
    }
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
    if (error != null &&
        (errorOnMergeCall == null || errorOnMergeCall == mergeCallCount)) {
      throw error!;
    }
    callLog = [
      ...callLog,
      'merge:${events.length}',
    ];
    mergedDeviceId = deviceId;
    mergedClientSeq = clientSeq;
    mergedEvents = List.of(events);
    mergedEventBatches = [
      ...mergedEventBatches,
      List.of(events),
    ];
    mergedClientSeqs = [
      ...mergedClientSeqs,
      clientSeq,
    ];
    await beforeMergeReturns?.call();
    final results = mergeResults;
    if (results != null && mergeCallCount <= results.length) {
      return results[mergeCallCount - 1];
    }
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
