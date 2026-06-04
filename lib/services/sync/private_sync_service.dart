import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:kazumi/modules/sync/private_sync_models.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/request/apis/private_sync_api.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:path_provider/path_provider.dart';

enum PrivateSyncEnableStrategy {
  merge,
  localFirst,
  cloudFirst,
}

class PrivateSyncEnableState {
  const PrivateSyncEnableState({
    required this.persistedSyncEnabled,
    required this.persistedWatchEnabled,
    required this.persistedCollectEnabled,
    required this.nextSyncEnabled,
    required this.nextWatchEnabled,
    required this.nextCollectEnabled,
  });

  final bool persistedSyncEnabled;
  final bool persistedWatchEnabled;
  final bool persistedCollectEnabled;
  final bool nextSyncEnabled;
  final bool nextWatchEnabled;
  final bool nextCollectEnabled;

  bool get persistedWatchActive =>
      persistedSyncEnabled && persistedWatchEnabled;
  bool get persistedCollectActive =>
      persistedSyncEnabled && persistedCollectEnabled;
  bool get nextWatchActive => nextSyncEnabled && nextWatchEnabled;
  bool get nextCollectActive => nextSyncEnabled && nextCollectEnabled;

  bool get newlyEnabledWatch => nextWatchActive && !persistedWatchActive;
  bool get newlyEnabledCollect => nextCollectActive && !persistedCollectActive;
  bool get requiresEnableStrategy => newlyEnabledWatch || newlyEnabledCollect;
}

abstract class PrivateSyncSettingsStore {
  dynamic get(String key, {dynamic defaultValue});
  Future<void> put(String key, dynamic value);
}

class HivePrivateSyncSettingsStore implements PrivateSyncSettingsStore {
  const HivePrivateSyncSettingsStore();

  @override
  dynamic get(String key, {dynamic defaultValue}) {
    return GStorage.setting.get(key, defaultValue: defaultValue);
  }

  @override
  Future<void> put(String key, dynamic value) {
    return GStorage.setting.put(key, value);
  }
}

class PrivateSyncLocalStore {
  static const deviceIdKey = SettingBoxKey.privateSyncDeviceId;
  static const sequenceKey = SettingBoxKey.privateSyncSequence;

  PrivateSyncLocalStore({
    PrivateSyncSettingsStore settings = const HivePrivateSyncSettingsStore(),
    File? localEventFile,
  })  : _settings = settings,
        _localEventFile = localEventFile;

  final PrivateSyncSettingsStore _settings;
  final File? _localEventFile;

  Future<String> getDeviceId() async {
    final existing =
        _settings.get(deviceIdKey, defaultValue: '').toString().trim();
    if (existing.isNotEmpty) {
      return existing;
    }
    final deviceId = _generateDeviceId();
    await _settings.put(deviceIdKey, deviceId);
    return deviceId;
  }

  Future<int> nextSeq() async {
    final value = _settings.get(sequenceKey, defaultValue: 0);
    final current = value is int ? value : int.tryParse(value.toString()) ?? 0;
    final next = current + 1;
    await _settings.put(sequenceKey, next);
    return next;
  }

  Future<void> appendEvent(PrivateSyncEvent event) async {
    final file = await localEventFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '${jsonEncode(event.toJson())}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  Future<List<PrivateSyncEvent>> readEvents() async {
    final file = await localEventFile();
    if (!await file.exists()) {
      return [];
    }
    final content = await file.readAsString();
    return const LineSplitter()
        .convert(content)
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map(
          (line) => PrivateSyncEvent.fromJson(
            Map<String, dynamic>.from(jsonDecode(line) as Map),
          ),
        )
        .toList();
  }

  Future<void> replaceEvents(Iterable<PrivateSyncEvent> events) async {
    final file = await localEventFile();
    await file.parent.create(recursive: true);
    final lines = events.map((event) => jsonEncode(event.toJson())).join('\n');
    await file.writeAsString(lines.isEmpty ? '' : '$lines\n', flush: true);
  }

  Future<void> clearEvents() async {
    final file = await localEventFile();
    if (await file.exists()) {
      await file.writeAsString('', flush: true);
    }
  }

  Future<File> localEventFile() async {
    final explicit = _localEventFile;
    if (explicit != null) {
      return explicit;
    }
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/sync/private-sync.local.jsonl');
  }

  static String _generateDeviceId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return [
      hex.substring(0, 8),
      hex.substring(8, 12),
      hex.substring(12, 16),
      hex.substring(16, 20),
      hex.substring(20),
    ].join('-');
  }
}

class PrivateSyncWatchDebouncer {
  PrivateSyncWatchDebouncer({
    this.minProgressDelta = const Duration(seconds: 20),
  });

  final Duration minProgressDelta;
  final Map<String, _WatchEmitState> _states = {};

  bool shouldEmit({
    required String entityKey,
    required int episode,
    required int road,
    required Duration progress,
  }) {
    final state = _states[entityKey];
    if (state == null ||
        state.episode != episode ||
        state.road != road ||
        (progress - state.progress).abs() >= minProgressDelta) {
      _states[entityKey] = _WatchEmitState(
        episode: episode,
        road: road,
        progress: progress,
      );
      return true;
    }
    return false;
  }

  void reset({String? entityKey}) {
    if (entityKey == null) {
      _states.clear();
      return;
    }
    _states.remove(entityKey);
  }
}

class PrivateSyncTriggerThrottler {
  PrivateSyncTriggerThrottler({
    this.minInterval = const Duration(minutes: 5),
  });

  final Duration minInterval;
  DateTime? _lastTriggeredAt;

  bool shouldTrigger(DateTime now) {
    final lastTriggeredAt = _lastTriggeredAt;
    if (lastTriggeredAt == null ||
        now.difference(lastTriggeredAt) >= minInterval) {
      _lastTriggeredAt = now;
      return true;
    }
    return false;
  }

  void reset() {
    _lastTriggeredAt = null;
  }
}

class PrivateSyncService {
  static const int maxEventsPerMerge = 100;

  static final PrivateSyncWatchDebouncer _sharedWatchDebouncer =
      PrivateSyncWatchDebouncer();
  static final PrivateSyncTriggerThrottler _sharedPlaybackSyncThrottler =
      PrivateSyncTriggerThrottler();
  static Future<PrivateSyncSyncResult>? _sharedSyncInFlight;
  static int _syncGeneration = 0;

  PrivateSyncService({
    PrivateSyncSettingsStore settings = const HivePrivateSyncSettingsStore(),
    PrivateSyncLocalStore? localStore,
    PrivateSyncApiClient? api,
    PrivateSyncWatchDebouncer? watchDebouncer,
    PrivateSyncTriggerThrottler? playbackSyncThrottler,
    DateTime Function()? now,
  })  : _settings = settings,
        _localStore = localStore ?? PrivateSyncLocalStore(settings: settings),
        _api = api,
        _watchDebouncer = watchDebouncer ?? _sharedWatchDebouncer,
        _playbackSyncThrottler =
            playbackSyncThrottler ?? _sharedPlaybackSyncThrottler,
        _now = now ?? DateTime.now;

  final PrivateSyncSettingsStore _settings;
  final PrivateSyncLocalStore _localStore;
  final PrivateSyncApiClient? _api;
  final PrivateSyncWatchDebouncer _watchDebouncer;
  final PrivateSyncTriggerThrottler _playbackSyncThrottler;
  final DateTime Function() _now;
  Future<void>? lastPlaybackSync;

  Future<void> appendWatchUpsert({
    required History history,
    required int episode,
    required int road,
    required int progressMs,
    int? updatedAt,
    bool force = false,
  }) async {
    if (!_enabled(SettingBoxKey.privateSyncEnableWatch)) {
      return;
    }
    if (!force &&
        !_watchDebouncer.shouldEmit(
          entityKey: history.key,
          episode: episode,
          road: road,
          progress: Duration(milliseconds: progressMs),
        )) {
      return;
    }
    final event = PrivateSyncEvent.watchUpsert(
      eventId: await _nextEventId(),
      deviceId: await _localStore.getDeviceId(),
      seq: _lastSeq,
      updatedAt: updatedAt ?? history.lastWatchTime.millisecondsSinceEpoch,
      entityKey: history.key,
      adapterName: history.adapterName,
      bangumiItem: history.bangumiItem,
      episode: episode,
      lastWatchEpisode: history.lastWatchEpisode,
      road: road,
      progressMs: progressMs,
      lastSrc: history.lastSrc,
      lastWatchEpisodeName: history.lastWatchEpisodeName,
      lastWatchTime: history.lastWatchTime.millisecondsSinceEpoch,
    );
    await _localStore.appendEvent(event);
  }

  Future<void> appendWatchDelete(History history) async {
    if (!_enabled(SettingBoxKey.privateSyncEnableWatch)) {
      return;
    }
    final event = PrivateSyncEvent.watchDelete(
      eventId: await _nextEventId(),
      deviceId: await _localStore.getDeviceId(),
      seq: _lastSeq,
      updatedAt: _now().millisecondsSinceEpoch,
      entityKey: history.key,
    );
    await _localStore.appendEvent(event);
    _watchDebouncer.reset(entityKey: history.key);
  }

  Future<void> appendWatchClearAll() async {
    if (!_enabled(SettingBoxKey.privateSyncEnableWatch)) {
      return;
    }
    final event = PrivateSyncEvent.watchClearAll(
      eventId: await _nextEventId(),
      deviceId: await _localStore.getDeviceId(),
      seq: _lastSeq,
      updatedAt: _now().millisecondsSinceEpoch,
    );
    await _localStore.appendEvent(event);
    _watchDebouncer.reset();
  }

  Future<void> appendCollectionUpsert(CollectedBangumi collectible) async {
    if (!_enabled(SettingBoxKey.privateSyncEnableCollect)) {
      return;
    }
    await _appendCollectionUpsert(collectible);
  }

  Future<void> appendCollectionDelete(int bangumiId) async {
    if (!_enabled(SettingBoxKey.privateSyncEnableCollect)) {
      return;
    }
    final event = PrivateSyncEvent.collectionDelete(
      eventId: await _nextEventId(),
      deviceId: await _localStore.getDeviceId(),
      seq: _lastSeq,
      updatedAt: _now().millisecondsSinceEpoch,
      bangumiId: bangumiId,
    );
    await _localStore.appendEvent(event);
  }

  Future<void> applySnapshot(
    PrivateSyncSnapshot snapshot, {
    bool applyWatch = true,
    bool applyCollection = true,
  }) async {
    if (applyWatch) {
      await _applyWatchSnapshot(snapshot.watch);
    }
    if (applyCollection) {
      await _applyCollectionSnapshot(snapshot.collection);
    }
  }

  Future<void> importExistingLocalDataIfNeeded() async {
    final syncEnabled =
        _settings.get(SettingBoxKey.privateSyncEnable, defaultValue: false) ==
            true;
    if (!syncEnabled) {
      return;
    }
    if (_enabled(SettingBoxKey.privateSyncEnableWatch) &&
        _settings.get(
              SettingBoxKey.privateSyncWatchImported,
              defaultValue: false,
            ) !=
            true) {
      await _importWatchHistories();
      await _settings.put(SettingBoxKey.privateSyncWatchImported, true);
    }
    if (_enabled(SettingBoxKey.privateSyncEnableCollect) &&
        _settings.get(
              SettingBoxKey.privateSyncCollectImported,
              defaultValue: false,
            ) !=
            true) {
      await _importCollectibles();
      await _settings.put(SettingBoxKey.privateSyncCollectImported, true);
    }
  }

  Future<PrivateSyncSyncResult> syncNow() {
    return _syncWithSharedInFlight(() => _syncNowInternal());
  }

  Future<PrivateSyncSyncResult> syncNowWithStrategy(
    PrivateSyncEnableStrategy strategy, {
    bool forceLocalSnapshot = false,
    bool? forceWatchSnapshot,
    bool? forceCollectionSnapshot,
  }) {
    final hasDomainSelection =
        forceWatchSnapshot != null || forceCollectionSnapshot != null;
    if (strategy == PrivateSyncEnableStrategy.merge &&
        !forceLocalSnapshot &&
        !hasDomainSelection) {
      return syncNow();
    }
    return _syncStrategyAfterCurrentInFlight(
      strategy,
      forceLocalSnapshot: forceLocalSnapshot,
      forceWatchSnapshot: forceWatchSnapshot,
      forceCollectionSnapshot: forceCollectionSnapshot,
    );
  }

  Future<PrivateSyncSyncResult> _syncWithSharedInFlight(
    Future<PrivateSyncSyncResult> Function() sync,
  ) {
    final inFlight = _sharedSyncInFlight;
    if (inFlight != null) {
      return inFlight;
    }
    final future = sync();
    _sharedSyncInFlight = future;
    return future.whenComplete(() {
      if (identical(_sharedSyncInFlight, future)) {
        _sharedSyncInFlight = null;
      }
    });
  }

  Future<PrivateSyncSyncResult> _syncStrategyAfterCurrentInFlight(
    PrivateSyncEnableStrategy strategy, {
    required bool forceLocalSnapshot,
    bool? forceWatchSnapshot,
    bool? forceCollectionSnapshot,
  }) async {
    _syncGeneration++;
    final inFlight = _sharedSyncInFlight;
    if (inFlight != null) {
      try {
        await inFlight;
      } catch (_) {}
    }
    final future = _syncNowInternal(
      strategy: strategy,
      forceLocalSnapshot: forceLocalSnapshot,
      forceWatchSnapshot: forceWatchSnapshot,
      forceCollectionSnapshot: forceCollectionSnapshot,
    );
    _sharedSyncInFlight = future;
    return future.whenComplete(() {
      if (identical(_sharedSyncInFlight, future)) {
        _sharedSyncInFlight = null;
      }
    });
  }

  Future<void> syncInBackground({String reason = 'background'}) async {
    try {
      await importExistingLocalDataIfNeeded();
      await syncNow();
    } catch (e, stackTrace) {
      KazumiLogger().w(
        'PrivateSync: automatic sync failed. reason=$reason',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  bool syncPlaybackProgressInBackground() {
    if (!_enabled(SettingBoxKey.privateSyncEnableWatch)) {
      return false;
    }
    if (!_playbackSyncThrottler.shouldTrigger(_now())) {
      return false;
    }
    lastPlaybackSync = syncInBackground(reason: 'playback');
    unawaited(lastPlaybackSync);
    return true;
  }

  int _lastSeq = 0;

  Future<String> _nextEventId() async {
    final deviceId = await _localStore.getDeviceId();
    _lastSeq = await _localStore.nextSeq();
    return '$deviceId:$_lastSeq';
  }

  bool _enabled(String domainKey) {
    final syncEnabled =
        _settings.get(SettingBoxKey.privateSyncEnable, defaultValue: false) ==
            true;
    final domainEnabled = _settings.get(domainKey, defaultValue: false) == true;
    return syncEnabled && domainEnabled;
  }

  Future<PrivateSyncSyncResult> _syncNowInternal({
    PrivateSyncEnableStrategy strategy = PrivateSyncEnableStrategy.merge,
    bool forceLocalSnapshot = false,
    bool? forceWatchSnapshot,
    bool? forceCollectionSnapshot,
  }) async {
    final syncEnabled =
        _settings.get(SettingBoxKey.privateSyncEnable, defaultValue: false) ==
            true;
    if (!syncEnabled) {
      return const PrivateSyncSyncResult(
        uploadedEventCount: 0,
        remainingEventCount: 0,
      );
    }

    final deviceId = await _localStore.getDeviceId();
    final api = _api ?? PrivateSyncApi();
    late final PrivateSyncMergeResult result;
    var uploadedEventCount = 0;
    final hasDomainSelection =
        forceWatchSnapshot != null || forceCollectionSnapshot != null;
    final activeWatchDomain = _enabled(SettingBoxKey.privateSyncEnableWatch);
    final activeCollectionDomain =
        _enabled(SettingBoxKey.privateSyncEnableCollect);
    final strategyWatchDomain =
        activeWatchDomain && (forceWatchSnapshot ?? true);
    final strategyCollectionDomain =
        activeCollectionDomain && (forceCollectionSnapshot ?? true);
    final isExplicitEnableSync = strategy != PrivateSyncEnableStrategy.merge ||
        forceLocalSnapshot ||
        hasDomainSelection;
    final generation =
        isExplicitEnableSync ? ++_syncGeneration : _syncGeneration;
    try {
      await api.registerDevice(
        deviceId: deviceId,
        deviceName: _deviceName(),
        platform: Platform.operatingSystem,
        appVersion: ApiEndpoints.version,
      );
      switch (strategy) {
        case PrivateSyncEnableStrategy.cloudFirst:
          await _clearPendingLocalOverrideDomains(
            watch: strategyWatchDomain,
            collection: strategyCollectionDomain,
          );
          await _removePendingEventsForDomains(
            watch: strategyWatchDomain,
            collection: strategyCollectionDomain,
          );
          result = await _uploadPendingEventsInBatches(api, deviceId);
          uploadedEventCount = result.acceptedEventIds.length +
              result.ignoredDuplicateEventIds.length;
        case PrivateSyncEnableStrategy.localFirst:
          await _prepareLocalOverrideEvents(
            watch: strategyWatchDomain,
            collection: strategyCollectionDomain,
            eventUpdatedAt: _now().millisecondsSinceEpoch,
          );
          await _clearPendingRemoteForLocalOverride(
            api,
            watch: strategyWatchDomain,
            collection: strategyCollectionDomain,
          );
          result = await _uploadPendingEventsInBatches(api, deviceId);
          uploadedEventCount = result.acceptedEventIds.length +
              result.ignoredDuplicateEventIds.length;
        case PrivateSyncEnableStrategy.merge:
          if (forceLocalSnapshot) {
            await _removePendingEventsForDomains(
              watch: strategyWatchDomain,
              collection: strategyCollectionDomain,
            );
            await _importExistingLocalData(
              eventUpdatedAt: _now().millisecondsSinceEpoch,
              importWatch: strategyWatchDomain,
              importCollection: strategyCollectionDomain,
              includeDeletesFromBaseline: true,
            );
          } else {
            await importExistingLocalDataIfNeeded();
          }
          await _clearPendingRemoteForLocalOverride(
            api,
            watch: activeWatchDomain,
            collection: activeCollectionDomain,
          );
          result = await _uploadPendingEventsInBatches(api, deviceId);
          uploadedEventCount = result.acceptedEventIds.length +
              result.ignoredDuplicateEventIds.length;
      }
    } on PrivateSyncAuthenticationException {
      await markAuthenticationExpired(_settings);
      rethrow;
    }
    if (generation != _syncGeneration) {
      final remaining = await _localStore.readEvents();
      return PrivateSyncSyncResult(
        uploadedEventCount: uploadedEventCount,
        remainingEventCount: remaining.length,
      );
    }
    await applySnapshot(
      result.snapshot,
      applyWatch: activeWatchDomain,
      applyCollection: activeCollectionDomain,
    );
    if (isExplicitEnableSync) {
      await _markImportedDomains(
        watch: strategyWatchDomain,
        collection: strategyCollectionDomain,
      );
    }

    final remaining = await _removeAckedEvents(result);
    return PrivateSyncSyncResult(
      uploadedEventCount: uploadedEventCount,
      remainingEventCount: remaining.length,
    );
  }

  Future<PrivateSyncMergeResult> _uploadPendingEventsInBatches(
    PrivateSyncApiClient api,
    String deviceId,
  ) async {
    final pending = await _localStore.readEvents();
    if (pending.isEmpty) {
      return api.merge(
        deviceId: deviceId,
        clientSeq: 0,
        events: const [],
      );
    }

    final acceptedEventIds = <String>[];
    final ignoredDuplicateEventIds = <String>[];
    PrivateSyncSnapshot? snapshot;
    for (var offset = 0; offset < pending.length; offset += maxEventsPerMerge) {
      final end = min(offset + maxEventsPerMerge, pending.length);
      final batch = pending.sublist(offset, end);
      final result = await api.merge(
        deviceId: deviceId,
        clientSeq: _maxSeq(batch),
        events: batch,
      );
      acceptedEventIds.addAll(result.acceptedEventIds);
      ignoredDuplicateEventIds.addAll(result.ignoredDuplicateEventIds);
      snapshot = result.snapshot;
    }
    return PrivateSyncMergeResult(
      acceptedEventIds: acceptedEventIds,
      ignoredDuplicateEventIds: ignoredDuplicateEventIds,
      snapshot: snapshot!,
    );
  }

  Future<List<PrivateSyncEvent>> _removeAckedEvents(
    PrivateSyncMergeResult result,
  ) async {
    final acked = {
      ...result.acceptedEventIds,
      ...result.ignoredDuplicateEventIds,
    };
    final currentEvents = await _localStore.readEvents();
    final remaining = currentEvents
        .where((event) => !acked.contains(event.eventId))
        .toList(growable: false);
    await _localStore.replaceEvents(remaining);
    return remaining;
  }

  Future<void> _removePendingEventsForDomains({
    required bool watch,
    required bool collection,
  }) async {
    if (!watch && !collection) {
      return;
    }
    final events = await _localStore.readEvents();
    final remaining = events
        .where((event) =>
            !(watch && event.domain == 'watch') &&
            !(collection && event.domain == 'collection'))
        .toList(growable: false);
    await _localStore.replaceEvents(remaining);
  }

  Future<void> _prepareLocalOverrideEvents({
    required bool watch,
    required bool collection,
    required int eventUpdatedAt,
  }) async {
    if (!watch && !collection) {
      return;
    }
    if (watch) {
      await _settings.put(
        SettingBoxKey.privateSyncPendingLocalOverrideWatch,
        true,
      );
    }
    if (collection) {
      await _settings.put(
        SettingBoxKey.privateSyncPendingLocalOverrideCollect,
        true,
      );
    }
    await _removePendingEventsForDomains(
      watch: watch,
      collection: collection,
    );
    await _importExistingLocalData(
      eventUpdatedAt: eventUpdatedAt,
      importWatch: watch,
      importCollection: collection,
      includeDeletesFromBaseline: false,
    );
    await _markImportedDomains(
      watch: watch,
      collection: collection,
    );
  }

  Future<void> _clearPendingRemoteForLocalOverride(
    PrivateSyncApiClient api, {
    required bool watch,
    required bool collection,
  }) async {
    final pendingWatch = watch &&
        _settings.get(
              SettingBoxKey.privateSyncPendingLocalOverrideWatch,
              defaultValue: false,
            ) ==
            true;
    final pendingCollection = collection &&
        _settings.get(
              SettingBoxKey.privateSyncPendingLocalOverrideCollect,
              defaultValue: false,
            ) ==
            true;
    if (!pendingWatch && !pendingCollection) {
      return;
    }
    await api.clearData(
      watch: pendingWatch,
      collection: pendingCollection,
    );
    await _clearPendingLocalOverrideDomains(
      watch: pendingWatch,
      collection: pendingCollection,
    );
  }

  Future<void> _clearPendingLocalOverrideDomains({
    required bool watch,
    required bool collection,
  }) async {
    if (watch) {
      await _settings.put(
        SettingBoxKey.privateSyncPendingLocalOverrideWatch,
        false,
      );
    }
    if (collection) {
      await _settings.put(
        SettingBoxKey.privateSyncPendingLocalOverrideCollect,
        false,
      );
    }
  }

  String _deviceName() {
    final configured = _settings
        .get(SettingBoxKey.privateSyncDeviceName, defaultValue: '')
        .toString()
        .trim();
    if (configured.isNotEmpty) {
      return configured;
    }
    return Platform.localHostname;
  }

  static int _maxSeq(List<PrivateSyncEvent> events) {
    var max = 0;
    for (final event in events) {
      if (event.seq > max) {
        max = event.seq;
      }
    }
    return max;
  }

  static Future<void> markAuthenticationExpired(
    PrivateSyncSettingsStore settings,
  ) async {
    await settings.put(SettingBoxKey.privateSyncEnable, false);
    await settings.put(SettingBoxKey.privateSyncToken, '');
    await settings.put(SettingBoxKey.privateSyncDisplayName, '');
    await settings.put(SettingBoxKey.privateSyncWatchImported, false);
    await settings.put(SettingBoxKey.privateSyncCollectImported, false);
    await settings.put(SettingBoxKey.privateSyncWatchBaseline, '');
    await settings.put(SettingBoxKey.privateSyncCollectBaseline, '');
    await settings.put(
        SettingBoxKey.privateSyncPendingLocalOverrideWatch, false);
    await settings.put(
      SettingBoxKey.privateSyncPendingLocalOverrideCollect,
      false,
    );
  }

  static Future<void> saveAuthenticationResult({
    required PrivateSyncSettingsStore settings,
    required PrivateSyncLocalStore localStore,
    required PrivateSyncAuthResult result,
    required String loginName,
    required String previousLoginName,
    required String previousToken,
    required String deviceName,
    required bool enableSync,
  }) async {
    final normalizedLoginName = loginName.trim();
    final changedAccount = previousLoginName.trim().isNotEmpty &&
        previousLoginName.trim() != normalizedLoginName;
    final firstAccountLogin =
        previousLoginName.trim().isEmpty && previousToken.trim().isEmpty;
    if (changedAccount || firstAccountLogin) {
      await localStore.clearEvents();
      await settings.put(SettingBoxKey.privateSyncWatchImported, false);
      await settings.put(SettingBoxKey.privateSyncCollectImported, false);
      await settings.put(SettingBoxKey.privateSyncWatchBaseline, '');
      await settings.put(SettingBoxKey.privateSyncCollectBaseline, '');
      await settings.put(
        SettingBoxKey.privateSyncPendingLocalOverrideWatch,
        false,
      );
      await settings.put(
        SettingBoxKey.privateSyncPendingLocalOverrideCollect,
        false,
      );
    }
    await settings.put(SettingBoxKey.privateSyncToken, result.token);
    await settings.put(SettingBoxKey.privateSyncLoginName, normalizedLoginName);
    await settings.put(
      SettingBoxKey.privateSyncDisplayName,
      result.displayName,
    );
    await settings.put(SettingBoxKey.privateSyncEnable, enableSync);
    await settings.put(SettingBoxKey.privateSyncEnableWatch, true);
    await settings.put(SettingBoxKey.privateSyncEnableCollect, true);
    await settings.put(SettingBoxKey.privateSyncDeviceName, deviceName.trim());
  }

  Future<void> _applyWatchSnapshot(PrivateSyncWatchSnapshot snapshot) async {
    await GStorage.histories.clear();
    for (final remote in snapshot.histories) {
      final history = History(
        remote.bangumiItem,
        remote.lastWatchEpisode,
        remote.adapterName,
        DateTime.fromMillisecondsSinceEpoch(remote.lastWatchTime),
        remote.lastSrc,
        remote.lastWatchEpisodeName,
      );
      for (final progress in remote.progresses.values) {
        history.progresses[progress.episode] = Progress(
          progress.episode,
          progress.road,
          progress.progressMs,
        );
      }
      await GStorage.histories.put(remote.entityKey, history);
    }
    await GStorage.histories.flush();
    await _settings.put(
      SettingBoxKey.privateSyncWatchBaseline,
      _encodeBaselineKeys(
          snapshot.histories.map((history) => history.entityKey)),
    );
  }

  Future<void> _applyCollectionSnapshot(
    PrivateSyncCollectionSnapshot snapshot,
  ) async {
    await GStorage.collectibles.clear();
    for (final remote in snapshot.items) {
      if (remote.type < 1 || remote.type > 5) {
        continue;
      }
      final collectible = CollectedBangumi(
        remote.bangumiItem,
        DateTime.fromMillisecondsSinceEpoch(
          remote.collectedAt ?? remote.updatedAt,
        ),
        remote.type,
      );
      await GStorage.collectibles.put(remote.bangumiId, collectible);
    }
    await GStorage.collectibles.flush();
    await _settings.put(
      SettingBoxKey.privateSyncCollectBaseline,
      _encodeBaselineKeys(
        snapshot.items.map((item) => item.bangumiId.toString()),
      ),
    );
  }

  Future<void> _importExistingLocalData({
    int? eventUpdatedAt,
    bool importWatch = true,
    bool importCollection = true,
    bool includeDeletesFromBaseline = false,
  }) async {
    if (importWatch && _enabled(SettingBoxKey.privateSyncEnableWatch)) {
      await _importWatchHistories(
        eventUpdatedAt: eventUpdatedAt,
        includeDeletesFromBaseline: includeDeletesFromBaseline,
      );
    }
    if (importCollection && _enabled(SettingBoxKey.privateSyncEnableCollect)) {
      await _importCollectibles(
        eventUpdatedAt: eventUpdatedAt,
        includeDeletesFromBaseline: includeDeletesFromBaseline,
      );
    }
  }

  Future<void> _markImportedDomains({
    bool watch = true,
    bool collection = true,
  }) async {
    if (watch && _enabled(SettingBoxKey.privateSyncEnableWatch)) {
      await _settings.put(SettingBoxKey.privateSyncWatchImported, true);
    }
    if (collection && _enabled(SettingBoxKey.privateSyncEnableCollect)) {
      await _settings.put(SettingBoxKey.privateSyncCollectImported, true);
    }
  }

  Future<void> _importWatchHistories({
    int? eventUpdatedAt,
    bool includeDeletesFromBaseline = false,
  }) async {
    final histories = GStorage.histories.values.toList()
      ..sort(
        (a, b) => a.lastWatchTime.millisecondsSinceEpoch.compareTo(
          b.lastWatchTime.millisecondsSinceEpoch,
        ),
      );
    final localKeys = histories.map((history) => history.key).toSet();
    if (includeDeletesFromBaseline &&
        _settings.get(
              SettingBoxKey.privateSyncWatchImported,
              defaultValue: false,
            ) ==
            true) {
      final baseline =
          _readBaselineKeys(SettingBoxKey.privateSyncWatchBaseline);
      for (final deletedKey in baseline.difference(localKeys).toList()
        ..sort()) {
        final updatedAt = eventUpdatedAt ?? _now().millisecondsSinceEpoch;
        await _localStore.appendEvent(
          PrivateSyncEvent.watchDelete(
            eventId: await _nextEventId(),
            deviceId: await _localStore.getDeviceId(),
            seq: _lastSeq,
            updatedAt: updatedAt,
            entityKey: deletedKey,
          ),
        );
        _watchDebouncer.reset(entityKey: deletedKey);
      }
    }
    for (final history in histories) {
      final progresses = history.progresses.values.toList()
        ..sort((a, b) => a.episode.compareTo(b.episode));
      for (final progress in progresses) {
        await appendWatchUpsert(
          history: history,
          episode: progress.episode,
          road: progress.road,
          progressMs: progress.progress.inMilliseconds,
          updatedAt:
              eventUpdatedAt ?? history.lastWatchTime.millisecondsSinceEpoch,
          force: true,
        );
      }
    }
  }

  Future<void> _importCollectibles({
    int? eventUpdatedAt,
    bool includeDeletesFromBaseline = false,
  }) async {
    final collectibles = GStorage.collectibles.values.toList()
      ..sort((a, b) => a.bangumiItem.id.compareTo(b.bangumiItem.id));
    final localIds =
        collectibles.map((item) => item.bangumiItem.id.toString()).toSet();
    if (includeDeletesFromBaseline &&
        _settings.get(
              SettingBoxKey.privateSyncCollectImported,
              defaultValue: false,
            ) ==
            true) {
      final baseline =
          _readBaselineKeys(SettingBoxKey.privateSyncCollectBaseline);
      for (final deletedId in baseline.difference(localIds).toList()..sort()) {
        final bangumiId = int.tryParse(deletedId);
        if (bangumiId == null) {
          continue;
        }
        await appendCollectionDelete(bangumiId);
      }
    }
    for (final collectible in collectibles) {
      await _appendCollectionUpsert(collectible, updatedAt: eventUpdatedAt);
    }
  }

  Future<void> _appendCollectionUpsert(
    CollectedBangumi collectible, {
    int? updatedAt,
  }) async {
    final event = PrivateSyncEvent.collectionUpsert(
      eventId: await _nextEventId(),
      deviceId: await _localStore.getDeviceId(),
      seq: _lastSeq,
      updatedAt: updatedAt ?? _now().millisecondsSinceEpoch,
      bangumiItem: collectible.bangumiItem,
      type: collectible.type,
      collectedAt: collectible.time.millisecondsSinceEpoch,
    );
    await _localStore.appendEvent(event);
  }

  Set<String> _readBaselineKeys(String key) {
    final raw = _settings.get(key, defaultValue: '').toString();
    if (raw.trim().isEmpty) {
      return {};
    }
    return raw
        .split('\n')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
  }

  static String _encodeBaselineKeys(Iterable<String> keys) {
    final sorted = keys
        .map((key) => key.trim())
        .where((key) => key.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return sorted.join('\n');
  }
}

class _WatchEmitState {
  const _WatchEmitState({
    required this.episode,
    required this.road,
    required this.progress,
  });

  final int episode;
  final int road;
  final Duration progress;
}

class PrivateSyncSyncResult {
  const PrivateSyncSyncResult({
    required this.uploadedEventCount,
    required this.remainingEventCount,
  });

  final int uploadedEventCount;
  final int remainingEventCount;
}
