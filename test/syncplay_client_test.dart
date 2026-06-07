import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/player/syncplay_client.dart';

void main() {
  group('SyncplayClient connection handling', () {
    late List<ServerSocket> servers;

    setUp(() {
      servers = [];
    });

    tearDown(() async {
      for (final server in servers) {
        await server.close();
      }
    });

    test('throws and remains disconnected when socket connection fails',
        () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      await server.close();

      final client = SyncplayClient(
          host: InternetAddress.loopbackIPv4.address, port: port);

      await expectLater(
        client.connect(enableTLS: false),
        throwsA(isA<SyncplayConnectionException>()),
      );
      expect(client.isConnected, isFalse);
    });

    test('throws instead of joining when not connected', () async {
      final client =
          SyncplayClient(host: InternetAddress.loopbackIPv4.address, port: 1);

      await expectLater(
        client.joinRoom('123456', 'aslan'),
        throwsA(isA<SyncplayConnectionException>()),
      );
      expect(client.currentRoom, isNull);
    });

    test('waits for server Hello before joining a room', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      servers.add(server);
      late Socket socket;
      final socketReady = Completer<void>();

      server.listen((clientSocket) {
        socket = clientSocket;
        socketReady.complete();
      });

      final client = SyncplayClient(
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
      );
      await client.connect(enableTLS: false);
      await socketReady.future;

      final joinFuture = client.joinRoom(
        '123456',
        'aslan',
        joinTimeout: const Duration(milliseconds: 200),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(client.currentRoom, isNull);

      socket.write(
        '{"Hello":{"username":"aslan","room":{"name":"123456"},"version":"1.7.0"}}\r\n',
      );

      await joinFuture;
      expect(client.currentRoom, '123456');
      await client.disconnect();
      await socket.close();
    });

    test('accepts server-renamed username when joining a room', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      servers.add(server);
      late Socket socket;
      final socketReady = Completer<void>();

      server.listen((clientSocket) {
        socket = clientSocket;
        socketReady.complete();
      });

      final client = SyncplayClient(
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
      );
      await client.connect(enableTLS: false);
      await socketReady.future;

      final joinFuture = client.joinRoom(
        '123456',
        'aslan',
        joinTimeout: const Duration(milliseconds: 200),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      socket.write(
        '{"Hello":{"username":"aslan_","room":{"name":"123456"},"version":"1.7.0"}}\r\n',
      );

      await joinFuture;
      expect(client.currentRoom, '123456');
      expect(client.username, 'aslan_');
      await client.disconnect();
      await socket.close();
    });

    test('throws when server does not confirm room join in time', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      servers.add(server);
      final socketReady = Completer<Socket>();

      server.listen((clientSocket) {
        socketReady.complete(clientSocket);
      });

      final client = SyncplayClient(
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
      );
      await client.connect(enableTLS: false);
      final socket = await socketReady.future;

      await expectLater(
        client.joinRoom(
          '123456',
          'aslan',
          joinTimeout: const Duration(milliseconds: 20),
        ),
        throwsA(isA<SyncplayConnectionException>()),
      );
      expect(client.currentRoom, isNull);

      await client.disconnect();
      await socket.close();
    });

    test('does not emit playback changes for server ping state without sender',
        () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      servers.add(server);
      late Socket socket;
      final socketReady = Completer<void>();

      server.listen((clientSocket) {
        socket = clientSocket;
        socketReady.complete();
      });

      final client = SyncplayClient(
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
      );
      final receivedPositions = <Map<String, dynamic>>[];
      final subscription = client.onPositionChangedMessage.listen(
        receivedPositions.add,
      );
      addTearDown(subscription.cancel);

      await client.connect(enableTLS: false);
      await socketReady.future;

      final joinFuture = client.joinRoom(
        '123456',
        'aslan',
        joinTimeout: const Duration(milliseconds: 200),
      );
      socket.write(
        '{"Hello":{"username":"aslan","room":{"name":"123456"},"version":"1.7.0"}}\r\n',
      );
      await joinFuture;

      socket.write(
        '{"State":{"ping":{"clientLatencyCalculation":1.0},"playstate":{"position":0.0,"paused":true}}}\r\n',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(receivedPositions, isEmpty);

      await client.disconnect();
      await socket.close();
    });

    test('does not emit playback changes for server nobody state', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      servers.add(server);
      late Socket socket;
      final socketReady = Completer<void>();

      server.listen((clientSocket) {
        socket = clientSocket;
        socketReady.complete();
      });

      final client = SyncplayClient(
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
      );
      final receivedPositions = <Map<String, dynamic>>[];
      final subscription = client.onPositionChangedMessage.listen(
        receivedPositions.add,
      );
      addTearDown(subscription.cancel);

      await client.connect(enableTLS: false);
      await socketReady.future;

      final joinFuture = client.joinRoom(
        '123456',
        'aslan',
        joinTimeout: const Duration(milliseconds: 200),
      );
      socket.write(
        '{"Hello":{"username":"aslan","room":{"name":"123456"},"version":"1.7.0"}}\r\n',
      );
      await joinFuture;

      socket.write(
        '${jsonEncode({
              'State': {
                'ping': {'clientLatencyCalculation': 1.0},
                'playstate': {
                  'position': 0.0,
                  'paused': true,
                  'setBy': 'Nobody',
                },
              },
            })}\r\n',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(receivedPositions, isEmpty);

      await client.disconnect();
      await socket.close();
    });

    test('emits latency updates for heartbeat states without playback changes',
        () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      servers.add(server);
      late Socket socket;
      final socketReady = Completer<void>();

      server.listen((clientSocket) {
        socket = clientSocket;
        socketReady.complete();
      });

      final client = SyncplayClient(
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
      );
      final receivedPositions = <Map<String, dynamic>>[];
      final receivedLatencies = <Map<String, dynamic>>[];
      final positionSubscription = client.onPositionChangedMessage.listen(
        receivedPositions.add,
      );
      final latencySubscription = client.onLatencyChangedMessage.listen(
        receivedLatencies.add,
      );
      addTearDown(positionSubscription.cancel);
      addTearDown(latencySubscription.cancel);

      await client.connect(enableTLS: false);
      await socketReady.future;

      final joinFuture = client.joinRoom(
        '123456',
        'aslan',
        joinTimeout: const Duration(milliseconds: 200),
      );
      socket.write(
        '{"Hello":{"username":"aslan","room":{"name":"123456"},"version":"1.7.0"}}\r\n',
      );
      await joinFuture;

      final timestamp = DateTime.now().millisecondsSinceEpoch / 1000.0;
      socket.write(
        '${jsonEncode({
              'State': {
                'ping': {
                  'clientLatencyCalculation': timestamp,
                  'serverRtt': 0.05,
                },
                'playstate': {
                  'position': 0.0,
                  'paused': true,
                  'setBy': 'Nobody',
                },
              },
            })}\r\n',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(receivedPositions, isEmpty);
      expect(receivedLatencies, hasLength(1));
      expect(receivedLatencies.single['clientRtt'], isNonNegative);
      expect(receivedLatencies.single['serverRtt'], 0.05);

      await client.disconnect();
      await socket.close();
    });

    test('emits playback changes from another user', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      servers.add(server);
      late Socket socket;
      final socketReady = Completer<void>();

      server.listen((clientSocket) {
        socket = clientSocket;
        socketReady.complete();
      });

      final client = SyncplayClient(
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
      );
      final receivedPositions = <Map<String, dynamic>>[];
      final subscription = client.onPositionChangedMessage.listen(
        receivedPositions.add,
      );
      addTearDown(subscription.cancel);

      await client.connect(enableTLS: false);
      await socketReady.future;

      final joinFuture = client.joinRoom(
        '123456',
        'aslan',
        joinTimeout: const Duration(milliseconds: 200),
      );
      socket.write(
        '{"Hello":{"username":"aslan","room":{"name":"123456"},"version":"1.7.0"}}\r\n',
      );
      await joinFuture;

      socket.write(
        '{"State":{"ping":{"clientLatencyCalculation":1.0},"playstate":{"position":30.0,"paused":false,"setBy":"friend"}}}\r\n',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(receivedPositions, hasLength(1));
      expect(receivedPositions.single['position'], 30.0);
      expect(receivedPositions.single['paused'], isFalse);
      expect(receivedPositions.single['setBy'], 'friend');

      await client.disconnect();
      await socket.close();
    });
  });
}
