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
  static final PrivateSyncWatchDebouncer _sharedWatchDebouncer =
      PrivateSyncWatchDebouncer();
  static final PrivateSyncTriggerThrottler _sharedPlaybackSyncThrottler =
      PrivateSyncTriggerThrottler();
  static Future<PrivateSyncSyncResult>? _sharedSyncInFlight;

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
      road: road,
      progressMs: progressMs,
      lastSrc: history.lastSrc,
      lastWatchEpisodeName: history.lastWatchEpisodeName,
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
    final event = PrivateSyncEvent.collectionUpsert(
      eventId: await _nextEventId(),
      deviceId: await _localStore.getDeviceId(),
      seq: _lastSeq,
      updatedAt: _now().millisecondsSinceEpoch,
      bangumiItem: collectible.bangumiItem,
      type: collectible.type,
      collectedAt: collectible.time.millisecondsSinceEpoch,
    );
    await _localStore.appendEvent(event);
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
    final inFlight = _sharedSyncInFlight;
    if (inFlight != null) {
      return inFlight;
    }
    final future = _syncNowInternal();
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

  Future<PrivateSyncSyncResult> _syncNowInternal() async {
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
    final pending = await _localStore.readEvents();
    final api = _api ?? PrivateSyncApi();
    await api.registerDevice(
      deviceId: deviceId,
      deviceName: _deviceName(),
      platform: Platform.operatingSystem,
      appVersion: ApiEndpoints.version,
    );

    late final PrivateSyncMergeResult result;
    try {
      result = await api.merge(
        deviceId: deviceId,
        clientSeq: _maxSeq(pending),
        events: pending,
      );
    } on PrivateSyncAuthenticationException {
      await _settings.put(SettingBoxKey.privateSyncEnable, false);
      rethrow;
    }
    await applySnapshot(
      result.snapshot,
      applyWatch: _enabled(SettingBoxKey.privateSyncEnableWatch),
      applyCollection: _enabled(SettingBoxKey.privateSyncEnableCollect),
    );

    final acked = {
      ...result.acceptedEventIds,
      ...result.ignoredDuplicateEventIds,
    };
    final currentEvents = await _localStore.readEvents();
    final remaining = currentEvents
        .where((event) => !acked.contains(event.eventId))
        .toList(growable: false);
    await _localStore.replaceEvents(remaining);
    return PrivateSyncSyncResult(
      uploadedEventCount: acked.length,
      remainingEventCount: remaining.length,
    );
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
  }

  Future<void> _applyCollectionSnapshot(
    PrivateSyncCollectionSnapshot snapshot,
  ) async {
    await GStorage.collectibles.clear();
    for (final remote in snapshot.items) {
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
  }

  Future<void> _importWatchHistories() async {
    final histories = GStorage.histories.values.toList()
      ..sort(
        (a, b) => a.lastWatchTime.millisecondsSinceEpoch.compareTo(
          b.lastWatchTime.millisecondsSinceEpoch,
        ),
      );
    for (final history in histories) {
      final progresses = history.progresses.values.toList()
        ..sort((a, b) => a.episode.compareTo(b.episode));
      for (final progress in progresses) {
        await appendWatchUpsert(
          history: history,
          episode: progress.episode,
          road: progress.road,
          progressMs: progress.progress.inMilliseconds,
          updatedAt: history.lastWatchTime.millisecondsSinceEpoch,
          force: true,
        );
      }
    }
  }

  Future<void> _importCollectibles() async {
    final collectibles = GStorage.collectibles.values.toList()
      ..sort((a, b) => a.bangumiItem.id.compareTo(b.bangumiItem.id));
    for (final collectible in collectibles) {
      await appendCollectionUpsert(collectible);
    }
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
