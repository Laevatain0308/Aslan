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

  static Future<LaevaBangumiApiEnvelope<List<LaevaBangumiUpdateItem>>>
      getUpdates({
    int days = 7,
    int limit = 24,
  }) async {
    final response = await _getEnvelope(
      '/updates',
      queryParameters: {
        'days': days,
        'limit': limit,
      },
    );
    final list = response.data as List<dynamic>? ?? const [];
    return response.mapData((_) => list
        .whereType<Map>()
        .map(
          (item) =>
              LaevaBangumiUpdateItem.fromJson(Map<String, dynamic>.from(item)),
        )
        .where((item) => item.id > 0 && item.title.isNotEmpty)
        .toList());
  }

  static Future<LaevaBangumiApiEnvelope<List<List<BangumiItem>>>>
      getCalendar() async {
    final response = await _getEnvelope('/calendar');
    final days = response.data as List<dynamic>? ?? const [];
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
    return response.mapData((_) => calendar);
  }

  static Future<LaevaBangumiApiEnvelope<List<LaevaBangumiSearchItem>>> search(
    String keyword, {
    bool byTag = false,
  }) async {
    final response = await _getEnvelope(
      '/search',
      queryParameters: byTag ? {'tag': keyword} : {'q': keyword},
    );
    final list = response.data as List<dynamic>? ?? const [];
    return response.mapData((_) => list
        .whereType<Map>()
        .map(
          (item) =>
              LaevaBangumiSearchItem.fromJson(Map<String, dynamic>.from(item)),
        )
        .where((item) => item.id > 0 && item.title.isNotEmpty)
        .toList());
  }

  static Future<LaevaBangumiApiEnvelope<LaevaBangumiDetail>?> getDetail(
      int id) async {
    final response = await _getEnvelope('/detail', queryParameters: {'id': id});
    final data = response.data;
    if (data is! Map) {
      return null;
    }
    return LaevaBangumiApiEnvelope<LaevaBangumiDetail>(
      data: LaevaBangumiDetail.fromJson(Map<String, dynamic>.from(data)),
      updatedAt: response.updatedAt,
      meta: response.meta,
    );
  }

  static Future<LaevaBangumiApiEnvelope<LaevaBangumiPlayData>?> getPlayUrl({
    required int id,
    required int channel,
    required int episode,
  }) async {
    final response = await _getEnvelope(
      '/play',
      queryParameters: {'id': id, 'ch': channel, 'ep': episode},
    );
    final data = response.data;
    if (data is! Map) {
      return null;
    }
    final playData = LaevaBangumiPlayData.fromJson(
      Map<String, dynamic>.from(data),
    );
    if (playData.videoUrl.isEmpty) {
      return null;
    }
    return response.mapData((_) => playData);
  }

  static Future<LaevaBangumiApiEnvelope<dynamic>> _getEnvelope(
    String path, {
    Map<String, dynamic> queryParameters = const {},
  }) async {
    final response = await _dio.get(
      '$baseUrl$path',
      queryParameters: queryParameters,
    );
    final json = _decodeResponse(response);
    final meta = json['meta'] is Map
        ? LaevaBangumiApiMeta.fromJson(Map<String, dynamic>.from(json['meta']))
        : LaevaBangumiApiMeta.fromJson(const {});
    if (json['data'] == null) {
      if (meta.warnings.isNotEmpty) {
        throw LaevaBangumiApiException(meta.warnings.join(', '));
      }
      throw const LaevaBangumiApiException('LaevaBangumi returned empty data');
    }
    return LaevaBangumiApiEnvelope<dynamic>(
      data: json['data'],
      updatedAt: json['updatedAt']?.toString(),
      meta: meta,
    );
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
