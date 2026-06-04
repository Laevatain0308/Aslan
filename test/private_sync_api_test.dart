import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/sync/private_sync_models.dart';
import 'package:kazumi/request/apis/private_sync_api.dart';

void main() {
  test('register posts account details without bearer token', () async {
    final adapter = _FakeAdapter((options) {
      expect(options.path, 'https://sync.example/api/sync/register');
      expect(options.headers.containsKey('Authorization'), false);
      final body = Map<String, dynamic>.from(options.data as Map);
      expect(body['loginName'], 'alice');
      expect(body['displayName'], 'Alice');
      expect(body['password'], 'password-password');
      expect(body['inviteCode'], 'invite-code');
      expect(body['deviceId'], 'device-a');
      expect(body['deviceName'], 'Phone');
      return {
        'data': {
          'user': {'displayName': 'Alice'},
          'deviceId': 'device-a',
          'token': 'lbst_token',
        },
        'updatedAt': '2026-06-04T00:00:00.000Z',
        'meta': {'warnings': []},
      };
    });
    final api = PrivateSyncApi(
      dio: Dio()..httpClientAdapter = adapter,
      baseUrl: 'https://sync.example/api',
      token: 'unused-token',
    );

    final result = await api.registerAccount(
      loginName: 'alice',
      displayName: 'Alice',
      password: 'password-password',
      inviteCode: 'invite-code',
      deviceId: 'device-a',
      deviceName: 'Phone',
      platform: 'ios',
      appVersion: '1.0.0',
    );

    expect(result.displayName, 'Alice');
    expect(result.deviceId, 'device-a');
    expect(result.token, 'lbst_token');
  });

  test('login posts credentials without bearer token', () async {
    final adapter = _FakeAdapter((options) {
      expect(options.path, 'https://sync.example/api/sync/login');
      expect(options.headers.containsKey('Authorization'), false);
      final body = Map<String, dynamic>.from(options.data as Map);
      expect(body['loginName'], 'alice');
      expect(body['password'], 'password-password');
      expect(body['deviceId'], 'device-a');
      return {
        'data': {
          'user': {'displayName': 'Alice'},
          'deviceId': 'device-a',
          'token': 'lbst_token',
        },
        'updatedAt': '2026-06-04T00:00:00.000Z',
        'meta': {'warnings': []},
      };
    });
    final api = PrivateSyncApi(
      dio: Dio()..httpClientAdapter = adapter,
      baseUrl: 'https://sync.example/api',
      token: 'unused-token',
    );

    final result = await api.login(
      loginName: 'alice',
      password: 'password-password',
      deviceId: 'device-a',
      deviceName: 'Phone',
    );

    expect(result.displayName, 'Alice');
    expect(result.deviceId, 'device-a');
    expect(result.token, 'lbst_token');
  });

  test('status sends bearer token and parses counts', () async {
    final adapter = _FakeAdapter((options) {
      expect(options.path, 'https://sync.example/api/sync/status');
      expect(options.headers['Authorization'], 'Bearer test-token');
      return {
        'data': {
          'user': {'displayName': 'Alice'},
          'devices': [],
          'watchHistoryCount': 2,
          'collectionCount': 3,
        },
        'updatedAt': '2026-06-04T00:00:00.000Z',
        'meta': {'warnings': []},
      };
    });
    final api = PrivateSyncApi(
      dio: Dio()..httpClientAdapter = adapter,
      baseUrl: 'https://sync.example/api',
      token: 'test-token',
    );

    final status = await api.status();

    expect(status.displayName, 'Alice');
    expect(status.watchHistoryCount, 2);
    expect(status.collectionCount, 3);
  });

  test('merge posts events and parses snapshot', () async {
    final adapter = _FakeAdapter((options) {
      expect(options.path, 'https://sync.example/api/sync/merge');
      final body = Map<String, dynamic>.from(options.data as Map);
      expect(body['deviceId'], 'device-a');
      expect((body['events'] as List).single['eventId'], 'device-a:1');
      return {
        'data': {
          'acceptedEventIds': ['device-a:1'],
          'ignoredDuplicateEventIds': [],
          'snapshot': {
            'generatedAt': 1000,
            'watch': {'clearVersion': null, 'histories': []},
            'collection': {'clearVersion': null, 'items': []},
          },
        },
        'updatedAt': '2026-06-04T00:00:00.000Z',
        'meta': {'warnings': []},
      };
    });
    final api = PrivateSyncApi(
      dio: Dio()..httpClientAdapter = adapter,
      baseUrl: 'https://sync.example/api/',
      token: 'test-token',
    );

    final result = await api.merge(
      deviceId: 'device-a',
      clientSeq: 1,
      events: [
        const PrivateSyncEvent(
          eventId: 'device-a:1',
          deviceId: 'device-a',
          seq: 1,
          domain: 'watch',
          op: 'watch.clearAll',
          updatedAt: 1000,
          payload: {},
        ),
      ],
    );

    expect(result.acceptedEventIds, ['device-a:1']);
    expect(result.snapshot.generatedAt, 1000);
  });

  test('logout posts bearer token to revoke the current session', () async {
    final adapter = _FakeAdapter((options) {
      expect(options.path, 'https://sync.example/api/sync/logout');
      expect(options.headers['Authorization'], 'Bearer test-token');
      expect(options.data, isA<Map>());
      return {
        'data': {'revoked': true},
        'updatedAt': '2026-06-04T00:00:00.000Z',
        'meta': {'warnings': []},
      };
    });
    final api = PrivateSyncApi(
      dio: Dio()..httpClientAdapter = adapter,
      baseUrl: 'https://sync.example/api',
      token: 'test-token',
    );

    await api.logout();
  });

  test('401 responses throw an authentication exception', () async {
    final adapter = _FakeAdapter(
      (_) => {
        'error': {
          'code': 'unauthorized',
          'message': 'missing or invalid token',
        },
      },
      statusCode: 401,
    );
    final api = PrivateSyncApi(
      dio: Dio()..httpClientAdapter = adapter,
      baseUrl: 'https://sync.example/api',
      token: 'bad-token',
    );

    await expectLater(
      api.status(),
      throwsA(isA<PrivateSyncAuthenticationException>()),
    );
  });

  test('known sync error codes use localized exception messages', () async {
    final adapter = _FakeAdapter(
      (_) => {
        'data': null,
        'updatedAt': '2026-06-04T00:00:00.000Z',
        'meta': {
          'freshness': 'error',
          'warnings': ['Invalid or expired sync invite'],
          'error': 'invalid_invite',
        },
      },
      statusCode: 401,
    );
    final api = PrivateSyncApi(
      dio: Dio()..httpClientAdapter = adapter,
      baseUrl: 'https://sync.example/api',
      token: 'bad-token',
    );

    await expectLater(
      api.registerAccount(
        loginName: 'alice',
        displayName: 'Alice',
        password: 'password-password',
        inviteCode: 'bad-invite',
        deviceId: 'device-a',
        deviceName: 'Phone',
      ),
      throwsA(
        isA<PrivateSyncAuthenticationException>().having(
          (error) => error.message,
          'message',
          '邀请码无效或已过期',
        ),
      ),
    );
  });

  test(
      'unknown error envelopes use the first server warning as the exception message',
      () async {
    final adapter = _FakeAdapter(
      (_) => {
        'data': null,
        'updatedAt': '2026-06-04T00:00:00.000Z',
        'meta': {
          'freshness': 'error',
          'warnings': ['Something failed'],
          'error': 'unknown_error',
        },
      },
      statusCode: 500,
    );
    final api = PrivateSyncApi(
      dio: Dio()..httpClientAdapter = adapter,
      baseUrl: 'https://sync.example/api',
      token: 'bad-token',
    );

    await expectLater(
      api.status(),
      throwsA(
        isA<PrivateSyncApiException>().having(
          (error) => error.message,
          'message',
          'Something failed',
        ),
      ),
    );
  });
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler, {this.statusCode = 200});

  final Map<String, dynamic> Function(RequestOptions options) handler;
  final int statusCode;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final response = handler(options);
    return ResponseBody.fromString(
      jsonEncode(response),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
