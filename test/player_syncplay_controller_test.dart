import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/pages/player/controller/player_syncplay_controller.dart';
import 'package:kazumi/services/player/syncplay_client.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:logger/logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlayerSyncPlayController room switching', () {
    late Directory tempDir;
    late Box<dynamic> setting;

    setUp(() async {
      final previousLevel = Logger.level;
      Logger.level = Level.fatal;
      addTearDown(() {
        Logger.level = previousLevel;
      });
      tempDir = await Directory.systemTemp.createTemp('aslan-syncplay-');
      Hive.init(tempDir.path);
      setting = await Hive.openBox<dynamic>('setting');
    });

    tearDown(() async {
      await Hive.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('keeps the current room when switching fails before join confirmation',
        () async {
      final oldClient = _FakeSyncplayClient();
      final newClient = _FakeSyncplayClient(
        joinError: SyncplayConnectionException('offline'),
      );
      final controller = PlayerSyncPlayController(
        setting: setting,
        bangumiId: () => 1,
        currentEpisode: () => 1,
        currentRoad: () => 0,
        playing: () => false,
        currentPosition: () => Duration.zero,
        playerPosition: () => Duration.zero,
        duration: () => const Duration(minutes: 20),
        pause: ({bool enableSync = true}) async {},
        play: ({bool enableSync = true}) async {},
        seek: (duration, {bool enableSync = true}) async {},
        syncplayClientFactory: ({required host, required port}) => newClient,
      );
      controller.syncplayController = oldClient;
      controller.syncplayRoom = '111111';

      await setting.put(SettingBoxKey.syncPlayEndPoint, '127.0.0.1:8996');
      await controller.createRoom(
        '222222',
        'aslan',
        (episode, {currentRoad = 0, offset = 0}) async {},
        enableTLS: false,
      );

      expect(controller.syncplayController, same(oldClient));
      expect(controller.syncplayRoom, '111111');
      expect(oldClient.disconnectCount, 0);
      expect(newClient.disconnectCount, 1);
    });

    test('keeps the current room when joining candidate is disconnected',
        () async {
      final oldClient = _FakeSyncplayClient();
      final newClient = _FakeSyncplayClient(
        joinError: SyncplayConnectionException(
          'SyncPlay: disconnected while joining room',
        ),
      );
      final controller = PlayerSyncPlayController(
        setting: setting,
        bangumiId: () => 1,
        currentEpisode: () => 1,
        currentRoad: () => 0,
        playing: () => false,
        currentPosition: () => Duration.zero,
        playerPosition: () => Duration.zero,
        duration: () => const Duration(minutes: 20),
        pause: ({bool enableSync = true}) async {},
        play: ({bool enableSync = true}) async {},
        seek: (duration, {bool enableSync = true}) async {},
        syncplayClientFactory: ({required host, required port}) => newClient,
      );
      controller.syncplayController = oldClient;
      controller.syncplayRoom = '111111';

      await setting.put(SettingBoxKey.syncPlayEndPoint, '127.0.0.1:8996');
      await controller.createRoom(
        '222222',
        'aslan',
        (episode, {currentRoad = 0, offset = 0}) async {},
        enableTLS: false,
      );

      expect(controller.syncplayController, same(oldClient));
      expect(controller.syncplayRoom, '111111');
      expect(oldClient.disconnectCount, 0);
      expect(newClient.disconnectCount, 1);
    });

    test('replaces the current room only after the new room is confirmed',
        () async {
      final oldClient = _FakeSyncplayClient();
      final newClient = _FakeSyncplayClient();
      final controller = PlayerSyncPlayController(
        setting: setting,
        bangumiId: () => 1,
        currentEpisode: () => 1,
        currentRoad: () => 0,
        playing: () => false,
        currentPosition: () => Duration.zero,
        playerPosition: () => Duration.zero,
        duration: () => const Duration(minutes: 20),
        pause: ({bool enableSync = true}) async {},
        play: ({bool enableSync = true}) async {},
        seek: (duration, {bool enableSync = true}) async {},
        syncplayClientFactory: ({required host, required port}) => newClient,
      );
      controller.syncplayController = oldClient;
      controller.syncplayRoom = '111111';

      await setting.put(SettingBoxKey.syncPlayEndPoint, '127.0.0.1:8996');
      await controller.createRoom(
        '222222',
        'aslan',
        (episode, {currentRoad = 0, offset = 0}) async {},
        enableTLS: false,
      );

      expect(controller.syncplayController, same(newClient));
      expect(controller.syncplayRoom, '222222');
      expect(oldClient.disconnectCount, 1);
      expect(newClient.disconnectCount, 0);
      expect(newClient.joinedRooms, ['222222']);
    });

    test('primes the new room with current local playback state', () async {
      final newClient = _FakeSyncplayClient();
      final controller = PlayerSyncPlayController(
        setting: setting,
        bangumiId: () => 1,
        currentEpisode: () => 1,
        currentRoad: () => 0,
        playing: () => true,
        currentPosition: () => const Duration(seconds: 30),
        playerPosition: () => const Duration(seconds: 30),
        duration: () => const Duration(minutes: 20),
        pause: ({bool enableSync = true}) async {},
        play: ({bool enableSync = true}) async {},
        seek: (duration, {bool enableSync = true}) async {},
        syncplayClientFactory: ({required host, required port}) => newClient,
      );

      await setting.put(SettingBoxKey.syncPlayEndPoint, '127.0.0.1:8996');
      await controller.createRoom(
        '222222',
        'aslan',
        (episode, {currentRoad = 0, offset = 0}) async {},
        enableTLS: false,
      );

      expect(newClient.pausedStates, [false]);
      expect(newClient.positions, [30.0]);
    });

    test('publishes media with the joining client when init arrives during join',
        () async {
      final newClient = _FakeSyncplayClient(emitInitDuringJoin: true);
      final controller = PlayerSyncPlayController(
        setting: setting,
        bangumiId: () => 1,
        currentEpisode: () => 2,
        currentRoad: () => 0,
        playing: () => true,
        currentPosition: () => const Duration(seconds: 45),
        playerPosition: () => const Duration(seconds: 45),
        duration: () => const Duration(minutes: 20),
        pause: ({bool enableSync = true}) async {},
        play: ({bool enableSync = true}) async {},
        seek: (duration, {bool enableSync = true}) async {},
        syncplayClientFactory: ({required host, required port}) => newClient,
      );

      await setting.put(SettingBoxKey.syncPlayEndPoint, '127.0.0.1:8996');
      await controller.createRoom(
        '222222',
        'aslan',
        (episode, {currentRoad = 0, offset = 0}) async {},
        enableTLS: false,
      );

      expect(controller.syncplayController, same(newClient));
      expect(newClient.playingFiles, ['1[2]']);
      expect(newClient.syncRequestCount, 1);
    });

    test('updates displayed latency from heartbeat updates', () async {
      final newClient = _FakeSyncplayClient();
      final controller = PlayerSyncPlayController(
        setting: setting,
        bangumiId: () => 1,
        currentEpisode: () => 1,
        currentRoad: () => 0,
        playing: () => true,
        currentPosition: () => const Duration(seconds: 30),
        playerPosition: () => const Duration(seconds: 30),
        duration: () => const Duration(minutes: 20),
        pause: ({bool enableSync = true}) async {},
        play: ({bool enableSync = true}) async {},
        seek: (duration, {bool enableSync = true}) async {},
        syncplayClientFactory: ({required host, required port}) => newClient,
      );

      await setting.put(SettingBoxKey.syncPlayEndPoint, '127.0.0.1:8996');
      await controller.createRoom(
        '222222',
        'aslan',
        (episode, {currentRoad = 0, offset = 0}) async {},
        enableTLS: false,
      );

      newClient.emitLatency(clientRtt: 0.123);

      expect(controller.syncplayClientRtt, 123);
    });
  });
}

class _FakeSyncplayClient extends SyncplayClient {
  _FakeSyncplayClient({this.joinError, this.emitInitDuringJoin})
      : super(host: InternetAddress.loopbackIPv4.address, port: 1);

  final SyncplayException? joinError;
  final bool? emitInitDuringJoin;
  final _roomMessages =
      StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final _latencyMessages =
      StreamController<Map<String, dynamic>>.broadcast(sync: true);
  var disconnectCount = 0;
  var syncRequestCount = 0;
  final joinedRooms = <String>[];
  final playingFiles = <String>[];
  final pausedStates = <bool>[];
  final positions = <double>[];

  @override
  Stream<Map<String, dynamic>> get onRoomMessage => _roomMessages.stream;

  @override
  Stream<Map<String, dynamic>> get onLatencyChangedMessage =>
      _latencyMessages.stream;

  void emitLatency({required double clientRtt}) {
    _latencyMessages.add({
      'clientRtt': clientRtt,
      'serverRtt': 0.0,
      'avrRtt': clientRtt,
      'fd': clientRtt / 2,
    });
  }

  @override
  Future<void> connect({bool enableTLS = true}) async {}

  @override
  Future<void> joinRoom(
    String room,
    String username, {
    Duration joinTimeout = const Duration(seconds: 8),
  }) async {
    if (joinError != null) {
      throw joinError!;
    }
    joinedRooms.add(room);
    if (emitInitDuringJoin ?? false) {
      _roomMessages.add({'type': 'init', 'username': ''});
    }
  }

  @override
  Future<void> disconnect() async {
    disconnectCount++;
  }

  @override
  Future<void> setSyncPlayPlaying(
      String bangumiName, double duration, int size) async {
    playingFiles.add(bangumiName);
  }

  @override
  Future<void> sendSyncPlaySyncRequest({bool? doSeek}) async {
    syncRequestCount++;
  }

  @override
  void setPaused(bool paused) {
    pausedStates.add(paused);
  }

  @override
  void setPosition(double position) {
    positions.add(position);
  }
}
