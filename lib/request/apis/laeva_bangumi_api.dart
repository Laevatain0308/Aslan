import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/laeva/laeva_bangumi_models.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/request/core/network_config.dart';
import 'package:kazumi/services/storage/storage.dart';

class LaevaBangumiApi {
  LaevaBangumiApi._();

  static Dio get _dio => DioFactory.createForConfig(
        const NetworkConfig(
          connectTimeout: Duration(seconds: 10),
          receiveTimeout: Duration(seconds: 20),
        ),
      );

  static String get baseUrl {
    final stored = GStorage.setting
        .get(
          SettingBoxKey.laevaBangumiServerUrl,
          defaultValue: ApiEndpoints.laevaBangumiDefaultApiBase,
        )
        .toString()
        .trim();
    final value =
        stored.isEmpty ? ApiEndpoints.laevaBangumiDefaultApiBase : stored;
    return value.replaceFirst(RegExp(r'/+$'), '');
  }

  static Future<List<LaevaBangumiUpdateItem>> getUpdates({
    int days = 7,
    int limit = 24,
  }) async {
    final data = await _get(
      '/updates',
      queryParameters: {
        'days': days,
        'limit': limit,
      },
    );
    final list = data as List<dynamic>? ?? const [];
    return list
        .whereType<Map>()
        .map(
          (item) =>
              LaevaBangumiUpdateItem.fromJson(Map<String, dynamic>.from(item)),
        )
        .where((item) => item.id > 0 && item.title.isNotEmpty)
        .toList();
  }

  static Future<List<List<BangumiItem>>> getCalendar() async {
    final data = await _get('/calendar');
    final days = data as List<dynamic>? ?? const [];
    final calendar = List.generate(7, (_) => <BangumiItem>[]);
    for (final dayJson in days.whereType<Map>()) {
      final day = LaevaBangumiCalendarDay.fromJson(
        Map<String, dynamic>.from(dayJson),
      );
      if (day.weekdayId < 1 || day.weekdayId > 7) {
        continue;
      }
      calendar[day.weekdayId - 1] = day.toBangumiItems();
    }
    return calendar;
  }

  static Future<List<LaevaBangumiSearchItem>> search(
    String keyword, {
    bool byTag = false,
  }) async {
    final data = await _get(
      '/search',
      queryParameters: byTag ? {'tag': keyword} : {'q': keyword},
    );
    final list = data as List<dynamic>? ?? const [];
    return list
        .whereType<Map>()
        .map(
          (item) =>
              LaevaBangumiSearchItem.fromJson(Map<String, dynamic>.from(item)),
        )
        .where((item) => item.id > 0 && item.title.isNotEmpty)
        .toList();
  }

  static Future<LaevaBangumiDetail?> getDetail(int id) async {
    final data = await _get('/detail', queryParameters: {'id': id});
    if (data is! Map) {
      return null;
    }
    return LaevaBangumiDetail.fromJson(Map<String, dynamic>.from(data));
  }

  static Future<LaevaBangumiPlayData?> getPlayUrl({
    required int id,
    required int channel,
    required int episode,
  }) async {
    final data = await _get(
      '/play',
      queryParameters: {'id': id, 'ch': channel, 'ep': episode},
    );
    if (data is! Map) {
      return null;
    }
    final playData = LaevaBangumiPlayData.fromJson(
      Map<String, dynamic>.from(data),
    );
    if (playData.videoUrl.isEmpty) {
      return null;
    }
    return playData;
  }

  static Future<dynamic> _get(
    String path, {
    Map<String, dynamic> queryParameters = const {},
  }) async {
    final response = await _dio.get(
      '$baseUrl$path',
      queryParameters: queryParameters,
    );
    final json = _decodeResponse(response);
    if (json['data'] == null) {
      final meta = json['meta'];
      if (meta is Map && meta['warnings'] is List) {
        throw LaevaBangumiApiException((meta['warnings'] as List).join(', '));
      }
      throw const LaevaBangumiApiException('LaevaBangumi returned empty data');
    }
    return json['data'];
  }

  static Map<String, dynamic> _decodeResponse(Response<dynamic> response) {
    final raw = response.data;
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
    throw const LaevaBangumiApiException('Invalid LaevaBangumi response');
  }
}

class LaevaBangumiApiException implements Exception {
  const LaevaBangumiApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
