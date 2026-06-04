import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:kazumi/modules/sync/private_sync_models.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/request/core/network_config.dart';
import 'package:kazumi/services/storage/storage.dart';

abstract class PrivateSyncApiClient {
  Future<PrivateSyncAuthResult> registerAccount({
    required String loginName,
    required String displayName,
    required String password,
    required String inviteCode,
    required String deviceId,
    required String deviceName,
    String? platform,
    String? appVersion,
  });

  Future<PrivateSyncAuthResult> login({
    required String loginName,
    required String password,
    required String deviceId,
    required String deviceName,
    String? platform,
    String? appVersion,
  });

  Future<PrivateSyncStatus> status();

  Future<void> logout();

  Future<PrivateSyncDeviceRegistration> registerDevice({
    required String deviceId,
    required String deviceName,
    String? platform,
    String? appVersion,
  });

  Future<PrivateSyncMergeResult> merge({
    required String deviceId,
    required int clientSeq,
    required List<PrivateSyncEvent> events,
  });
}

class PrivateSyncApi implements PrivateSyncApiClient {
  PrivateSyncApi({
    Dio? dio,
    String? baseUrl,
    String? token,
  })  : _dio = dio ??
            DioFactory.createForConfig(
              const NetworkConfig(
                connectTimeout: Duration(seconds: 10),
                receiveTimeout: Duration(seconds: 20),
              ),
            ),
        _baseUrl = _normalizeBaseUrl(baseUrl ?? _settingsBaseUrl()),
        _token = token ?? _settingsToken();

  final Dio _dio;
  final String _baseUrl;
  final String _token;

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
    final envelope = await _postPublic('/sync/register', {
      'loginName': loginName,
      'displayName': displayName,
      'password': password,
      'inviteCode': inviteCode,
      'deviceId': deviceId,
      'deviceName': deviceName,
      if (platform != null) 'platform': platform,
      if (appVersion != null) 'appVersion': appVersion,
    });
    return PrivateSyncAuthResult.fromJson(
      Map<String, dynamic>.from(envelope['data'] as Map),
    );
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
    final envelope = await _postPublic('/sync/login', {
      'loginName': loginName,
      'password': password,
      'deviceId': deviceId,
      'deviceName': deviceName,
      if (platform != null) 'platform': platform,
      if (appVersion != null) 'appVersion': appVersion,
    });
    return PrivateSyncAuthResult.fromJson(
      Map<String, dynamic>.from(envelope['data'] as Map),
    );
  }

  @override
  Future<PrivateSyncStatus> status() async {
    final envelope = await _get('/sync/status');
    return PrivateSyncStatus.fromJson(
      Map<String, dynamic>.from(envelope['data'] as Map),
    );
  }

  @override
  Future<void> logout() async {
    await _post('/sync/logout', const {});
  }

  @override
  Future<PrivateSyncDeviceRegistration> registerDevice({
    required String deviceId,
    required String deviceName,
    String? platform,
    String? appVersion,
  }) async {
    final envelope = await _post('/sync/register-device', {
      'deviceId': deviceId,
      'deviceName': deviceName,
      if (platform != null) 'platform': platform,
      if (appVersion != null) 'appVersion': appVersion,
    });
    return PrivateSyncDeviceRegistration.fromJson(
      Map<String, dynamic>.from(envelope['data'] as Map),
    );
  }

  @override
  Future<PrivateSyncMergeResult> merge({
    required String deviceId,
    required int clientSeq,
    required List<PrivateSyncEvent> events,
  }) async {
    final envelope = await _post('/sync/merge', {
      'deviceId': deviceId,
      'clientSeq': clientSeq,
      'events': events.map((event) => event.toJson()).toList(),
    });
    return PrivateSyncMergeResult.fromJson(
      Map<String, dynamic>.from(envelope['data'] as Map),
    );
  }

  Future<Map<String, dynamic>> _get(String path) async {
    try {
      final response = await _dio.get(
        '$_baseUrl$path',
        options: Options(headers: _headers),
      );
      return _decodeResponse(response);
    } on DioException catch (e) {
      throw _mapDioException(e);
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _dio.post(
        '$_baseUrl$path',
        data: body,
        options: Options(headers: _headers),
      );
      return _decodeResponse(response);
    } on DioException catch (e) {
      throw _mapDioException(e);
    }
  }

  Future<Map<String, dynamic>> _postPublic(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _dio.post(
        '$_baseUrl$path',
        data: body,
        options: Options(headers: const {
          'Content-Type': Headers.jsonContentType,
        }),
      );
      return _decodeResponse(response);
    } on DioException catch (e) {
      throw _mapDioException(e);
    }
  }

  Map<String, dynamic> get _headers => {
        'Authorization': 'Bearer $_token',
        'Content-Type': Headers.jsonContentType,
      };

  static Map<String, dynamic> _decodeResponse(Response<dynamic> response) {
    final raw = response.data;
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw PrivateSyncAuthenticationException(
        _extractErrorMessage(raw) ?? '同步密钥无效或已失效',
      );
    }
    if ((response.statusCode ?? 200) >= 400) {
      throw PrivateSyncApiException(
        _extractErrorMessage(raw) ?? '数据同步请求失败',
      );
    }
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    if (raw is String) {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    }
    throw const PrivateSyncApiException('同步响应格式无效');
  }

  static String? _extractErrorMessage(dynamic raw) {
    if (raw is String) {
      try {
        return _extractErrorMessage(jsonDecode(raw));
      } catch (_) {
        return raw;
      }
    }
    if (raw is Map) {
      final meta = raw['meta'];
      if (meta is Map) {
        final localized = _localizedErrorCode(meta['error']?.toString());
        if (localized != null) {
          return localized;
        }
      }
      final error = raw['error'];
      if (error is Map && error['message'] != null) {
        return error['message'].toString();
      }
      if (raw['message'] != null) {
        return raw['message'].toString();
      }
      if (meta is Map) {
        final warnings = meta['warnings'];
        if (warnings is List && warnings.isNotEmpty) {
          return warnings.first.toString();
        }
      }
    }
    return null;
  }

  static String? _localizedErrorCode(String? code) {
    switch (code) {
      case 'invalid_invite':
        return '邀请码无效或已过期';
      case 'invalid_credentials':
        return '账号或密码不正确';
      case 'unauthorized':
        return '同步密钥无效或已失效';
      default:
        return null;
    }
  }

  static PrivateSyncApiException _mapDioException(DioException e) {
    final statusCode = e.response?.statusCode;
    if (statusCode == 401 || statusCode == 403) {
      return PrivateSyncAuthenticationException(
        _extractErrorMessage(e.response?.data) ?? '同步密钥无效或已失效',
      );
    }
    return PrivateSyncApiException(
      _extractErrorMessage(e.response?.data) ?? e.message ?? '数据同步请求失败',
    );
  }

  static String _normalizeBaseUrl(String value) {
    final normalized = value.trim().replaceFirst(RegExp(r'/+$'), '');
    if (normalized.isEmpty) {
      throw const PrivateSyncApiException('请先配置服务地址');
    }
    return normalized;
  }

  static String _settingsBaseUrl() {
    return GStorage.setting
        .get(
          SettingBoxKey.laevaBangumiServerUrl,
          defaultValue: ApiEndpoints.laevaBangumiDefaultApiBase,
        )
        .toString();
  }

  static String _settingsToken() {
    final token = GStorage.setting
        .get(SettingBoxKey.privateSyncToken, defaultValue: '')
        .toString()
        .trim();
    if (token.isEmpty) {
      throw const PrivateSyncApiException('请先配置同步密钥');
    }
    return token;
  }
}

class PrivateSyncAuthResult {
  const PrivateSyncAuthResult({
    required this.displayName,
    required this.deviceId,
    required this.token,
  });

  final String displayName;
  final String deviceId;
  final String token;

  factory PrivateSyncAuthResult.fromJson(Map<String, dynamic> json) {
    final user = Map<String, dynamic>.from((json['user'] as Map?) ?? const {});
    return PrivateSyncAuthResult(
      displayName: user['displayName'] as String? ?? '',
      deviceId: json['deviceId'] as String? ?? '',
      token: json['token'] as String? ?? '',
    );
  }
}

class PrivateSyncStatus {
  const PrivateSyncStatus({
    required this.displayName,
    required this.devices,
    required this.watchHistoryCount,
    required this.collectionCount,
  });

  final String displayName;
  final List<PrivateSyncDevice> devices;
  final int watchHistoryCount;
  final int collectionCount;

  factory PrivateSyncStatus.fromJson(Map<String, dynamic> json) {
    final user = Map<String, dynamic>.from((json['user'] as Map?) ?? const {});
    return PrivateSyncStatus(
      displayName: user['displayName'] as String? ?? '',
      devices: ((json['devices'] as List?) ?? const [])
          .map(
            (item) => PrivateSyncDevice.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
      watchHistoryCount: (json['watchHistoryCount'] as num?)?.toInt() ?? 0,
      collectionCount: (json['collectionCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class PrivateSyncDeviceRegistration {
  const PrivateSyncDeviceRegistration({
    required this.displayName,
    required this.deviceId,
  });

  final String displayName;
  final String deviceId;

  factory PrivateSyncDeviceRegistration.fromJson(Map<String, dynamic> json) {
    final user = Map<String, dynamic>.from((json['user'] as Map?) ?? const {});
    return PrivateSyncDeviceRegistration(
      displayName: user['displayName'] as String? ?? '',
      deviceId: json['deviceId'] as String? ?? '',
    );
  }
}

class PrivateSyncDevice {
  const PrivateSyncDevice({
    required this.deviceId,
    this.deviceName,
    this.platform,
    this.appVersion,
    this.firstSeenAt,
    this.lastSeenAt,
  });

  final String deviceId;
  final String? deviceName;
  final String? platform;
  final String? appVersion;
  final String? firstSeenAt;
  final String? lastSeenAt;

  factory PrivateSyncDevice.fromJson(Map<String, dynamic> json) {
    return PrivateSyncDevice(
      deviceId: json['deviceId'] as String? ?? '',
      deviceName: json['deviceName'] as String?,
      platform: json['platform'] as String?,
      appVersion: json['appVersion'] as String?,
      firstSeenAt: json['firstSeenAt'] as String?,
      lastSeenAt: json['lastSeenAt'] as String?,
    );
  }
}

class PrivateSyncMergeResult {
  const PrivateSyncMergeResult({
    required this.acceptedEventIds,
    required this.ignoredDuplicateEventIds,
    required this.snapshot,
  });

  final List<String> acceptedEventIds;
  final List<String> ignoredDuplicateEventIds;
  final PrivateSyncSnapshot snapshot;

  factory PrivateSyncMergeResult.fromJson(Map<String, dynamic> json) {
    return PrivateSyncMergeResult(
      acceptedEventIds: ((json['acceptedEventIds'] as List?) ?? const [])
          .map((eventId) => eventId.toString())
          .toList(),
      ignoredDuplicateEventIds:
          ((json['ignoredDuplicateEventIds'] as List?) ?? const [])
              .map((eventId) => eventId.toString())
              .toList(),
      snapshot: PrivateSyncSnapshot.fromJson(
        Map<String, dynamic>.from(json['snapshot'] as Map),
      ),
    );
  }
}

class PrivateSyncApiException implements Exception {
  const PrivateSyncApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PrivateSyncAuthenticationException extends PrivateSyncApiException {
  const PrivateSyncAuthenticationException(super.message);
}
